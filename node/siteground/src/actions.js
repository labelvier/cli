import { resolve4 } from 'node:dns/promises';
import { randomBytes } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, writeFile, mkdir, chmod } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';
import { STATE_DIR } from './session.js';

const CREDENTIALS_DIR = path.join(STATE_DIR, '.credentials');

export const SSH_PORT = 18765;

const execFileAsync = promisify(execFile);

export function generatePassword() {
	// Mixed case + digit + symbol so SiteGround's password rules always pass.
	return `${randomBytes(18).toString('base64url')}a1!`;
}

/** Merge secrets into .credentials/<domain>.json (in STATE_DIR, 0600). Returns the file path. */
export async function storeCredentials(domain, data) {
	await mkdir(CREDENTIALS_DIR, { recursive: true, mode: 0o700 });
	const file = path.join(CREDENTIALS_DIR, `${domain}.json`);
	const current = existsSync(file) ? JSON.parse(await readFile(file, 'utf8')) : { domain };
	await writeFile(file, JSON.stringify({ ...current, ...data }, null, 2));
	await chmod(file, 0o600);
	return file;
}

/**
 * Hosting accounts enriched with site count and disk usage, for display and selection.
 * Note: accounts[].quota_info.usage is the number of sites, not a disk percentage.
 */
export async function accountsOverview(sg) {
	const [accounts, sites] = await Promise.all([sg.accounts(), sg.sites()]);
	return Promise.all(
		accounts.map(async (a) => {
			const disk = await sg.get(`/account/${a.id}/stats/disk`).catch(() => null); // MB
			return {
				...a,
				siteCount: sites.filter((s) => s.account_id === a.id).length,
				diskUsedGb: disk ? disk.total / 1024 : null,
				diskLimitGb: disk ? disk.limit / 1024 : null,
			};
		}),
	);
}

export function describeAccount(a) {
	const disk =
		a.diskLimitGb != null
			? `${a.diskUsedGb.toFixed(0)}/${a.diskLimitGb.toFixed(0)} GB (${Math.round((a.diskUsedGb / a.diskLimitGb) * 100)}%), ${(a.diskLimitGb - a.diskUsedGb).toFixed(0)} GB free`
			: 'disk usage unknown';
	return `${a.name.padEnd(22)} ${String(a.siteCount).padStart(3)} sites  ${disk.padEnd(34)} ${a.plan_description.replace(/\s+/g, ' ')}  ${a.server.location}`;
}

/**
 * Disk usage of one site, from the stats of its hosting account (MB):
 * { siteMb, accountMb, limitMb }, siteMb null when the account lists no figure for the site.
 */
export async function siteDiskUsage(sg, site) {
	const disk = await sg.get(`/account/${site.account_id}/stats/disk`);
	const entry = (disk.site_stats_responses || []).find((s) => String(s.id) === String(site.id) || s.domain === site.domain);
	return { siteMb: entry ? entry.value : null, accountMb: disk.total, limitMb: disk.limit };
}

const formatMb = (mb) => (mb < 1024 ? `${Math.round(mb)} MB` : `${(mb / 1024).toFixed(1)} GB`);

export function describeDiskUsage(disk) {
	if (!disk) return 'unknown';
	const hasLimit = disk.limitMb > 0;
	const plan = hasLimit ? `plan ${formatMb(disk.accountMb)} of ${formatMb(disk.limitMb)}` : `plan ${formatMb(disk.accountMb)}`;
	if (disk.siteMb == null) return `unknown (${plan})`;
	return `${formatMb(disk.siteMb)} (${hasLimit ? `${Math.round((disk.siteMb / disk.limitMb) * 100)}% of plan; ` : ''}${plan})`;
}

export async function findSite(sg, domain) {
	const site = (await sg.sites()).find((s) => s.domain === domain);
	if (!site) throw new Error(`No site found for ${domain}`);
	return site;
}

export const USAGE_METRICS = { cpu: 'cpu_seconds', exec: 'program_executions' };

/**
 * Sum a stats series per UTC day. Daily points are stamped 23:59:59 UTC; the API also
 * pads the range with zero points at other timestamps, which adds nothing.
 */
