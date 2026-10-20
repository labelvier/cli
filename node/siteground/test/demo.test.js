import { HOME, STATE_DIR, fakeStream, jsonResponse, tokenExpiringIn } from './helpers.js'; // first: sandbox + fetch guard
import { test, before, after, beforeEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { SiteGroundClient } from '../src/client.js';
import { SiteToolsClient } from '../src/sitetools.js';
import { demo, enableDemo, mask, fakeActions, withDemoPlans } from '../src/demo.js';

// enableDemo() patches the prototypes and the output streams for good: this file is its own process.
// The streams are swapped for recorders BEFORE enableDemo wraps them, so the masking is observable.
let stdout, stderr;
before(() => {
	stdout = fakeStream('stdout', { isTTY: false });
	stderr = fakeStream('stderr', { isTTY: false });
	assert.equal(demo.enabled, false);
	enableDemo();
});
after(() => {
	stdout.restore();
	stderr.restore();
});
beforeEach(() => {
	stdout.reset();
	stderr.reset();
});

const session = () => ({ token: tokenExpiringIn(3600), refreshToken: tokenExpiringIn(86400), fromEnv: true });

/** Run `promise` while draining every pending (mocked) timer, so demo pauses cost no real time. */
async function withFakeTimers(t, run) {
	t.mock.timers.enable({ apis: ['setTimeout'] });
	const result = run();
	let settled = false;
	result.then(() => (settled = true), () => (settled = true));
	for (let i = 0; i < 100 && !settled; i++) {
		t.mock.timers.tick(10_000);
		await new Promise((r) => setImmediate(r));
	}
	t.mock.timers.reset();
	return result;
}

test('enableDemo() flips the flag', () => {
	assert.equal(demo.enabled, true);
});

test('mask(): IPs (not 127.0.0.1), *.sgvps.net hosts and SSH users are replaced', () => {
	assert.equal(mask('server 35.214.252.94 (c1103939.sgvps.net), ssh -p 18765 u114-abcdef12@c1103939.sgvps.net, memcached 127.0.0.1:11211'),
		'server •••.•••.•••.••• (••••••.sgvps.net), ssh -p 18765 u•••-••••••••@••••••.sgvps.net, memcached 127.0.0.1:11211');
	assert.equal(mask('Develop - Hamerkop'), 'Develop - Hamerkop', 'plan names are not masked until withDemoPlans ran');
});

test('stdout and stderr are masked, including ids seen in API responses', async (t) => {
	t.mock.method(globalThis, 'fetch', async () => jsonResponse({ status: 200, data: { accounts: [{ id: 'TFFEeVkzOEZJQT09', name: 'Develop - Hamerkop', server: { ip: '35.214.252.94', location: 'Amsterdam' }, short: 'abc', plain: 'notmasked' }] } }));
	const sg = new SiteGroundClient(session());
	const accounts = await sg.accounts();
	assert.equal(accounts[0].id, 'TFFEeVkzOEZJQT09', 'the data itself is untouched');
	console.log('plan TFFEeVkzOEZJQT09 on 35.214.252.94 in Amsterdam, abc notmasked');
	process.stderr.write('✔ TFFEeVkzOEZJQT09 found\n');
	assert.equal(stdout.text(), 'plan •••••••••• on •••.•••.•••.••• in Amsterdam, abc notmasked\n');
	assert.equal(stderr.text(), '✔ •••••••••• found\n');
	assert.equal(mask('location Amsterdam'), 'location Amsterdam', 'plain words under a secret key stay readable');
});

test('writes to the client area are blocked; refresh and wizard step3 pass through', async (t) => {
	const calls = [];
	t.mock.method(globalThis, 'fetch', async (url, init) => {
		calls.push(`${init.method} ${url.replace('https://uapi.siteground.com/v1', '')}`);
		return jsonResponse({ status: 200, data: { client_token: tokenExpiringIn(3600), extras: [] } });
	});
	const sg = new SiteGroundClient(session());
	await assert.rejects(sg.post('/sites/wizard', {}), /^Error: Demo mode: blocked POST \/sites\/wizard$/);
	await assert.rejects(sg.request('DELETE', '/sites/S1'), /blocked DELETE/);
	await sg.post('/sites/wizard/step3/A1', {});
	sg.session.token = null;
	await sg.token(); // refresh
	assert.deepEqual(calls, ['POST /sites/wizard/step3/A1', 'POST /auth/refresh-client-token']);
});

test('Site Tools: only GET passes, api_url hosts seen are masked', async (t) => {
	const st = new SiteToolsClient({ get: async () => ({ site_token: tokenExpiringIn(3600, { api_url: 'c999999.sgvps.net', cts: Math.floor(Date.now() / 1000), vsec: 3600 }) }) }, 'S1');
	await assert.rejects(st.post('/ssl-le', { domain_id: 1 }), /^Error: Demo mode: blocked POST \/ssl-le$/);
	await assert.rejects(st.del('/uservice/4'), /blocked DELETE/);
	t.mock.method(globalThis, 'fetch', async () => jsonResponse({ status: 200, data: [{ id: 1, name: 'x.labelvier.dev', config: { ssh_host: 'c999999.sgvps.net' } }] }));
	assert.equal((await st.domains())[0].name, 'x.labelvier.dev');
	console.log('host c999999.sgvps.net');
	assert.equal(stdout.text(), 'host ••••••.sgvps.net\n');
});

test('checkExistingDomain() pretends the check passed when SiteGround refuses', async (t) => {
	t.mock.method(globalThis, 'fetch', async () => jsonResponse({ status: 400, message: 'validation.domain' }, 400));
	const sg = new SiteGroundClient(session());
	assert.deepEqual(await sg.checkExistingDomain('A1', 'existing.labelvier.dev'), { registered: 1, client_is_owner_of_domain: true });
	t.mock.method(globalThis, 'fetch', async () => jsonResponse({ status: 200, data: { registered: 0 } }));
	assert.deepEqual(await sg.checkExistingDomain('A1', 'new.labelvier.dev'), { registered: 0 }, 'a real answer is passed on');
});

test('createSite() and waitForOrder() are simulated without any request', async (t) => {
	const sg = new SiteGroundClient(session());
	const orderId = await withFakeTimers(t, () => sg.createSite({ accountId: 'A1', domain: 'x.labelvier.dev', app: null }));
	assert.match(orderId, /^DEMO[0-9A-Z]+$/);
	assert.equal(sg.demoApp, false);
	const ticks = [];
	const result = await withFakeTimers(t, () => sg.waitForOrder(orderId, { onTick: (items, i) => ticks.push([i, items.map((it) => `${it.product_name}:${it.status}`).join(',')]) }));
	assert.deepEqual(result, { ok: true, items: [{ product_name: 'site_activation', status: 100 }] });
	assert.deepEqual(ticks, [[1, 'site_activation:1'], [2, 'site_activation:100']]);

	await withFakeTimers(t, () => sg.createSite({ app: { name: 'WordPress' } }));
	assert.equal(sg.demoApp, true);
	const withApp = await withFakeTimers(t, () => sg.waitForOrder('x'));
	assert.deepEqual(withApp.items, [{ product_name: 'site_activation', status: 100 }, { product_name: 'cms_install', status: 100 }]);
});

test('withDemoPlans(): real plans get bird names in order, extras borrow a real plan, names are masked from then on', () => {
	const real = [
		{ id: 'H', name: 'Develop - Hamerkop', server: { ip: '1.1.1.1' } },
		{ id: 'AL', name: 'Basis - Albatros' },
		{ id: 'AA', name: 'Basis - Aalscholver' },
		{ id: 'Z', name: 'Compleet - Zeearend' },
	];
	const plans = withDemoPlans(real);
	assert.deepEqual(plans.map((p) => p.name), [
		'Start - Roodborst',
		'Basis - Grutto', 'Basis - Kievit', 'Basis - Tureluur',
		'Compleet - Lepelaar', 'Compleet - Ooievaar',
		'Develop - Kraanvogel', 'Develop - Reiger',
	]);
	const by = (name) => plans.find((p) => p.name === name);
	assert.equal(by('Basis - Grutto').id, 'AA', 'alphabetical: Aalscholver first');
	assert.equal(by('Basis - Tureluur').id, 'AL');
	assert.equal(by('Basis - Kievit').id, 'AA', 'extra Basis plan borrows the first real one');
	assert.equal(by('Basis - Kievit').demoExtra, true);
	assert.equal(by('Start - Roodborst').id, 'H', 'no real Start plan: borrows the Develop plan');
	assert.equal(by('Develop - Reiger').id, 'H');
	assert.equal(by('Develop - Reiger').demoExtra, undefined);
	assert.equal(by('Develop - Kraanvogel').demoExtra, true);
	assert.equal(mask('Develop - Hamerkop / Basis - Albatros'), 'Develop - Reiger / Basis - Tureluur');
	console.log('Site on Compleet - Zeearend');
	assert.equal(stdout.text(), 'Site on Compleet - Lepelaar\n');
	assert.equal(withDemoPlans([{ id: 'X', name: 'Other plan' }]).every((p) => p.id === 'X'), true, 'no typed plans: everything borrows the first');
});

test('fakeActions: simulated steps with the same shapes as the real ones', async (t) => {
	assert.equal(await withFakeTimers(t, () => fakeActions.enableMemcached()), 'Memcached enabled (127.0.0.1:11211)');
	assert.equal(await withFakeTimers(t, () => fakeActions.setPhpVersion('PHP 8.3.35')), 'PHP set to PHP 8.3.35');
	assert.equal(await withFakeTimers(t, () => fakeActions.addSshKey('/x/id.pub')), 'SSH key authorized');
	assert.deepEqual(await withFakeTimers(t, () => fakeActions.addSshAlias('analytics')), { ok: true, message: "Added alias 'analytics'" });

	const progress = { text: '' };
	assert.deepEqual(await fakeActions.setupSsl({ domain: 'x.labelvier.dev', https: true }, progress, false), { ok: false, message: 'SSL skipped: x.labelvier.dev does not resolve to the server yet' });
	const ssl = await withFakeTimers(t, () => fakeActions.setupSsl({ domain: 'x.labelvier.dev', https: true }, progress, true));
	assert.deepEqual(ssl, { ok: true, message: "Let's Encrypt installed on x.labelvier.dev (+ www), HTTPS forced" });
	assert.equal(progress.text, 'Forcing HTTPS…');
	const noHttps = await withFakeTimers(t, () => fakeActions.setupSsl({ domain: 'x.labelvier.dev', https: false }, progress, true));
	assert.equal(noHttps.message, "Let's Encrypt installed on x.labelvier.dev (+ www)");

	const db = await withFakeTimers(t, () => fakeActions.createDatabase('shop', progress));
	assert.equal(db.label, 'shop');
	assert.match(db.name, /^db[a-z0-9]{10}$/);
	assert.match(db.user, /^u[a-z0-9]{10}$/);
	assert.equal(db.password, '••••••••••••');
	assert.equal(db.host, 'localhost');
	assert.equal(progress.text, 'Granting privileges…');
});

test('demo mode leaves .credentials and ~/.ssh/config alone', () => {
	assert.equal(existsSync(path.join(STATE_DIR, '.credentials')), false);
	assert.equal(existsSync(path.join(HOME, '.ssh', 'config')), false);
	assert.equal(existsSync(STATE_DIR), false, 'nothing at all was written to the state dir');
});
