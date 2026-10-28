import { HOME, STATE_DIR, ROOT, REPO_DIR, resetDirs, startDnsStub } from './helpers.js'; // first: sets HOME/SG_STATE_DIR
import { test, beforeEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync, chmodSync } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';
import {
	SSH_PORT,
	generatePassword,
	storeCredentials,
	accountsOverview,
	describeAccount,
	findSite,
	siteDiskUsage,
	describeDiskUsage,
	USAGE_METRICS,
	siteUsage,
	rankSites,
	dnsPointsTo,
	defaultSshKeyFile,
	enableMemcached,
	disableMemcached,
	setupSsl,
	addDomainAlias,
	addSshKey,
	sshDetails,
	sshCommand,
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
} from '../src/actions.js';

const CREDENTIALS_DIR = path.join(STATE_DIR, '.credentials');
const mode = (file) => statSync(file).mode & 0o777;
const SERVER_IP = '35.214.252.94';

/** A Site Tools stand-in: every method records its calls and answers from `answers`. */
function fakeSt(answers = {}) {
	const st = { apiUrl: 'c1103939.sgvps.net', calls: [] };
	for (const [name, value] of Object.entries(answers)) {
		st[name] = mock.fn(async (...args) => {
			st.calls.push([name, ...args]);
			return typeof value === 'function' ? value(...args) : value;
		});
	}
	return st;
}

beforeEach(() => {
	resetDirs();
	assert.equal(homedir(), HOME, 'os.homedir() follows $HOME');
});

// --- passwords / credentials ---------------------------------------------------------

test('generatePassword(): long, url-safe, always with lower/upper/digit/symbol', () => {
	const seen = new Set();
	for (let i = 0; i < 20; i++) {
		const pw = generatePassword();
		seen.add(pw);
		assert.match(pw, /^[A-Za-z0-9_-]{24}a1!$/);
	}
	assert.equal(seen.size, 20);
});

test('storeCredentials(): creates .credentials (0700) and <domain>.json (0600) with the domain', async () => {
	const file = await storeCredentials('x.labelvier.dev', { ssh: 'ssh -p 18765 u1@h' });
	assert.equal(file, path.join(CREDENTIALS_DIR, 'x.labelvier.dev.json'));
	assert.equal(mode(CREDENTIALS_DIR), 0o700);
	assert.equal(mode(file), 0o600);
	assert.deepEqual(JSON.parse(readFileSync(file, 'utf8')), { domain: 'x.labelvier.dev', ssh: 'ssh -p 18765 u1@h' });
});

test('storeCredentials(): merges into an existing file instead of overwriting it', async () => {
	await storeCredentials('x.labelvier.dev', { wp_admin: { email: 'a@b.nl', password: 'one' } });
	const file = await storeCredentials('x.labelvier.dev', { database_db1: { user: 'u1' }, wp_admin: { email: 'a@b.nl', password: 'two' } });
	assert.deepEqual(JSON.parse(readFileSync(file, 'utf8')), {
		domain: 'x.labelvier.dev',
		wp_admin: { email: 'a@b.nl', password: 'two' },
		database_db1: { user: 'u1' },
	});
	assert.equal(mode(file), 0o600);
});

// --- accounts / sites ---------------------------------------------------------------------

const ACCOUNTS = [
	{ id: 'A1', name: 'Develop - Hamerkop', plan_description: 'GoGeek\n  Dev', server: { ip: SERVER_IP, location: 'Amsterdam' } },
	{ id: 'A2', name: 'Basis - Albatros', plan_description: 'GrowBig', server: { ip: '35.214.165.2', location: 'Amsterdam' } },
];
const SITES = [
	{ id: 'S1', domain: 'analytics.labelvier.dev', account_id: 'A1', status: 'active' },
	{ id: 'S2', domain: 'old.labelvier.dev', account_id: 'A1', status: 'pending' },
	{ id: 'S3', domain: 'yoni.care', account_id: 'A2', status: 'active' },
];