function perDay(points) {
	const days = {};
	for (const p of points) {
		const day = new Date(p.timestamp * 1000).toISOString().slice(0, 10);
		days[day] = (days[day] || 0) + (p.value || 0);
	}
	return days;
}

/**
 * Daily CPU seconds and program executions per site of a hosting account over the last `days` days.
 * Returns { days: ['YYYY-MM-DD', …], total: { cpu, exec }, sites: [{ id, domain, cpu, exec }] }
 * where cpu/exec map a day to its value.
 */
export async function siteUsage(sg, accountId, { days = 31 } = {}) {
	const to = Math.floor(Date.now() / 1000);
	const from = to - days * 86400;
	const entries = await Promise.all(
		Object.entries(USAGE_METRICS).map(async ([key, metric]) => [key, await sg.accountStats(accountId, metric, { from, to, step: 'd' })]),
	);
	const total = {};
	const sites = {};
	for (const [key, data] of entries) {
		total[key] = perDay(data.points);
		for (const s of data.aggregated_site_stats_responses || []) {
			sites[s.id] ??= { id: s.id, domain: s.domain, cpu: {}, exec: {} };
			sites[s.id][key] = perDay(s.points);
		}
	}
	const allDays = [...new Set(Object.values(total).flatMap((d) => Object.keys(d)))].sort();
	return { days: allDays.filter((d) => total.cpu[d] || total.exec[d]), total, sites: Object.values(sites) };
}

/**
 * Rank sites on a metric (cpu | exec): share of the account total, average per day in the last
 * `recentDays` complete days against the days before, and the growth factor between the two.
 * Today (UTC) is incomplete, so it only counts towards the total.
 */
export function rankSites(usage, key, { recentDays = 7 } = {}) {
	const today = new Date().toISOString().slice(0, 10);
	const complete = usage.days.filter((d) => d < today);
	const recent = complete.slice(-recentDays);
	const before = complete.slice(0, -recentDays);
	const avg = (series, days) => (days.length ? days.reduce((sum, d) => sum + (series[d] || 0), 0) / days.length : 0);
	const accountTotal = usage.days.reduce((sum, d) => sum + (usage.total[key][d] || 0), 0);
	return usage.sites
		.map((s) => {
			const series = s[key];
			const total = usage.days.reduce((sum, d) => sum + (series[d] || 0), 0);
			const peakDay = usage.days.reduce((best, d) => ((series[d] || 0) > (series[best] || 0) ? d : best), usage.days[0]);
			const avgBefore = avg(series, before);
			const avgRecent = avg(series, recent);
			return {
				domain: s.domain,
				total,
				share: accountTotal ? total / accountTotal : 0,
				avgBefore,
				avgRecent,
				growth: avgBefore ? avgRecent / avgBefore : null,
				peak: series[peakDay] || 0,
				peakDay,
			};
		})
		.sort((a, b) => b.total - a.total);
}

/** Does the domain's A record point at the given server IP? */
export async function dnsPointsTo(domain, ip) {
	try {
		return (await resolve4(domain)).includes(ip);
	} catch {
		return false;
	}
}

export function defaultSshKeyFile() {
	for (const name of ['id_ed25519.pub', 'id_ecdsa.pub', 'id_rsa.pub']) {
		const file = path.join(homedir(), '.ssh', name);
		if (existsSync(file)) return file;
	}
	return null;
}

// --- Site Tools actions -----------------------------------------------------
// They return a result line instead of printing, so the CLI can show it next to a spinner.
// `progress` is an optional spinner whose text is updated per sub-step.

export async function enableMemcached(st) {
	const r = await st.enableMemcached();
	return r.alreadyEnabled ? 'Memcached already enabled' : 'Memcached enabled (127.0.0.1:11211)';
}

export async function disableMemcached(st) {
	const svc = await st.memcached();
	if (!svc) return 'Memcached already disabled';
	await st.del(`/uservice/${svc.id}`);
	return 'Memcached disabled';
}

/**
 * Install Let's Encrypt when DNS points to the server; optionally force HTTPS.
 * strict: the domain must exist on the site (an alias), no fallback to the main domain.
 */
