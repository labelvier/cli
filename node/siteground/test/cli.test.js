import { ROOT, PKG_DIR, tokenExpiringIn } from './helpers.js'; // first: sandbox + fetch guard
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';

// The CLI runs on import, so every case is a child process with its own empty SG_STATE_DIR and HOME.
// test/fixtures/fake-api.mjs is preloaded: canned SiteGround answers + local DNS, no network.
// `login` is never run (it opens a browser).

const CLI = path.join(PKG_DIR, 'src', 'cli.js');
const FAKE_API = path.join(PKG_DIR, 'test', 'fixtures', 'fake-api.mjs');
const HELP_FIRST_LINE = 'Usage: labelvier siteground <command> [options]';

let sandbox, stateDir, home, fetchLog;
beforeEach(() => {
	sandbox = mkdtempSync(path.join(ROOT, 'cli-'));
	stateDir = path.join(sandbox, 'state');
	home = path.join(sandbox, 'home');
	fetchLog = path.join(sandbox, 'fetch.log');
	mkdirSync(home);
});

/** Run the CLI; resolves { code, stdout, stderr }. stdin gets `input` (default: closed at once). */
function run(args, { input = '', env = {} } = {}) {
	return new Promise((resolve) => {
		const child = execFile(
			process.execPath,
			['--import', FAKE_API, CLI, ...args],
			{
				cwd: PKG_DIR,
				env: { PATH: process.env.PATH, HOME: home, SG_STATE_DIR: stateDir, SG_TEST_FETCH_LOG: fetchLog, NO_COLOR: '1', TZ: 'UTC', LANG: 'en_US.UTF-8', ...env },
				timeout: 30_000,
			},
			(error, stdout, stderr) => resolve({ code: error ? error.code : 0, stdout, stderr }),
		);
		child.stdin.end(input);
	});
}

/** Environment of a logged-in user: tokens from the environment (SG_REFRESH_TOKEN wins over the file). */
const loggedIn = () => ({ SG_TOKEN: tokenExpiringIn(3600), SG_REFRESH_TOKEN: tokenExpiringIn(86400) });
const requests = () => (existsSync(fetchLog) ? readFileSync(fetchLog, 'utf8').trim().split('\n').map((l) => JSON.parse(l)) : []);
const requested = () => requests().map((r) => `${r.method} ${r.url.replace(/^https:\/\/[^/]+(\/v1|\/api-sgcp\/v00)/, '')}`);

// --- help / dispatch -------------------------------------------------------------------

test('no arguments: help on stdout, exit 0', async () => {
	const r = await run([]);
	assert.equal(r.code, 0);
	assert.equal(r.stderr, '');
	assert.ok(r.stdout.startsWith(HELP_FIRST_LINE));
	assert.match(r.stdout, /\n  create-site \[--domain <domain>\]/);
});

test('--help (and -h) print the help, also with a command', async () => {
	for (const args of [['--help'], ['-h'], ['accounts', '--help']]) {
		const r = await run(args);
		assert.equal(r.code, 0, args.join(' '));
		assert.ok(r.stdout.startsWith(HELP_FIRST_LINE));
	}
	assert.deepEqual(requests(), [], 'help never talks to the API');
});

test('unknown command: "✗ Unknown command: x" on stderr, help on stdout, exit 1', async () => {
	const r = await run(['frobnicate']);
	assert.equal(r.code, 1);
	assert.equal(r.stderr, '\x1b[31m✗\x1b[0m Unknown command: frobnicate\n');
	assert.ok(r.stdout.startsWith(HELP_FIRST_LINE));
});

test('an unknown option is a parseArgs error (exit 1)', async () => {
	const r = await run(['accounts', '--bogus']);
	assert.equal(r.code, 1);
	assert.match(r.stderr, /Unknown option '--bogus'/);
});

// --- session commands (no client needed) -----------------------------------------------------