function fakeSg(extra = {}) {
	return {
		accounts: async () => ACCOUNTS,
		sites: async () => SITES,
		get: mock.fn(async (p) => {
			if (p === '/account/A1/stats/disk') return { total: 10240, limit: 40960 };
			throw new Error(`no disk stats for ${p}`);
		}),
		...extra,
	};
}

test('accountsOverview(): site count per plan, disk in GB, null when the stats call fails', async () => {
	const overview = await accountsOverview(fakeSg());
	assert.equal(overview.length, 2);
	assert.equal(overview[0].siteCount, 2);
	assert.equal(overview[0].diskUsedGb, 10);
	assert.equal(overview[0].diskLimitGb, 40);
	assert.equal(overview[1].siteCount, 1);
	assert.equal(overview[1].diskUsedGb, null);
	assert.equal(overview[1].diskLimitGb, null);
});

test('describeAccount(): one aligned line, whitespace in the plan description collapsed', async () => {
	const [a, b] = await accountsOverview(fakeSg());
	assert.equal(describeAccount(a), 'Develop - Hamerkop       2 sites  10/40 GB (25%), 30 GB free         GoGeek Dev  Amsterdam');
	assert.equal(describeAccount(b), 'Basis - Albatros         1 sites  disk usage unknown                 GrowBig  Amsterdam');
});

test('siteDiskUsage(): the site figure from its plan disk stats, null when the site is not listed', async () => {
	const sg = fakeSg({
		get: async (p) => {
			assert.equal(p, '/account/A1/stats/disk');
			return { total: 10240, limit: 40960, site_stats_responses: [{ id: 'S1', domain: 'analytics.labelvier.dev', value: 1536 }] };
		},
	});
	assert.deepEqual(await siteDiskUsage(sg, SITES[0]), { siteMb: 1536, accountMb: 10240, limitMb: 40960 });
	assert.deepEqual(await siteDiskUsage(sg, SITES[1]), { siteMb: null, accountMb: 10240, limitMb: 40960 });
	const numeric = fakeSg({ get: async () => ({ total: 1, limit: 2, site_stats_responses: [{ id: 1, domain: 'other.nl', value: 5 }] }) });
	assert.equal((await siteDiskUsage(numeric, { ...SITES[0], id: '1' })).siteMb, 5);
});

test('describeDiskUsage(): MB below 1 GB, GB above, share of the plan limit', () => {
	assert.equal(describeDiskUsage({ siteMb: 1536, accountMb: 10240, limitMb: 40960 }), '1.5 GB (4% of plan; plan 10.0 GB of 40.0 GB)');
	assert.equal(describeDiskUsage({ siteMb: 199, accountMb: 10240, limitMb: 40960 }), '199 MB (0% of plan; plan 10.0 GB of 40.0 GB)');
	assert.equal(describeDiskUsage({ siteMb: null, accountMb: 10240, limitMb: 40960 }), 'unknown (plan 10.0 GB of 40.0 GB)');
	assert.equal(describeDiskUsage(null), 'unknown');
});

test('describeDiskUsage(): leaves out the percentage when the plan limit is missing or 0', () => {
	assert.equal(describeDiskUsage({ siteMb: 1536, accountMb: 10240, limitMb: 0 }), '1.5 GB (plan 10.0 GB)');
	assert.equal(describeDiskUsage({ siteMb: 1536, accountMb: 10240, limitMb: undefined }), '1.5 GB (plan 10.0 GB)');
});

test('findSite(): by exact domain, or throws', async () => {
	assert.equal((await findSite(fakeSg(), 'yoni.care')).id, 'S3');
	await assert.rejects(findSite(fakeSg(), 'nope.nl'), /^Error: No site found for nope\.nl$/);
});

// --- usage statistics ------------------------------------------------------------------------

const day = (d) => Math.floor(Date.parse(`${d}T23:59:59Z`) / 1000);