export async function setupSsl(st, { domain, serverIp, https = true, strict = false }, progress) {
	const d = (await st.domains()).find((x) => x.name === domain) || (strict ? null : await st.mainDomain());
	if (!d) return { ok: false, message: `${domain} is not a domain of this site` };
	if (progress) progress.text = `Checking DNS of ${d.name}…`;
	if (!(await dnsPointsTo(d.name, serverIp))) {
		return { ok: false, message: `SSL skipped: ${d.name} does not resolve to ${serverIp} yet` };
	}
	const parts = [];
	if (d.cert_id) {
		parts.push(`SSL certificate already installed on ${d.name}`);
	} else {
		if (progress) progress.text = `Installing Let's Encrypt certificate for ${d.name}…`;
		await st.installLetsEncrypt(d.id);
		parts.push(`Let's Encrypt installed on ${d.name} (+ www)`);
	}
	if (https) {
		if (progress) progress.text = 'Forcing HTTPS…';
		await st.enforceHttps(d, true);
		parts.push('HTTPS forced');
	}
	return { ok: true, message: parts.join(', ') };
}

/**
 * Park `alias` on a site (an alias of its main domain), then wait until Site Tools lists it.
 * Returns the message; an alias that is already there is left alone.
 */
export async function addDomainAlias(sg, st, site, alias, { intervalMs = 3000, attempts = 20 } = {}) {
	const name = alias.toLowerCase();
	const listed = async () => (await st.domains()).find((d) => d.name === name);
	if (await listed()) return `${name} is already a domain of ${site.domain}`;
	await sg.addDomainAlias(site.id, name, site.domain);
	for (let i = 0; i < attempts; i++) {
		if (await listed()) return `${name} parked on ${site.domain}`;
		await new Promise((r) => setTimeout(r, intervalMs));
	}
	throw new Error(`${name} was added but Site Tools does not list it yet; check with site:info`);
}

export async function addSshKey(st, { keyFile, comment }) {
	const keyPub = (await readFile(keyFile, 'utf8')).trim();
	const existing = (await st.sshKeys()).find((k) => k.key_pub.trim() === keyPub.split(' ').slice(0, 2).join(' ') || k.key_pub.trim() === keyPub);
	let message;
	if (existing) {
		message = `SSH key already authorized (${existing.comment})`;
	} else {
		await st.importSshKey(keyPub, comment || keyPub.split(' ')[2] || path.basename(keyFile));
		message = `SSH key ${path.basename(keyFile)} authorized`;
	}
	return { message, ssh: await sshCommand(st) };
}

export async function sshDetails(st) {
	const { data } = await st.request('GET', '/endpoint');
	const host = (await st.mainDomain()).config?.ssh_host || st.apiUrl;
	return { user: data.features.username, host, port: SSH_PORT };
}

export async function sshCommand(st) {
	const { user, host, port } = await sshDetails(st);
	return `ssh -p ${port} ${user}@${host}`;
}

/** Suggested alias: the part before the registrable domain (analytics.labelvier.dev -> analytics). */
export function defaultSshAlias(domain) {
	const labels = domain.split('.');
	return labels.length > 2 ? labels.slice(0, -2).join('.') : labels[0];
}

/**
 * Add a Host block to ~/.ssh/config through `labelvier ssh alias` so the format matches the rest
 * of the team's tooling. stdin is closed so labelvier never waits for input.
 */
export async function addSshAlias({ name, user, host, port, keyFile }) {
	const privateKey = keyFile?.replace(/\.pub$/, '');
	const identity = privateKey && existsSync(privateKey) ? privateKey.replace(homedir(), '~') : '';
	try {
		const run = execFileAsync('labelvier', ['ssh', 'alias', name, host, user, String(port), identity]);
		run.child.stdin.end(); // EOF for every `read` (update check, prompts)
		const { stdout } = await run;
		return { ok: true, message: stripAnsi(stdout).trim().split('\n')[0] || `Added alias '${name}'` };
	} catch (err) {
		if (err.code === 'ENOENT') return { ok: false, message: 'labelvier CLI not found, SSH alias not added' };
		const output = stripAnsi(`${err.stdout || ''}${err.stderr || ''}`).trim();
		return { ok: false, message: output.split('\n').pop() || `SSH alias '${name}' not added` };
	}
}