test('logout with nothing stored: "Nothing to remove", exit 0', async () => {
	const r = await run(['logout']);
	assert.equal(r.code, 0);
	assert.equal(r.stdout, 'Nothing to remove: not logged in.\n');
	assert.equal(existsSync(stateDir), false);
});

test('logout removes the session and browser profile, --forget also .env', async () => {
	mkdirSync(path.join(stateDir, '.browser-profile'), { recursive: true });
	writeFileSync(path.join(stateDir, '.session.json'), '{}');
	writeFileSync(path.join(stateDir, '.env'), 'SG_LOGIN_EMAIL=x@example.com\n');
	const r = await run(['logout']);
	assert.equal(r.code, 0);
	assert.equal(r.stdout, `Removed ${path.join(stateDir, '.session.json')}\nRemoved ${path.join(stateDir, '.browser-profile')}\nLogged out. Credentials in .env are kept (use --forget to remove them too).\n`);
	assert.equal(existsSync(path.join(stateDir, '.env')), true);
	const r2 = await run(['logout', '--forget']);
	assert.equal(r2.stdout, `Removed ${path.join(stateDir, '.env')}\nLogged out, credentials forgotten.\n`);
});

test('session:status without a session: "No session found" error naming the file, exit 1', async () => {
	const r = await run(['session:status']);
	assert.equal(r.code, 1);
	assert.equal(r.stdout, '');
	assert.equal(r.stderr, `Error: No session found. Run "labelvier siteground login" first (expected ${path.join(stateDir, '.session.json')}).\n`);
});

test('session:import reads JSON from stdin, writes .session.json (0600) and prints the expiry', async () => {
	const token = tokenExpiringIn(3600);
	const refreshToken = tokenExpiringIn(86400);
	const r = await run(['session:import'], { input: JSON.stringify({ token, refreshToken, other: 1 }) });
	assert.equal(r.code, 0, r.stderr);
	assert.match(r.stdout, /^Session stored, refresh token valid until \S+/);
	const file = path.join(stateDir, '.session.json');
	assert.deepEqual(JSON.parse(readFileSync(file, 'utf8')), { token, refreshToken });
	assert.equal(statSync(file).mode & 0o777, 0o600);
	assert.equal(statSync(stateDir).mode & 0o777, 0o700);

	const status = await run(['session:status']);
	assert.equal(status.code, 0, status.stderr);
	assert.match(status.stdout, /^access token  until \S+.*\nrefresh token until \S+/);

	const noAccess = await run(['session:import'], { input: JSON.stringify({ refreshToken }) });
	assert.equal(noAccess.code, 0, noAccess.stderr);
	const status2 = await run(['session:status']);
	assert.match(status2.stdout, /^access token  until -\n/, 'no access token shows as -');
});

test('session:import without a refreshToken fails', async () => {
	const r = await run(['session:import'], { input: '{"token":"x"}' });
	assert.equal(r.code, 1);
	assert.equal(r.stderr, 'Error: Input JSON needs a "refreshToken" field\n');
	assert.equal(existsSync(stateDir), false);
});

test('session:import rejects a refreshToken or token that is not a JWT, and non-JSON input', async () => {
	const bad = await run(['session:import'], { input: JSON.stringify({ refreshToken: 'not-a-jwt' }) });
	assert.equal(bad.code, 1);
	assert.match(bad.stderr, /^Error: refreshToken is not a valid JWT \(Not a JWT: .*\)/);
	assert.equal(existsSync(stateDir), false, 'nothing stored');

	const badAccess = await run(['session:import'], { input: JSON.stringify({ token: 'nope', refreshToken: tokenExpiringIn(86400) }) });
	assert.equal(badAccess.code, 1);
	assert.match(badAccess.stderr, /^Error: token is not a valid JWT \(Not a JWT: .*\)/);
	assert.equal(existsSync(stateDir), false, 'nothing stored');

	const notJson = await run(['session:import'], { input: 'garbage' });
	assert.equal(notJson.code, 1);
	assert.match(notJson.stderr, /^Error: Input is not valid JSON: /);
});