test('siteUsage(): sums points per UTC day for the account and per site, drops empty days', async () => {
	const calls = [];
	const sg = {
		accountStats: async (accountId, metric, opts) => {
			calls.push([accountId, metric, opts]);
			const v = metric === 'cpu_seconds' ? 10 : 100;
			return {
				points: [
					{ timestamp: day('2026-10-01'), value: v },
					{ timestamp: day('2026-10-01') - 3600, value: v }, // same day, other stamp: added
					{ timestamp: day('2026-10-02'), value: 0 }, // padding
					{ timestamp: day('2026-10-03'), value: v * 2 },
				],
				aggregated_site_stats_responses: [
					{ id: 'S1', domain: 'analytics.labelvier.dev', points: [{ timestamp: day('2026-10-01'), value: v }, { timestamp: day('2026-10-03'), value: v }] },
				],
			};
		},
	};
	const usage = await siteUsage(sg, 'A1', { days: 7 });
	assert.deepEqual(calls.map((c) => c[1]), Object.values(USAGE_METRICS));
	assert.equal(calls[0][2].step, 'd');
	assert.equal(calls[0][2].to - calls[0][2].from, 7 * 86400);
	assert.deepEqual(usage.days, ['2026-10-01', '2026-10-03']);
	assert.deepEqual(usage.total.cpu, { '2026-10-01': 20, '2026-10-02': 0, '2026-10-03': 20 });
	assert.deepEqual(usage.total.exec['2026-10-03'], 200);
	assert.deepEqual(usage.sites, [{ id: 'S1', domain: 'analytics.labelvier.dev', cpu: { '2026-10-01': 10, '2026-10-03': 10 }, exec: { '2026-10-01': 100, '2026-10-03': 100 } }]);
});

test('rankSites(): share, averages before/recent (complete days only), growth, peak, sorted on total', () => {
	const today = new Date().toISOString().slice(0, 10);
	const past = (n) => new Date(Date.now() - n * 86400_000).toISOString().slice(0, 10);
	const days = [past(9), past(8), past(7), ...Array.from({ length: 7 }, (_, i) => past(7 - i)).slice(1), today].filter((d, i, a) => a.indexOf(d) === i).sort();
	// 10 days: 3 before, 6 recent complete days, today.
	const complete = days.filter((d) => d < today);
	const before = complete.slice(0, -7);
	const recent = complete.slice(-7);
	const total = {};
	const quiet = {};
	const busy = {};
	for (const d of days) {
		quiet[d] = 1;
		busy[d] = before.includes(d) ? 2 : 8;
		total[d] = quiet[d] + busy[d];
	}
	const usage = { days, total: { cpu: total, exec: total }, sites: [{ id: 'q', domain: 'quiet', cpu: quiet, exec: quiet }, { id: 'b', domain: 'busy', cpu: busy, exec: busy }] };
	const ranked = rankSites(usage, 'cpu');
	assert.deepEqual(ranked.map((r) => r.domain), ['busy', 'quiet']);
	const [b, q] = ranked;
	const sum = (s) => days.reduce((acc, d) => acc + s[d], 0);
	assert.equal(b.total, sum(busy));
	assert.ok(Math.abs(b.share - sum(busy) / sum(total)) < 1e-9);
	assert.equal(b.avgBefore, before.length ? 2 : 0);
	assert.equal(b.avgRecent, 8);
	assert.equal(b.growth, before.length ? 4 : null);
	assert.equal(b.peak, 8);
	assert.ok(recent.includes(b.peakDay) || b.peakDay === today);
	assert.equal(q.growth, before.length ? 1 : null);
	assert.equal(q.avgRecent, 1);
	assert.equal(rankSites({ days: [], total: { cpu: {} }, sites: [{ domain: 'x', cpu: {} }] }, 'cpu')[0].share, 0, 'no total: share 0');
});

// --- DNS ----------------------------------------------------------------------------------

test('dnsPointsTo(): true when an A record matches, false for another IP or an unknown name', async (t) => {
	const dns = await startDnsStub({ 'new.labelvier.dev': SERVER_IP, 'stub-only.test': '9.9.9.9' });
	t.after(() => dns.close());
	assert.equal(await dnsPointsTo('stub-only.test', '9.9.9.9'), true, 'only the stub knows this name: proves no real DNS is used');
	assert.equal(await dnsPointsTo('new.labelvier.dev', SERVER_IP), true);
	assert.equal(await dnsPointsTo('new.labelvier.dev', '1.2.3.4'), false);
	// *.labelvier.dev really is a wildcard record; the stub says NXDOMAIN.
	assert.equal(await dnsPointsTo('unknown.labelvier.dev', SERVER_IP), false);
});