const stripAnsi = (s) => s.replace(/\x1b\[[0-9;]*m/g, '');

/** Create database + user with all privileges. Returns { label, name, user, password, host }. */
export async function createDatabase(st, { label }, progress) {
	const password = generatePassword();
	if (progress) progress.text = `Creating database "${label}"…`;
	const db = (await st.createDatabase(label)).data;
	if (progress) progress.text = `Creating database user "${label}"…`;
	const user = (await st.createDbUser(label, password)).data;
	if (progress) progress.text = 'Granting privileges…';
	await st.grantAll(db.id, user.id);
	return { label, name: db.name, user: user.name, password, host: 'localhost' };
}

// --- PHP ----------------------------------------------------------------------

/**
 * PHP versions available on the server of an account. Site Tools needs a site, so this asks
 * an existing site on the same account. Returns null when the account has no sites yet.
 */
export async function serverPhpVersions(sg, accountId) {
	const ref = (await sg.sites()).find((s) => s.account_id === accountId && s.status === 'active');
	if (!ref) return null;
	return sg.siteTools(ref.id).phpVersions();
}

/** Resolve "8.3", "83", "PHP 8.3" or "managed" to a version id (null = managed). */
export function parsePhpVersion(input, versions) {
	const value = String(input).trim().toLowerCase().replace(/^php\s*/, '');
	if (['managed', 'auto', 'default'].includes(value)) return null;
	const id = Number(value.replace('.', '').slice(0, 2));
	const match = versions?.find((v) => v.id === id);
	if (!match) throw new Error(`Unknown PHP version "${input}". Available: ${versions?.map((v) => v.version.replace(/^PHP (\d+\.\d+).*/, '$1')).join(', ') ?? 'unknown'}, managed`);
	return match.id;
}

export function phpLabel(versions, id) {
	if (id == null) {
		const def = versions?.find((v) => v.default);
		return `managed by SiteGround${def ? ` (now ${def.version})` : ''}`;
	}
	return versions?.find((v) => v.id === id)?.version ?? `PHP ${String(id)[0]}.${String(id).slice(1)}`;
}

export async function setPhpVersion(st, versionId) {
	const versions = await st.phpVersions();
	await st.setPhpVersion(versionId);
	return `PHP set to ${phpLabel(versions, versionId)}`;
}

// --- Cron ---------------------------------------------------------------------

const CRON_FIELDS = ['min', 'hour', 'day', 'mon', 'dow'];

/** Parse "* * * * *" (or @hourly/@daily/@weekly/@monthly) into { min, hour, day, mon, dow }. */
export function parseCronSchedule(input) {
	const aliases = { '@hourly': '0 * * * *', '@daily': '0 0 * * *', '@weekly': '0 0 * * 0', '@monthly': '0 0 1 * *' };
	const parts = (aliases[String(input).trim()] ?? String(input)).trim().split(/\s+/);
	if (parts.length !== 5 || parts.some((p) => !/^[\d*,\/-]+$/.test(p))) {
		throw new Error(`Invalid schedule "${input}": use 5 crontab fields like "*/5 * * * *", or @hourly/@daily/@weekly/@monthly`);
	}
	return Object.fromEntries(CRON_FIELDS.map((f, i) => [f, parts[i]]));
}

export const cronSchedule = (job) => CRON_FIELDS.map((f) => job[f]).join(' ');

/** Add a cron job unless the same command with the same schedule already exists. */
export async function addCronJob(st, { cmd, schedule }) {
	const fields = parseCronSchedule(schedule);
	const existing = (await st.cronJobs()).find((j) => j.cmd === cmd && cronSchedule(j) === cronSchedule(fields));
	if (existing) return { job: existing, message: `Cron job already exists (#${existing.id})` };
	const job = (await st.createCronJob(cmd, fields))?.data;
	return { job, message: `Cron job added${job?.id ? ` (#${job.id})` : ''}: ${cronSchedule(fields)} ${cmd}` };
}