test('session:status with a non-JWT token in the session file prints a clear error instead of crashing', async () => {
	mkdirSync(stateDir, { recursive: true });
	writeFileSync(path.join(stateDir, '.session.json'), JSON.stringify({ token: 'garbage', refreshToken: tokenExpiringIn(86400) }));
	const r = await run(['session:status']);
	assert.equal(r.code, 1);
	assert.equal(r.stdout, '');
	assert.match(r.stderr, /^Error: token is not a valid JWT \(Not a JWT: [^)]+\)\. Run "labelvier siteground login" again/);
	assert.doesNotMatch(r.stderr, /Buffer|TypeError|at .*\.js/);
});

test('session:status with a corrupt (non-JSON) session file prints a clear error naming the file', async () => {
	mkdirSync(stateDir, { recursive: true });
	const file = path.join(stateDir, '.session.json');
	writeFileSync(file, '{not json');
	const r = await run(['session:status']);
	assert.equal(r.code, 1);
	assert.equal(r.stderr, `Error: Session file is corrupt (not valid JSON): ${file}. Run "labelvier siteground login" again.\n`);

	writeFileSync(file, 'null');
	const r2 = await run(['session:status']);
	assert.equal(r2.code, 1);
	assert.equal(r2.stderr, `Error: Session file is corrupt: ${file}. Run "labelvier siteground login" again.\n`);
});

test('setup without a terminal: "Missing Email (no terminal …)", nothing written', async () => {
	const r = await run(['setup']);
	assert.equal(r.code, 1);
	assert.equal(r.stdout, `Credentials for the automatic login go to ${path.join(stateDir, '.env')} (chmod 600).\n`);
	assert.equal(r.stderr, 'Error: Missing Email (no terminal to ask it in; pass it as option)\n');
	assert.equal(existsSync(stateDir), false);
});

// --- commands that need a client ----------------------------------------------------------------

test('a client command without a session fails before any request', async () => {
	const r = await run(['accounts']);
	assert.equal(r.code, 1);
	assert.match(r.stderr, /^Error: No session found/);
	assert.deepEqual(requests(), []);
});

test('accounts: plans with site count and disk usage (spinner lines on stderr)', async () => {
	const r = await run(['accounts'], { env: loggedIn() });
	assert.equal(r.code, 0, r.stderr);
	assert.equal(r.stderr, '… Getting hosting plans…\n✔ 2 hosting plans\n');
	assert.equal(r.stdout, [
		'Develop - Hamerkop       1 sites  10/40 GB (25%), 30 GB free         GoGeek  Amsterdam',
		'Basis - Albatros         1 sites  30/40 GB (75%), 10 GB free         GrowBig  Amsterdam',
		'',
	].join('\n'));
	assert.deepEqual(requested().sort(), [
		'GET /account/TFE3L1oza01JUT09/stats/disk',
		'GET /account/TFFEeVkzOEZJQT09/stats/disk',
		'GET /accounts?sort_field=created&sort_order=DESC',
		'GET /sites/list',
	]);
	assert.equal(existsSync(path.join(stateDir, '.session.json')), false, 'a session from the environment is never written');
});

test('accounts --json prints the enriched accounts as JSON', async () => {
	const r = await run(['accounts', '--json'], { env: loggedIn() });
	assert.equal(r.code, 0, r.stderr);
	const accounts = JSON.parse(r.stdout);
	assert.equal(accounts[0].name, 'Develop - Hamerkop');
	assert.equal(accounts[0].siteCount, 1);
	assert.equal(accounts[0].diskLimitGb, 40);
});