// --- SSH keys -------------------------------------------------------------------------------

test('defaultSshKeyFile(): first of id_ed25519 / id_ecdsa / id_rsa in ~/.ssh, null when none', () => {
	assert.equal(defaultSshKeyFile(), null);
	mkdirSync(path.join(HOME, '.ssh'));
	writeFileSync(path.join(HOME, '.ssh', 'id_rsa.pub'), 'ssh-rsa AAA');
	assert.equal(defaultSshKeyFile(), path.join(HOME, '.ssh', 'id_rsa.pub'));
	writeFileSync(path.join(HOME, '.ssh', 'id_ed25519.pub'), 'ssh-ed25519 BBB');
	assert.equal(defaultSshKeyFile(), path.join(HOME, '.ssh', 'id_ed25519.pub'));
});

const endpointAnswers = {
	request: async (m, e) => ({ data: { features: { username: 'u114-abcdef12' } } }),
	mainDomain: { id: 1, name: 'x.labelvier.dev', config: { ssh_host: 'c1103939.sgvps.net' } },
};

test('sshDetails() / sshCommand(): user from /endpoint, host from the main domain, port 18765', async () => {
	const st = fakeSt(endpointAnswers);
	assert.deepEqual(await sshDetails(st), { user: 'u114-abcdef12', host: 'c1103939.sgvps.net', port: SSH_PORT });
	assert.equal(await sshCommand(st), 'ssh -p 18765 u114-abcdef12@c1103939.sgvps.net');
	assert.deepEqual(st.calls[0], ['request', 'GET', '/endpoint']);
	const noHost = fakeSt({ ...endpointAnswers, mainDomain: { id: 1, name: 'x' } });
	assert.equal((await sshDetails(noHost)).host, 'c1103939.sgvps.net', 'falls back to the api url');
});

test('addSshKey(): authorizes a new key with the comment from the key file; existing key is not re-added', async () => {
	const keyFile = path.join(HOME, 'id_ed25519.pub');
	writeFileSync(keyFile, 'ssh-ed25519 AAAAC3Nza eric@mac\n');
	const st = fakeSt({ ...endpointAnswers, sshKeys: [{ key_pub: 'ssh-rsa OTHER', comment: 'other' }], importSshKey: {} });
	const r = await addSshKey(st, { keyFile });
	assert.equal(r.message, 'SSH key id_ed25519.pub authorized');
	assert.equal(r.ssh, 'ssh -p 18765 u114-abcdef12@c1103939.sgvps.net');
	assert.deepEqual(st.calls.find((c) => c[0] === 'importSshKey'), ['importSshKey', 'ssh-ed25519 AAAAC3Nza eric@mac', 'eric@mac']);

	const existing = fakeSt({ ...endpointAnswers, sshKeys: [{ key_pub: 'ssh-ed25519 AAAAC3Nza', comment: 'already' }], importSshKey: {} });
	const r2 = await addSshKey(existing, { keyFile });
	assert.equal(r2.message, 'SSH key already authorized (already)');
	assert.equal(existing.importSshKey.mock.callCount(), 0);

	writeFileSync(keyFile, 'ssh-ed25519 AAAAC3Nza\n'); // no comment in the key: file name is used
	const noComment = fakeSt({ ...endpointAnswers, sshKeys: [], importSshKey: {} });
	await addSshKey(noComment, { keyFile });
	assert.equal(noComment.importSshKey.mock.calls[0].arguments[1], 'id_ed25519.pub');
	await addSshKey(fakeSt({ ...endpointAnswers, sshKeys: [], importSshKey: {} }), { keyFile, comment: 'given' }).then(() => {});
});

