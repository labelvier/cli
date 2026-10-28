#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { existsSync } from 'node:fs';
import { SiteGroundClient } from './client.js';
import { interactiveLogin, setupLogin } from './login.js';
import { saveSession, loadSession, clearSession, decodeJwt, SESSION_FILE } from './session.js';

/** Expiry Date of a JWT; a clear error naming the field when it is not a JWT or has no exp. */
function jwtExpiry(token, what) {
	let payload;
	try {
		payload = decodeJwt(token);
	} catch (err) {
		throw new Error(`${what} is not a valid JWT (${err.message}). Run "labelvier siteground login" again or import a session exported from the browser.`);
	}
	if (typeof payload.exp !== 'number') throw new Error(`${what} is not a valid JWT (no "exp" claim)`);
	return new Date(payload.exp * 1000);
}
import { ask, confirm, select, closePrompt, interactive } from './prompt.js';
import { task } from './spinner.js';
import { demo, enableDemo, fakeActions, pause, withDemoPlans } from './demo.js';
import {
	accountsOverview,
	describeAccount,
	findSite,
	siteDiskUsage,
	describeDiskUsage,
	siteUsage,
	rankSites,
	dnsPointsTo,
	defaultSshKeyFile,
	generatePassword,
	storeCredentials,
	enableMemcached,
	disableMemcached,
	setupSsl,
	addSshKey,
	sshCommand,
	sshDetails,
	defaultSshAlias,
	addSshAlias,
	createDatabase,
	serverPhpVersions,
	parsePhpVersion,
	phpLabel,
	setPhpVersion,
	parseCronSchedule,
	cronSchedule,
	addCronJob,
	domainFromUrl,
	loginApps,
	adminLoginUrl,
	openInBrowser,
} from './actions.js';

const HELP = `Usage: labelvier siteground <command> [options]

Session
  setup                          Store email + password (and optionally the TOTP secret) for the
                                 automatic login in ~/.config/labelvier/siteground/.env
  login                          Open browser, log in (automatically when setup was done), store session
  session:import                 Read {"token","refreshToken"} JSON from stdin and store it
  session:status                 Show how long the stored session is valid
  logout [--forget]              Remove the stored session and browser profile; --forget also the
                                 login credentials (.env)

Overview
  accounts                       Hosting plans with site count and disk usage
  sites [--account <name|id>]    Websites, optionally filtered on plan

Usage (find the site behind a CPU spike or an autoscale)
  account:stats <name|id> [--days 31] [--top 15] [--sort cpu|exec]
                                 Sites ranked on CPU seconds and program executions,
                                 avg/day of the last 7 days against the days before
  account:autoscale <name|id>    Cloud plan autoscale settings and resources added by autoscaling
  site:stats <domain> [--days 31]
                                 CPU seconds and program executions per day for one site

Create (asks for everything that is missing when run in a terminal)
  create-site [--domain <domain>] [--account <name|id>] [--app none|wordpress|woocommerce]
              [--php <8.3|managed>] [--wp-email <email>] [--[no-]memcached] [--[no-]ssl] [--[no-]https]
              [--ssh-key <file.pub>|--no-ssh-key]
              [--ssh-alias <name>|--no-ssh-alias] [--db <label>|--no-db] [--yes] [--dry-run]

Site Tools (existing site)
  site:info <domain>                         Domains, SSL, PHP, Memcached, SSH, storage, databases
  site:memcached <domain> [--off]            Enable (or disable) Memcached
  site:php <domain> [--php <8.3|managed>]    Show or set the PHP version
  site:ssl <domain> [--no-https]             Let's Encrypt when DNS points to the server, force HTTPS
  site:ssh-key <domain> [--ssh-key <file>] [--ssh-alias <name>]
                                             Authorize a public key (default ~/.ssh/id_ed25519.pub)
                                             and add a Host alias to ~/.ssh/config (via labelvier ssh alias)
  site:ssh <domain>                          Print the ssh command
  site:login <domain|url> [--print]          Log in to the admin panel (WordPress) in the browser with a
                                             one-time link; --print prints the link instead of opening it
  site:db <domain> [--db <label>]            Create MySQL database + user with all privileges
  site:cron <domain>                         List cron jobs
  site:cron <domain> --add "<command>" [--at "<min hour day mon dow>"]
                                             Add a cron job (default every minute; @hourly/@daily/… also work)
  site:cron <domain> --remove <id>           Delete a cron job (asks first in a terminal unless --yes)
`;