test('accounts --demo: made-up bird plans only, real names and ids masked', async () => {
	const r = await run(['accounts', '--demo'], { env: loggedIn() });
	assert.equal(r.code, 0, r.stderr);
	assert.equal(r.stdout, ['Start - Roodborst', 'Basis - Grutto', 'Basis - Kievit', 'Basis - Tureluur', 'Compleet - Lepelaar', 'Compleet - Ooievaar', 'Develop - Kraanvogel', 'Develop - Reiger', ''].join('\n'));
	assert.equal(r.stderr, '… Getting hosting plans…\n✔ 8 hosting plans\n');
	const json = await run(['accounts', '--demo', '--json'], { env: { ...loggedIn(), SG_DEMO: '1' } });
	assert.doesNotMatch(json.stdout, /Hamerkop|Albatros|TFFEeVkzOEZJQT09|35\.214\./, 'masked on the way out');
	assert.match(json.stdout, /"name": "Develop - Reiger"/);
	assert.match(json.stdout, /"ip": "•••\.•••\.•••\.•••"/);
});

test('sites: list, filtered on --account, --json', async () => {
	const all = await run(['sites'], { env: loggedIn() });
	assert.equal(all.code, 0, all.stderr);
	assert.equal(all.stdout, [
		'SmczellITUpKZz09  analytics.labelvier.dev                  wordpress  active         Develop - Hamerkop',
		'TXpBd05EZz09  yoni.care                                wordpress  active         Basis - Albatros',
		'',
	].join('\n'));
	const filtered = await run(['sites', '--account', 'albatros'], { env: loggedIn() });
	assert.equal(filtered.stdout, 'TXpBd05EZz09  yoni.care                                wordpress  active         Basis - Albatros\n');
	const json = await run(['sites', '--json', '--account', 'TFFEeVkzOEZJQT09'], { env: loggedIn() });
	assert.deepEqual(JSON.parse(json.stdout).map((s) => s.domain), ['analytics.labelvier.dev']);
	const none = await run(['sites', '--account', 'nope'], { env: loggedIn() });
	assert.equal(none.code, 1);
	assert.match(none.stderr, /matched 0 accounts/);
});

test('site:info without a domain, site:stats --days validation, account:stats without a plan', async () => {
	const info = await run(['site:info'], { env: loggedIn() });
	assert.equal(info.code, 1);
	assert.equal(info.stderr, 'Error: Domain is required, e.g. labelvier siteground site:info example.com\n');
	const days = await run(['site:stats', 'yoni.care', '--days', 'x'], { env: loggedIn() });
	assert.equal(days.stderr, 'Error: --days needs a positive whole number\n');
	const stats = await run(['account:stats'], { env: loggedIn() });
	assert.match(stats.stderr, /^Error: Hosting plan is required/);
	const sort = await run(['account:stats', 'Hamerkop', '--sort', 'ram'], { env: loggedIn() });
	assert.equal(sort.stderr, 'Error: --sort must be cpu or exec\n');
	const cron = await run(['site:cron', 'yoni.care', '--add', 'x', '--remove', '1'], { env: loggedIn() });
	assert.equal(cron.stderr, 'Error: Use either --add or --remove, not both\n');
	const at = await run(['site:cron', 'yoni.care', '--add', 'x', '--at', 'nope'], { env: loggedIn() });
	assert.match(at.stderr, /^Error: Invalid schedule "nope"/);
	assert.deepEqual(requests(), [], 'all of these fail before the first request');
});