test('defaultSshAlias(): everything before the registrable domain', () => {
	assert.equal(defaultSshAlias('analytics.labelvier.dev'), 'analytics');
	assert.equal(defaultSshAlias('a.b.labelvier.dev'), 'a.b');
	assert.equal(defaultSshAlias('yoni.care'), 'yoni');
	assert.equal(defaultSshAlias('localhost'), 'localhost');
});

// --- SSH alias through the real `labelvier ssh alias` ----------------------------------------

const BIN_DIR = path.join(ROOT, 'bin');
const SSH_CONFIG = path.join(HOME, '.ssh', 'config');

/** Put a `labelvier` on PATH that runs this repo's script, with the update check off. */
function withRepoCli(t) {
	mkdirSync(BIN_DIR, { recursive: true });
	const wrapper = path.join(BIN_DIR, 'labelvier');
	writeFileSync(wrapper, `#!/bin/bash\nexec "${path.join(REPO_DIR, 'labelvier')}" "$@"\n`);
	chmodSync(wrapper, 0o755);
	const previous = { PATH: process.env.PATH, LABELVIER_AUTO_UPDATE: process.env.LABELVIER_AUTO_UPDATE };
	process.env.PATH = `${BIN_DIR}:${process.env.PATH}`;
	process.env.LABELVIER_AUTO_UPDATE = '1';
	t.after(() => {
		process.env.PATH = previous.PATH;
		if (previous.LABELVIER_AUTO_UPDATE === undefined) delete process.env.LABELVIER_AUTO_UPDATE;
		else process.env.LABELVIER_AUTO_UPDATE = previous.LABELVIER_AUTO_UPDATE;
	});
}

const alias = { name: 'analytics', user: 'u114-abcdef12', host: 'c1103939.sgvps.net', port: SSH_PORT };

test('addSshAlias(): adds a Host block to ~/.ssh/config with the private key as IdentityFile', async (t) => {
	withRepoCli(t);
	mkdirSync(path.join(HOME, '.ssh'));
	writeFileSync(path.join(HOME, '.ssh', 'id_ed25519'), 'private');
	writeFileSync(path.join(HOME, '.ssh', 'id_ed25519.pub'), 'ssh-ed25519 AAA');
	const r = await addSshAlias({ ...alias, keyFile: path.join(HOME, '.ssh', 'id_ed25519.pub') });
	assert.deepEqual(r, { ok: true, message: "Added alias 'analytics' -> u114-abcdef12@c1103939.sgvps.net." });
	assert.equal(readFileSync(SSH_CONFIG, 'utf8'), '\nHost analytics\n    HostName c1103939.sgvps.net\n    User u114-abcdef12\n    Port 18765\n    IdentityFile ~/.ssh/id_ed25519\n');
	assert.equal(mode(SSH_CONFIG), 0o600);
});

test('addSshAlias(): without a private key next to the .pub there is no IdentityFile line', async (t) => {
	withRepoCli(t);
	writeFileSync(path.join(HOME, 'key.pub'), 'ssh-ed25519 AAA');
	await addSshAlias({ ...alias, keyFile: path.join(HOME, 'key.pub') });
	assert.doesNotMatch(readFileSync(SSH_CONFIG, 'utf8'), /IdentityFile/);
	await addSshAlias({ ...alias, name: 'nokey', keyFile: undefined });
	assert.match(readFileSync(SSH_CONFIG, 'utf8'), /\nHost nokey\n/);
});

test('addSshAlias(): is idempotent and does not clobber other blocks', async (t) => {
	withRepoCli(t);
	mkdirSync(path.join(HOME, '.ssh'));
	const other = 'Host other\n    HostName other.example\n    User me\n';
	writeFileSync(SSH_CONFIG, other);
	const first = await addSshAlias(alias);
	assert.equal(first.ok, true);
	const second = await addSshAlias(alias);
	assert.deepEqual(second, { ok: false, message: `Alias 'analytics' already exists in ${SSH_CONFIG}.` });
	const config = readFileSync(SSH_CONFIG, 'utf8');
	assert.ok(config.startsWith(other), 'existing block untouched');
	assert.equal(config.match(/^Host analytics$/gm).length, 1);
});