const { positionals, values } = parseArgs({
	allowPositionals: true,
	allowNegative: true,
	options: {
		account: { type: 'string' },
		domain: { type: 'string' },
		app: { type: 'string' },
		php: { type: 'string' },
		'wp-email': { type: 'string' },
		memcached: { type: 'boolean' },
		ssl: { type: 'boolean' },
		https: { type: 'boolean' },
		'ssh-key': { type: 'string' },
		'no-ssh-key': { type: 'boolean' },
		'ssh-alias': { type: 'string' },
		'no-ssh-alias': { type: 'boolean' },
		db: { type: 'string' },
		'no-db': { type: 'boolean' },
		off: { type: 'boolean' },
		demo: { type: 'boolean' }, // hidden: see src/demo.js
		add: { type: 'string' },
		at: { type: 'string' },
		remove: { type: 'string' },
		yes: { type: 'boolean', short: 'y' },
		'dry-run': { type: 'boolean' },
		json: { type: 'boolean' },
		days: { type: 'string' },
		top: { type: 'string' },
		sort: { type: 'string' },
		print: { type: 'boolean' }, // site:login: print the link instead of opening it
		forget: { type: 'boolean' }, // logout: also remove the stored credentials
		help: { type: 'boolean', short: 'h' },
	},
});

const APPS = { none: null, wordpress: 'WordPress', woocommerce: 'WooCommerce' };
const isDomain = (v) => (/^(?!-)[a-z0-9-]+(\.[a-z0-9-]+)+$/i.test(v) ? null : 'Not a valid domain');
const isEmail = (v) => (/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(v) ? null : 'Not a valid email address');

/** Use the flag when given, otherwise ask (only in a terminal), otherwise fall back to the default. */
async function option(flag, question, defaultValue) {
	if (values[flag] !== undefined) return values[flag];
	if (!interactive) return defaultValue;
	return confirm(question, { defaultValue, flag: `--${flag}` });
}

async function siteToolsFor(sg, domain) {
	if (!domain) throw new Error('Domain is required, e.g. labelvier siteground site:info example.com');
	return task(`Looking up ${domain}…`, async () => {
		const site = await findSite(sg, domain);
		const account = (await sg.accounts()).find((a) => a.id === site.account_id);
		return { site, account, st: sg.siteTools(site.id) };
	}, { done: ({ site, account }) => `${domain} found on ${account.name} (${site.id})` });
}

/** Let the user pick a PHP version; null = managed by SiteGround. */
function askPhp(versions) {
	return select('PHP version:', [
		{ label: phpLabel(versions, null), value: null },
		...versions
			.filter((v) => v.mod_php)
			.map((v) => ({ label: `${v.version}${v.recommended ? '  (recommended)' : ''}${v.default ? '  (default)' : ''}`, value: v.id })),
	]);
}

/** Alias for ~/.ssh/config: --ssh-alias, otherwise asked in a terminal; null = no alias. */
async function askSshAlias(domain) {
	if (values['ssh-alias']) return values['ssh-alias'];
	if (values['no-ssh-alias'] || !interactive) return null;
	if (!(await confirm('Add an SSH alias to ~/.ssh/config?', { defaultValue: true }))) return null;
	return ask('Alias name', { defaultValue: defaultSshAlias(domain), validate: (v) => (/^[\w.-]+$/.test(v) ? null : 'Use letters, digits, dot, dash or underscore') });
}

async function runSshAlias(st, name, keyFile) {
	return task(`Adding SSH alias "${name}" to ~/.ssh/config…`, async (s) => {
		const r = await addSshAlias({ name, keyFile, ...(await sshDetails(st)) });
		if (!r.ok) s.info(r.message);
		return r;
	}, { done: (r) => `${r.message} (ssh ${name})` });
}

const num = (n) => Math.round(n).toLocaleString('en-US');
const intOption = (flag, fallback) => {
	if (values[flag] === undefined) return fallback;
	const n = Number(values[flag]);
	if (!Number.isInteger(n) || n < 1) throw new Error(`--${flag} needs a positive whole number`);
	return n;
};
const METRIC_LABELS = { cpu: 'CPU seconds', exec: 'Program executions' };