test('create-site --dry-run: walks every read step with the given options and creates nothing', async () => {
	const r = await run(
		['create-site', '--domain', 'New.labelvier.dev', '--account', 'Hamerkop', '--app', 'wordpress', '--wp-email', 'a@b.nl', '--php', '8.3', '--no-memcached', '--no-ssl', '--no-ssh-key', '--no-db', '--dry-run'],
		{ env: loggedIn() },
	);
	assert.equal(r.code, 0, r.stderr);
	assert.equal(r.stderr, [
		'… Checking whether new.labelvier.dev already exists…',
		'✔ new.labelvier.dev is not in use yet',
		'… Getting hosting plans and disk usage…',
		'✔ 2 hosting plans',
		'… Checking domain and DNS for new.labelvier.dev…',
		'✔ new.labelvier.dev points to 35.214.252.94',
		'… Getting PHP versions…',
		'✔ PHP 8.2, 8.3 available',
		'',
	].join('\n'));
	assert.equal(r.stdout, [
		'',
		'Domain      new.labelvier.dev (registered: yes, DNS -> 35.214.252.94: yes)',
		'Plan        Develop - Hamerkop (Amsterdam)',
		'App         WordPress, admin a@b.nl',
		'PHP         PHP 8.3.35',
		'Memcached   no',
		'SSL         no',
		'SSH key     no',
		'Database    created by installer',
		'',
		'Dry run: nothing created.',
		'',
	].join('\n'));
	const calls = requested();
	assert.ok(calls.every((c) => c.startsWith('GET ')), `only reads: ${calls.join(', ')}`);
	assert.ok(calls.includes('GET /domain/checkexisting/TFFEeVkzOEZJQT09/new.labelvier.dev'));
	assert.ok(calls.includes('GET /auth/sites/SmczellITUpKZz09/token'), 'PHP versions come from an existing site on the plan');
	assert.ok(calls.includes('GET /php-version'));
	assert.equal(existsSync(path.join(stateDir, '.credentials')), false);
});

test('create-site: validation of --domain, --app and --php, existing domain refused', async () => {
	const domain = await run(['create-site', '--domain', 'not a domain'], { env: loggedIn() });
	assert.equal(domain.stderr, 'Error: not a domain: not a valid domain\n');
	const app = await run(['create-site', '--domain', 'new.labelvier.dev', '--account', 'Hamerkop', '--app', 'drupal'], { env: loggedIn() });
	assert.match(app.stderr, /Error: --app must be one of: none, wordpress, woocommerce\n$/);
	const php = await run(['create-site', '--domain', 'new.labelvier.dev', '--account', 'Hamerkop', '--app', 'none', '--php', '5.6'], { env: loggedIn() });
	assert.match(php.stderr, /Error: Unknown PHP version "5\.6"\. Available: 8\.2, 8\.3, managed\n$/);
	const existing = await run(['create-site', '--domain', 'yoni.care'], { env: loggedIn() });
	assert.equal(existing.code, 1);
	assert.match(existing.stderr, /✖ Checking whether yoni\.care already exists failed\nError: Site yoni\.care already exists on Basis - Albatros \(TXpBd05EZz09\)\n$/);
	const missing = await run(['create-site'], { env: loggedIn() });
	assert.equal(missing.stderr, 'Error: Missing --domain (no terminal to ask it in; pass it as option)\n');
	assert.ok(requested().every((c) => c.startsWith('GET ')));
});

test('create-site --demo --dry-run: server details hidden, demo plan name shown', async () => {
	const r = await run(['create-site', '--demo', '--dry-run', '--domain', 'new.labelvier.dev', '--account', 'Hamerkop', '--app', 'none', '--php', 'managed', '--no-memcached', '--no-ssl', '--no-ssh-key', '--no-db'], { env: loggedIn() });
	assert.equal(r.code, 0, r.stderr);
	assert.match(r.stdout, /Domain      new\.labelvier\.dev \(registered: yes, DNS -> server: yes\)\nPlan        Develop - Reiger\n/);
	assert.match(r.stdout, /PHP         managed by SiteGround \(now PHP 8\.3\.35\)/);
	assert.doesNotMatch(r.stdout + r.stderr, /Hamerkop|35\.214|sgvps/);
	assert.match(r.stderr, /✔ new\.labelvier\.dev points to the server\n/);
	rmSync(sandbox, { recursive: true, force: true });
});