test('addSshAlias(): reports a missing labelvier CLI instead of throwing', async (t) => {
	const previous = process.env.PATH;
	process.env.PATH = path.join(ROOT, 'empty-bin');
	t.after(() => (process.env.PATH = previous));
	assert.deepEqual(await addSshAlias(alias), { ok: false, message: 'labelvier CLI not found, SSH alias not added' });
	assert.equal(existsSync(SSH_CONFIG), false);
});

// --- Site Tools steps ------------------------------------------------------------------------------

test('enableMemcached() / disableMemcached() messages and calls', async () => {
	assert.equal(await enableMemcached(fakeSt({ enableMemcached: { alreadyEnabled: true } })), 'Memcached already enabled');
	assert.equal(await enableMemcached(fakeSt({ enableMemcached: {} })), 'Memcached enabled (127.0.0.1:11211)');
	assert.equal(await disableMemcached(fakeSt({ memcached: null })), 'Memcached already disabled');
	const st = fakeSt({ memcached: { id: 4 }, del: {} });
	assert.equal(await disableMemcached(st), 'Memcached disabled');
	assert.deepEqual(st.calls.at(-1), ['del', '/uservice/4']);
});

test('setupSsl(): strict does not fall back to the main domain', async () => {
	const st = fakeSt({ domains: [{ id: 1, name: 'main.nl' }], mainDomain: { id: 1, name: 'main.nl' }, installLetsEncrypt: {}, enforceHttps: {} });
	const r = await setupSsl(st, { domain: 'alias.nl', serverIp: SERVER_IP, strict: true });
	assert.deepEqual(r, { ok: false, message: 'alias.nl is not a domain of this site' });
	assert.equal(st.mainDomain.mock.callCount(), 0);
	assert.equal(st.installLetsEncrypt.mock.callCount(), 0);
});

test('addDomainAlias(): parks the domain and waits until Site Tools lists it', async () => {
	let listed = [{ name: 'main.nl' }];
	const sg = { addDomainAlias: mock.fn(async () => { listed = [...listed, { name: 'alias.nl' }]; }) };
	const st = fakeSt({ domains: () => listed });
	const site = { id: 'S1', domain: 'main.nl' };
	assert.equal(await addDomainAlias(sg, st, site, 'Alias.NL', { intervalMs: 0 }), 'alias.nl parked on main.nl');
	assert.deepEqual(sg.addDomainAlias.mock.calls[0].arguments, ['S1', 'alias.nl', 'main.nl']);

	// Already there: no write.
	assert.equal(await addDomainAlias(sg, st, site, 'alias.nl', { intervalMs: 0 }), 'alias.nl is already a domain of main.nl');
	assert.equal(sg.addDomainAlias.mock.callCount(), 1);

	// Never shows up: error after the attempts.
	const slow = { addDomainAlias: mock.fn(async () => {}) };
	await assert.rejects(addDomainAlias(slow, fakeSt({ domains: [] }), site, 'late.nl', { intervalMs: 0, attempts: 2 }), /does not list it yet/);
});

test('setupSsl(): skipped while DNS does not point to the server', async (t) => {
	const dns = await startDnsStub({});
	t.after(() => dns.close());
	const st = fakeSt({ domains: [{ id: 1, name: 'x.labelvier.dev' }], installLetsEncrypt: {}, enforceHttps: {} });
	const progress = { text: '' };
	const r = await setupSsl(st, { domain: 'x.labelvier.dev', serverIp: SERVER_IP }, progress);
	assert.deepEqual(r, { ok: false, message: `SSL skipped: x.labelvier.dev does not resolve to ${SERVER_IP} yet` });
	assert.equal(progress.text, 'Checking DNS of x.labelvier.dev…');
	assert.equal(st.installLetsEncrypt.mock.callCount(), 0);
});