function printRanking(rows, key, top) {
	console.log(`\n${METRIC_LABELS[key]}`);
	console.log(`${'share'.padStart(6)} ${'total'.padStart(12)} ${'avg/day before'.padStart(15)} ${'avg/day last 7'.padStart(15)} ${'growth'.padStart(7)}  ${'peak (day)'.padEnd(22)} site`);
	for (const r of rows.slice(0, top)) {
		const growth = r.growth == null ? '-' : `${r.growth.toFixed(1)}x`;
		console.log(
			`${(r.share * 100).toFixed(1).padStart(5)}% ${num(r.total).padStart(12)} ${num(r.avgBefore).padStart(15)} ${num(r.avgRecent).padStart(15)} ${growth.padStart(7)}  ${`${num(r.peak)} (${r.peakDay})`.padEnd(22)} ${r.domain}`,
		);
	}
}

const ACTIVATION_LABELS = { site_activation: 'site', cms_install: 'app install' };
const STATUS_LABELS = { '-1': 'failed', 0: 'pending', 1: 'running', 100: 'done' };
const describeActivation = (items) =>
	items.map((it) => `${ACTIVATION_LABELS[it.product_name] || it.product_name} ${STATUS_LABELS[it.status] ?? it.status}`).join(', ');

const commands = {
	async setup() {
		await setupLogin();
	},

	async login() {
		await interactiveLogin();
	},

	async 'session:import'() {
		let raw = '';
		for await (const chunk of process.stdin) raw += chunk;
		let parsed;
		try {
			parsed = JSON.parse(raw);
		} catch (err) {
			throw new Error(`Input is not valid JSON: ${err.message}`);
		}
		const { token, refreshToken } = parsed ?? {};
		if (!refreshToken) throw new Error('Input JSON needs a "refreshToken" field');
		const refreshExp = jwtExpiry(refreshToken, 'refreshToken');
		if (token) jwtExpiry(token, 'token');
		await saveSession({ token, refreshToken });
		console.log('Session stored, refresh token valid until', refreshExp.toLocaleString());
	},

	async logout() {
		const removed = await clearSession({ forget: values.forget });
		if (removed.length === 0) {
			console.log('Nothing to remove: not logged in.');
			return;
		}
		for (const file of removed) console.log(`Removed ${file}`);
		console.log(values.forget ? 'Logged out, credentials forgotten.' : 'Logged out. Credentials in .env are kept (use --forget to remove them too).');
	},

	async 'session:status'() {
		let s;
		try {
			s = await loadSession();
		} catch (err) {
			if (err instanceof SyntaxError) throw new Error(`Session file is corrupt (not valid JSON): ${SESSION_FILE}. Run "labelvier siteground login" again.`);
			throw err;
		}
		if (!s || typeof s !== 'object') throw new Error(`Session file is corrupt: ${SESSION_FILE}. Run "labelvier siteground login" again.`);
		const fmt = (t, what) => (t ? jwtExpiry(t, what).toLocaleString() : '-');
		console.log(`access token  until ${fmt(s.token, 'token')}\nrefresh token until ${fmt(s.refreshToken, 'refreshToken')}`);
	},

	async accounts(sg) {
		const accounts = await task('Getting hosting plans…', async () => (demo.enabled ? withDemoPlans(await accountsOverview(sg)) : accountsOverview(sg)), { done: (a) => `${a.length} hosting plans` });
		if (values.json) return console.log(JSON.stringify(accounts, null, 2));
		for (const a of accounts) console.log(demo.enabled ? a.name : describeAccount(a));
	},

	async sites(sg) {
		let sites = await task('Getting websites…', () => sg.sites(), { done: (s) => `${s.length} websites` });
		if (values.account) {
			const account = await sg.findAccount(values.account);
			sites = sites.filter((s) => s.account_id === account.id);
		}
		if (values.json) return console.log(JSON.stringify(sites, null, 2));
		for (const s of sites) console.log(`${s.id}  ${s.domain.padEnd(40)} ${s.cms.padEnd(10)} ${s.status.padEnd(14)} ${s.account_name}`);
	},

	async 'account:stats'(sg, [nameOrId = values.account]) {
		if (!nameOrId) throw new Error('Hosting plan is required, e.g. labelvier siteground account:stats Albatros');
		const days = intOption('days', 31);
		const top = intOption('top', 15);
		const sort = values.sort ?? 'cpu';
		if (!METRIC_LABELS[sort]) throw new Error('--sort must be cpu or exec');
		const account = await sg.findAccount(nameOrId);
		const usage = await task(`Getting usage of ${account.name}…`, () => siteUsage(sg, account.id, { days }), {
			done: (u) => `${u.sites.length} sites, ${u.days[0]} to ${u.days.at(-1)}`,
		});
		const ranked = Object.fromEntries(Object.keys(METRIC_LABELS).map((key) => [key, rankSites(usage, key)]));
		if (values.json) return console.log(JSON.stringify(ranked, null, 2));
		console.log('Growth = avg/day of the last 7 complete days (UTC) against the days before.');
		for (const key of [sort, ...Object.keys(METRIC_LABELS).filter((k) => k !== sort)]) printRanking(ranked[key], key, top);
	},

	async 'account:autoscale'(sg, [nameOrId = values.account]) {
		if (!nameOrId) throw new Error('Hosting plan is required, e.g. labelvier siteground account:autoscale Albatros');
		const account = await sg.findAccount(nameOrId);
		const [settings, logs] = await task(`Getting autoscale info of ${account.name}…`, () =>
			Promise.all([sg.autoscaleSettings(account.id), sg.autoscaleLogs(account.id)]), { done: `Autoscale info of ${account.name}` });
		if (values.json) return console.log(JSON.stringify({ settings, logs }, null, 2));
		for (const r of Object.values(settings || {})) {
			console.log(`${r.name.padEnd(4)} ${r.status ? 'on ' : 'off'}  now ${r.current_value} ${r.unit_plural}, cap ${r.current_cap}, threshold ${r.current_threshold}%`);
		}
		console.log(logs?.length ? '\nAdded by autoscaling:' : '\nNothing added by autoscaling.');
		for (const l of logs || []) console.log(`${l.date_added}  ${l.type}  +${l.units}  ${l.status}  until ${l.expiration_date}`);
	},

	async 'site:stats'(sg, [domain]) {
		if (!domain) throw new Error('Domain is required, e.g. labelvier siteground site:stats example.com');
		const days = intOption('days', 31);
		const site = await findSite(sg, domain);
		const usage = await task(`Getting usage of ${domain}…`, () => siteUsage(sg, site.account_id, { days }), { done: (u) => `${u.days[0]} to ${u.days.at(-1)}` });
		const s = usage.sites.find((x) => x.id === site.id);
		if (!s) throw new Error(`No statistics for ${domain}`);
		if (values.json) return console.log(JSON.stringify(s, null, 2));
		console.log(`${'day'.padEnd(10)} ${'CPU seconds'.padStart(12)} ${'% of plan'.padStart(9)} ${'executions'.padStart(11)}`);
		for (const d of usage.days) {
			const share = usage.total.cpu[d] ? `${(((s.cpu[d] || 0) / usage.total.cpu[d]) * 100).toFixed(1)}%` : '-';
			console.log(`${d} ${num(s.cpu[d] || 0).padStart(12)} ${share.padStart(9)} ${num(s.exec[d] || 0).padStart(11)}`);
		}
	},

	async 'create-site'(sg) {
		// 1. Domain
		const domain = (values.domain || (await ask('Domain', { validate: isDomain, flag: '--domain' }))).toLowerCase();
		if (isDomain(domain)) throw new Error(`${domain}: not a valid domain`);
		await task(`Checking whether ${domain} already exists…`, async () => {
			const existing = (await sg.sites()).find((s) => s.domain === domain);
			// Demo mode records "creating" a site that already exists.
			if (existing && !demo.enabled) throw new Error(`Site ${domain} already exists on ${existing.account_name} (${existing.id})`);
		}, { done: `${domain} is not in use yet` });

		// 2. Hosting plan
		const accounts = await task(demo.enabled ? 'Getting hosting plans…' : 'Getting hosting plans and disk usage…', async () =>
			demo.enabled ? withDemoPlans(await accountsOverview(sg)) : accountsOverview(sg), { done: (a) => `${a.length} hosting plans` });
		let account;
		if (values.account) {
			const { id } = await sg.findAccount(values.account);
			account = accounts.find((a) => a.id === id && !a.demoExtra);
		} else {
			account = await select(
				'Hosting plan:',
				accounts.map((a) => ({
					label: demo.enabled ? a.name : describeAccount(a), // demo: plan names only
					value: a,
					disabled: !a.can_create_sites || a.status !== 'active' ? 'cannot create sites' : null,
				})),
				{ flag: '--account' },
			);
		}

		const { check, pointed } = await task(`Checking domain and DNS for ${domain}…`, async () => ({
			check: await sg.checkExistingDomain(account.id, domain),
			pointed: await dnsPointsTo(domain, account.server.ip),
		}), {
			done: ({ pointed }) => {
				const server = demo.enabled ? 'the server' : account.server.ip;
				return pointed ? `${domain} points to ${server}` : `${domain} does not point to ${server} yet`;
			},
		});

		// 3. Application
		let appKey = values.app?.toLowerCase();
		if (appKey === undefined) {
			appKey = interactive
				? await select('Application:', [
						{ label: 'None (empty site)', value: 'none' },
						{ label: 'WordPress', value: 'wordpress' },
						{ label: 'WooCommerce', value: 'woocommerce' },
					])
				: 'none';
		}
		if (!(appKey in APPS)) throw new Error(`--app must be one of: ${Object.keys(APPS).join(', ')}`);
		let app = null;
		if (APPS[appKey]) {
			const email = values['wp-email'] || (await ask('Admin email', { defaultValue: 'hallo@labelvier.nl', validate: isEmail, flag: '--wp-email' }));
			app = { name: APPS[appKey], email, password: generatePassword() };
		}

		// 4. PHP version (always asked)
		const phpVersions = await task('Getting PHP versions…', () => serverPhpVersions(sg, account.id), {
			done: (v) => (v ? `PHP ${v.map((x) => x.version.replace(/^PHP (\d+\.\d+).*/, '$1')).join(', ')} available` : 'No existing site on this plan to read PHP versions from'),
		});
		// No site on this plan yet: versions are only known after creation, then we ask (see step 8).
		let phpVersion = null;
		if (!phpVersions) {
			// handled after creation
		} else if (values.php !== undefined) {
			phpVersion = parsePhpVersion(values.php, phpVersions);
		} else if (interactive && phpVersions) {
			phpVersion = await askPhp(phpVersions);
		}

		// 5. Extras
		const memcached = await option('memcached', 'Enable Memcached?', true);
		const ssl = await option('ssl', pointed ? "Install Let's Encrypt SSL?" : `Install SSL? (DNS does not point to ${account.server.ip} yet, will be skipped)`, pointed);
		const https = ssl ? await option('https', 'Force HTTPS?', true) : false;

		let sshKeyFile = values['ssh-key'];
		if (!sshKeyFile && !values['no-ssh-key'] && interactive) {
			const def = defaultSshKeyFile();
			if (await confirm(demo.enabled ? 'Authorize your SSH key?' : 'Authorize an SSH public key?', { defaultValue: !!def })) {
				// Demo: no file paths on screen, just use the default key.
				sshKeyFile = demo.enabled && def
					? def
					: await ask('Public key file', { defaultValue: def, validate: (f) => (existsSync(f) ? null : 'File not found') });
			}
		}
		const sshAlias = sshKeyFile ? await askSshAlias(domain) : null;

		let dbLabel = values.db;
		if (!dbLabel && !values['no-db'] && !app && interactive) {
			if (await confirm('Create a MySQL database + user?', { defaultValue: false })) {
				dbLabel = await ask('Database label', { defaultValue: domain.split('.')[0] });
			}
		}

		// 6. Summary
		console.log(`
Domain      ${domain} (registered: ${check.registered ? 'yes' : 'no'}, DNS -> ${demo.enabled ? 'server' : account.server.ip}: ${pointed ? 'yes' : 'no'})
Plan        ${account.name}${demo.enabled ? '' : ` (${account.server.location})`}
App         ${app ? `${app.name}, admin ${app.email}` : 'none (empty site)'}
PHP         ${phpLabel(phpVersions, phpVersion)}
Memcached   ${memcached ? 'yes' : 'no'}
SSL         ${ssl ? `yes${https ? ', force HTTPS' : ''}` : 'no'}
SSH key     ${sshKeyFile ? `${demo.enabled ? 'yes' : sshKeyFile}${sshAlias ? `, alias "${sshAlias}" in ~/.ssh/config` : ''}` : 'no'}
Database    ${dbLabel || (app ? 'created by installer' : 'no')}
`);
		if (values['dry-run']) return console.log('Dry run: nothing created.');
		if (!values.yes && interactive && !(await confirm('Create this site?', { defaultValue: true }))) return console.log('Cancelled.');

		// 7. Create + wait
		const orderId = await task(`Creating site ${domain}${app ? ` with ${app.name}` : ''}…`, () => sg.createSite({ accountId: account.id, domain, app }), {
			done: (id) => `Order ${id} placed`,
		});
		const started = Date.now();
		await task('Waiting for activation…', async (s) => {
			const result = await sg.waitForOrder(orderId, {
				onTick: (items) => (s.text = `Waiting for activation: ${describeActivation(items)} (${Math.round((Date.now() - started) / 1000)}s)…`),
			});
			if (!result.ok) throw new Error(`Order ${orderId} not successful: ${JSON.stringify(result)}`);
		}, { done: () => `Activated in ${Math.round((Date.now() - started) / 1000)}s` });
		const site = await task('Looking up the new site…', () => findSite(sg, domain), { done: (s) => `Site ${domain} created (${demo.enabled ? s.status : `${s.id}, ${s.status}`})` });

		const credentials = {};
		if (app) credentials.wp_admin = { url: `https://${domain}/wp-admin`, email: app.email, password: app.password };

		// 8. Site Tools
		const st = sg.siteTools(site.id);
		if (!phpVersions) {
			const versions = await task('Getting PHP versions…', () => st.phpVersions());
			if (values.php !== undefined) phpVersion = parsePhpVersion(values.php, versions);
			else if (interactive) {
				phpVersion = await askPhp(versions);
			}
		}
		// Demo mode: same steps and spinners, but simulated (see src/demo.js).
		const fake = demo.enabled ? fakeActions : null;
		if (phpVersion) {
			await task('Setting PHP version…', () => (fake ? fake.setPhpVersion(phpLabel(phpVersions, phpVersion)) : setPhpVersion(st, phpVersion)), { done: (m) => m });
		}
		if (memcached) await task('Enabling Memcached…', () => (fake ? fake.enableMemcached() : enableMemcached(st)), { done: (m) => m });
		if (ssl) {
			await task('Setting up SSL…', async (s) => {
				const r = fake
					? await fake.setupSsl({ domain, https }, s, await dnsPointsTo(domain, account.server.ip))
					: await setupSsl(st, { domain, serverIp: account.server.ip, https }, s);
				if (!r.ok) s.info(r.message);
				return r;
			}, { done: (r) => r.message });
		}
		if (sshKeyFile) {
			const r = await task('Authorizing SSH key…', async () =>
				fake ? { message: await fake.addSshKey(sshKeyFile), ssh: await sshCommand(st) } : addSshKey(st, { keyFile: sshKeyFile }),
			{ done: (r) => r.message });
			credentials.ssh = r.ssh;
			if (sshAlias) {
				const ok = fake
					? (await task(`Adding SSH alias "${sshAlias}" to ~/.ssh/config…`, () => fake.addSshAlias(sshAlias), { done: (r) => `${r.message} (ssh ${sshAlias})` })).ok
					: (await runSshAlias(st, sshAlias, sshKeyFile)).ok;
				if (ok) credentials.ssh_alias = `ssh ${sshAlias}`;
			}
		}
		if (dbLabel) {
			credentials.database = await task('Creating database…', (s) => (fake ? fake.createDatabase(dbLabel, s) : createDatabase(st, { label: dbLabel }, s)), {
				done: (db) => `Database ${db.name} + user ${db.user} created (all privileges)`,
			});
		}
		if (!credentials.ssh) credentials.ssh = await task('Getting SSH details…', () => sshCommand(st), { done: 'SSH details fetched' });

		if (fake) {
			await pause(600);
			console.log(`\nDone. Credentials saved in .credentials/${domain}.json`);
		} else {
			const file = await storeCredentials(domain, credentials);
			console.log(`\nDone. Credentials saved in ${file}`);
		}
		if (app) console.log(`WP admin: ${credentials.wp_admin.url}  user ${app.email}  password ${fake ? '••••••••••••' : app.password}`);
		if (credentials.database) console.log(`Database: ${credentials.database.name}  user ${credentials.database.user}  password ${credentials.database.password}`);
		console.log(`SSH:      ${credentials.ssh_alias || credentials.ssh}`);
		if (!pointed) console.log(`DNS:      point A ${domain} -> ${account.server.ip}, then run: labelvier siteground site:ssl ${domain}`);
	},

	async 'site:info'(sg, [domain]) {
		const { site, account, st } = await siteToolsFor(sg, domain);
		const [domains, certs, memcached, keys, dbs, ssh, phpVersions, php, disk] = await task('Getting Site Tools details…', () =>
			Promise.all([st.domains(), st.certificates(), st.memcached(), st.sshKeys(), st.databases(), sshCommand(st), st.phpVersions(), st.phpVersion(), siteDiskUsage(sg, site).catch(() => null)]),
		);
		console.log(`${site.domain} (${site.id}) on ${account.name} / ${account.server.ip}, status ${site.status}`);
		for (const d of domains) {
			const cert = certs.find((c) => c.id === d.cert_id);
			const until = cert ? new Date(cert.not_after * 1000).toISOString().slice(0, 10) : null;
			console.log(`  ${d.domain_type.padEnd(12)} ${d.name.padEnd(36)} SSL ${cert ? `${cert.issuer.includes("Let's Encrypt") ? 'LE' : 'yes'} until ${until}` : 'no'}  HTTPS forced ${d.settings.https_enforce ? 'yes' : 'no'}`);
		}
		console.log(`  PHP        ${phpLabel(phpVersions, php)}`);
		console.log(`  Memcached  ${memcached ? 'on' : 'off'}`);
		console.log(`  SSH        ${ssh}  (${keys.length} key(s): ${keys.map((k) => k.comment).join(', ') || '-'})`);
		console.log(`  Storage    ${describeDiskUsage(disk)}`);
		console.log(`  Databases  ${dbs.map((d) => `${d.name} "${d.label}"`).join(', ') || '-'}`);
	},

	async 'site:memcached'(sg, [domain]) {
		const { st } = await siteToolsFor(sg, domain);
		await (values.off
			? task('Disabling Memcached…', () => disableMemcached(st), { done: (m) => m })
			: task('Enabling Memcached…', () => enableMemcached(st), { done: (m) => m }));
	},

	async 'site:php'(sg, [domain]) {
		const { st } = await siteToolsFor(sg, domain);
		const [versions, current, apache] = await task('Getting PHP versions…', () => Promise.all([st.phpVersions(), st.phpVersion(), st.apacheService()]), {
			done: ([v, c, a]) => `Current: ${phpLabel(v, c)}${a ? '' : ' (standard PHP; setting a version switches to Ultrafast PHP)'}`,
		});
		let target;
		if (values.php !== undefined) target = parsePhpVersion(values.php, versions);
		else if (interactive) {
			target = await askPhp(versions);
		} else return;
		if (apache && target === current) return console.log('Unchanged.');
		await task(`Setting ${phpLabel(versions, target)}…`, () => setPhpVersion(st, target), { done: (m) => m });
	},

	async 'site:ssl'(sg, [domain]) {
		const { account, st } = await siteToolsFor(sg, domain);
		const r = await task('Setting up SSL…', async (s) => {
			const res = await setupSsl(st, { domain, serverIp: account.server.ip, https: values.https !== false }, s);
			if (!res.ok) s.info(res.message);
			return res;
		}, { done: (res) => res.message });
		if (!r.ok) process.exitCode = 2;
	},

	async 'site:ssh-key'(sg, [domain]) {
		const { st } = await siteToolsFor(sg, domain);
		const keyFile = values['ssh-key'] || defaultSshKeyFile();
		if (!keyFile) throw new Error('No public key found, pass --ssh-key <file.pub>');
		const alias = await askSshAlias(domain);
		const r = await task('Authorizing SSH key…', () => addSshKey(st, { keyFile }), { done: (r) => r.message });
		if (alias && (await runSshAlias(st, alias, keyFile)).ok) return console.log(`ssh ${alias}`);
		console.log(r.ssh);
	},

	async 'site:ssh'(sg, [domain]) {
		const { st } = await siteToolsFor(sg, domain);
		console.log(await task('Getting SSH details…', () => sshCommand(st), { done: 'SSH details fetched' }));
	},

	/** Log in to the admin panel of a site; takes a domain or a URL on it (https://www.x.nl/wp-admin). */
	async 'site:login'(sg, [input]) {
		const domain = input && domainFromUrl(input);
		const { st } = await siteToolsFor(sg, domain);
		const apps = await task('Getting installed apps…', () => loginApps(st, domain), { done: (a) => `${a.length} app(s) with an admin login` });
		if (!apps.length) throw new Error(`No WordPress install found on ${domain}`);
		const app = apps.length > 1 && interactive
			? await select('Log in to:', apps.map((a) => ({ label: `${a.app_url}${a.is_staging ? '  (staging)' : ''}`, value: a })))
			: apps[0];
		const url = await task(`Creating login link for ${app.app_url}…`, () => adminLoginUrl(st, app), { done: 'Login link created (one-time)' });
		// The link is a login: only on stdout when asked for or piped, never in the spinner text.
		if (values.print || !process.stdout.isTTY) return console.log(url);
		if (await openInBrowser(url)) return console.log(`Opened the admin panel of ${app.app_url} in the browser.`);
		console.log(`Could not open a browser. One-time login link:\n${url}`);
	},

	async 'site:db'(sg, [domain]) {
		const { st } = await siteToolsFor(sg, domain);
		const label = values.db || (await ask('Database label', { defaultValue: domain.split('.')[0], flag: '--db' }));
		const db = await task('Creating database…', (s) => createDatabase(st, { label }, s), {
			done: (db) => `Database ${db.name} + user ${db.user} created (all privileges)`,
		});
		const file = await storeCredentials(domain, { [`database_${db.name}`]: db });
		console.log(`name ${db.name}  user ${db.user}  password ${db.password}  host localhost\nSaved in ${file}`);
	},

	async 'site:cron'(sg, [domain]) {
		if (values.add !== undefined && values.remove !== undefined) throw new Error('Use either --add or --remove, not both');
		const schedule = values.at ?? '* * * * *';
		if (values.add !== undefined) parseCronSchedule(schedule); // fail before any API call
		const { st } = await siteToolsFor(sg, domain);

		if (values.add !== undefined) {
			if (!values.add.trim()) throw new Error('--add needs a command');
			await task('Adding cron job…', () => addCronJob(st, { cmd: values.add.trim(), schedule }), { done: (r) => r.message });
		} else if (values.remove !== undefined) {
			const job = (await st.cronJobs()).find((j) => String(j.id) === values.remove);
			if (!job) throw new Error(`No cron job #${values.remove} on ${domain}`);
			if (!values.yes && interactive && !(await confirm(`Delete cron job #${job.id} (${cronSchedule(job)} ${job.cmd})?`, { defaultValue: false }))) {
				return console.log('Cancelled.');
			}
			if (!values.yes && !interactive) throw new Error('Deleting needs --yes when not run in a terminal');
			await task(`Deleting cron job #${job.id}…`, () => st.deleteCronJob(job.id), { done: `Cron job #${job.id} deleted` });
		}

		const jobs = await task('Getting cron jobs…', () => st.cronJobs(), { done: (j) => `${j.length} cron job(s)` });
		if (values.json) return console.log(JSON.stringify(jobs, null, 2));
		for (const j of jobs) console.log(`#${String(j.id).padEnd(8)} ${cronSchedule(j).padEnd(20)} ${j.cmd}`);
	},
};

if (values.demo || process.env.SG_DEMO === '1') enableDemo();

const [cmd, ...args] = positionals;
if (!cmd || !commands[cmd] || values.help) {
	if (cmd && !commands[cmd] && !values.help) console.error(`\x1b[31m✗\x1b[0m Unknown command: ${cmd}`);
	console.log(HELP);
	process.exit(cmd && !commands[cmd] && !values.help ? 1 : 0);
}

try {
	const needsClient = !['setup', 'login', 'logout', 'session:import', 'session:status'].includes(cmd);
	await commands[cmd](needsClient ? await SiteGroundClient.fromSavedSession() : undefined, args);
} catch (err) {
	console.error(`Error: ${err.message}`);
	process.exitCode = 1;
} finally {
	closePrompt();
}