test("setupSsl(): installs Let's Encrypt and forces HTTPS once DNS points to the server", async (t) => {
	const dns = await startDnsStub({ 'x.labelvier.dev': SERVER_IP, 'main.labelvier.dev': SERVER_IP });
	t.after(() => dns.close());
	const domain = { id: 1, name: 'x.labelvier.dev', cert_id: null, settings: { https_rewrite_links: 0 } };
	const st = fakeSt({ domains: [domain], installLetsEncrypt: {}, enforceHttps: {} });
	const progress = { text: '' };
	const r = await setupSsl(st, { domain: 'x.labelvier.dev', serverIp: SERVER_IP, https: true }, progress);
	assert.deepEqual(r, { ok: true, message: "Let's Encrypt installed on x.labelvier.dev (+ www), HTTPS forced" });
	assert.deepEqual(st.calls.slice(1), [['installLetsEncrypt', 1], ['enforceHttps', domain, true]]);
	assert.equal(progress.text, 'Forcing HTTPS…');

	// Certificate present + no https: nothing written.
	const withCert = fakeSt({ domains: [{ ...domain, cert_id: 9 }], installLetsEncrypt: {}, enforceHttps: {} });
	const r2 = await setupSsl(withCert, { domain: 'x.labelvier.dev', serverIp: SERVER_IP, https: false });
	assert.deepEqual(r2, { ok: true, message: 'SSL certificate already installed on x.labelvier.dev' });
	assert.equal(withCert.installLetsEncrypt.mock.callCount(), 0);
	assert.equal(withCert.enforceHttps.mock.callCount(), 0);

	// Unknown domain name: the main domain is used.
	const main = fakeSt({ domains: [{ id: 2, name: 'www.other' }], mainDomain: { id: 3, name: 'main.labelvier.dev' }, installLetsEncrypt: {}, enforceHttps: {} });
	const r3 = await setupSsl(main, { domain: 'typo.labelvier.dev', serverIp: SERVER_IP, https: false });
	assert.equal(r3.message, "Let's Encrypt installed on main.labelvier.dev (+ www)");
	assert.deepEqual(main.calls.at(-1), ['installLetsEncrypt', 3]);
});

test('createDatabase(): database, user with a generated password, grant; progress per sub-step', async () => {
	const st = fakeSt({ createDatabase: { data: { id: 1, name: 'dbabc' } }, createDbUser: { data: { id: 2, name: 'uabc' } }, grantAll: {} });
	const texts = [];
	const progress = { set text(v) { texts.push(v); } };
	const db = await createDatabase(st, { label: 'shop' }, progress);
	assert.deepEqual({ ...db, password: '*' }, { label: 'shop', name: 'dbabc', user: 'uabc', password: '*', host: 'localhost' });
	assert.match(db.password, /a1!$/);
	assert.deepEqual(st.calls, [['createDatabase', 'shop'], ['createDbUser', 'shop', db.password], ['grantAll', 1, 2]]);
	assert.deepEqual(texts, ['Creating database "shop"…', 'Creating database user "shop"…', 'Granting privileges…']);
});

// --- PHP -----------------------------------------------------------------------------------------

const VERSIONS = [
	{ id: 82, version: 'PHP 8.2.29', mod_php: true },
	{ id: 83, version: 'PHP 8.3.35', default: true, recommended: true, mod_php: true },
];

test('serverPhpVersions(): asks an active site on the account, null without one', async () => {
	const phpVersions = mock.fn(async () => VERSIONS);
	const sg = fakeSg({ siteTools: mock.fn(() => ({ phpVersions })) });
	assert.deepEqual(await serverPhpVersions(sg, 'A1'), VERSIONS);
	assert.deepEqual(sg.siteTools.mock.calls[0].arguments, ['S1']);
	assert.equal(await serverPhpVersions(sg, 'A9'), null);
	assert.equal(await serverPhpVersions(fakeSg({ sites: async () => [{ account_id: 'A1', status: 'pending' }] }), 'A1'), null, 'pending sites do not count');
});

test('parsePhpVersion(): accepts 8.3 / 83 / PHP 8.3 / managed, rejects unknown versions with the list', () => {
	for (const input of ['8.3', '83', 'PHP 8.3', 'php8.3', ' 8.3.35 ']) assert.equal(parsePhpVersion(input, VERSIONS), 83, input);
	for (const input of ['managed', 'Auto', 'default']) assert.equal(parsePhpVersion(input, VERSIONS), null, input);
	assert.throws(() => parsePhpVersion('7.4', VERSIONS), /^Error: Unknown PHP version "7\.4"\. Available: 8\.2, 8\.3, managed$/);
	assert.throws(() => parsePhpVersion('8.3', null), /Available: unknown, managed/);
});

test('phpLabel(): version name, managed with the current default, or a guess from the id', () => {
	assert.equal(phpLabel(VERSIONS, 83), 'PHP 8.3.35');
	assert.equal(phpLabel(VERSIONS, null), 'managed by SiteGround (now PHP 8.3.35)');
	assert.equal(phpLabel(null, undefined), 'managed by SiteGround');
	assert.equal(phpLabel(null, 81), 'PHP 8.1');
});

test('setPhpVersion(): sets and reports the label', async () => {
	const st = fakeSt({ phpVersions: VERSIONS, setPhpVersion: {} });
	assert.equal(await setPhpVersion(st, 82), 'PHP set to PHP 8.2.29');
	assert.deepEqual(st.calls.at(-1), ['setPhpVersion', 82]);
	assert.equal(await setPhpVersion(st, null), 'PHP set to managed by SiteGround (now PHP 8.3.35)');
});

// --- Cron ----------------------------------------------------------------------------------------

test('parseCronSchedule(): five fields or an @alias; anything else throws', () => {
	assert.deepEqual(parseCronSchedule('*/5 1-3  * * 7'), { min: '*/5', hour: '1-3', day: '*', mon: '*', dow: '7' });
	assert.deepEqual(parseCronSchedule('@daily'), { min: '0', hour: '0', day: '*', mon: '*', dow: '*' });
	assert.deepEqual(parseCronSchedule(' @weekly '), { min: '0', hour: '0', day: '*', mon: '*', dow: '0' });
	assert.equal(parseCronSchedule('@hourly').hour, '*');
	assert.equal(parseCronSchedule('@monthly').day, '1');
	for (const bad of ['* * * *', '* * * * * *', 'a b c d e', '@yearly', '']) assert.throws(() => parseCronSchedule(bad), /^Error: Invalid schedule/, bad);
});

test('cronSchedule() joins the five fields of a job', () => {
	assert.equal(cronSchedule({ id: 1, cmd: 'x', min: '0', hour: '3', day: '*', mon: '*', dow: '0' }), '0 3 * * 0');
});

test('addCronJob(): creates a job, or reports the existing one with the same command and schedule', async () => {
	const st = fakeSt({ cronJobs: [], createCronJob: { data: { id: 12 } } });
	const r = await addCronJob(st, { cmd: 'php cron.php', schedule: '@hourly' });
	assert.deepEqual(r, { job: { id: 12 }, message: 'Cron job added (#12): 0 * * * * php cron.php' });
	assert.deepEqual(st.calls.at(-1), ['createCronJob', 'php cron.php', { min: '0', hour: '*', day: '*', mon: '*', dow: '*' }]);

	const existing = { id: 7, cmd: 'php cron.php', min: '0', hour: '*', day: '*', mon: '*', dow: '*' };
	const st2 = fakeSt({ cronJobs: [existing], createCronJob: {} });
	assert.deepEqual(await addCronJob(st2, { cmd: 'php cron.php', schedule: '0 * * * *' }), { job: existing, message: 'Cron job already exists (#7)' });
	assert.equal(st2.createCronJob.mock.callCount(), 0);

	const st3 = fakeSt({ cronJobs: [], createCronJob: undefined });
	assert.equal((await addCronJob(st3, { cmd: 'x', schedule: '* * * * *' })).message, 'Cron job added: * * * * * x');
	await assert.rejects(addCronJob(st3, { cmd: 'x', schedule: 'bad' }), /Invalid schedule/);
});
