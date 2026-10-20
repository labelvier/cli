import { STATE_DIR, resetDirs, jsonResponse, tokenExpiringIn, jwt } from './helpers.js'; // first: sets HOME/SG_STATE_DIR
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { SiteGroundClient, ApiError } from '../src/client.js';
import { SiteToolsClient } from '../src/sitetools.js';

const API = 'https://uapi.siteground.com/v1';
const SESSION_FILE = path.join(STATE_DIR, '.session.json');

const freshSession = (extra = {}) => ({ token: tokenExpiringIn(3600), refreshToken: tokenExpiringIn(86400), ...extra });

/** Mock fetch with a routing table { 'METHOD /path': body | (init) => Response }. Returns the mock + calls. */
function mockApi(t, routes) {
	const calls = [];
	const fn = t.mock.method(globalThis, 'fetch', async (url, init = {}) => {
		const method = init.method || 'GET';
		const pathname = url.replace(API, '');
		calls.push({ method, path: pathname, headers: init.headers || {}, body: init.body ? JSON.parse(init.body) : undefined });
		const route = routes[`${method} ${pathname}`];
		if (route === undefined) throw new Error(`No fake route for ${method} ${pathname}`);
		return typeof route === 'function' ? route(init, calls.length) : jsonResponse({ status: 200, message: 'OK', data: route });
	});
	return { fn, calls };
}

beforeEach(resetDirs);

// --- tokens --------------------------------------------------------------------

test('token(): returns the access token without a request when it is still valid', async (t) => {
	const { calls } = mockApi(t, {});
	const sg = new SiteGroundClient(freshSession());
	assert.equal(await sg.token(), sg.session.token);
	assert.equal(calls.length, 0);
});

test('token(): refreshes when less than 120 s are left and saves the session', async (t) => {
	const newToken = tokenExpiringIn(3600, { tokenType: 'access' });
	const { calls } = mockApi(t, { 'POST /auth/refresh-client-token': { client_token: newToken } });
	const session = freshSession({ token: tokenExpiringIn(100) });
	const sg = new SiteGroundClient(session);

	assert.equal(await sg.token(), newToken);
	assert.equal(calls.length, 1);
	assert.deepEqual(calls[0].body, { refresh_token: session.refreshToken });
	assert.equal(calls[0].headers.authorization, undefined, 'refresh has no Bearer header');
	assert.equal(calls[0].headers['content-type'], 'application/json');
	assert.deepEqual(JSON.parse(readFileSync(SESSION_FILE, 'utf8')), { token: newToken, refreshToken: session.refreshToken });
});

test('token(): refreshes an expired or missing access token too', async (t) => {
	const newToken = tokenExpiringIn(3600);
	mockApi(t, { 'POST /auth/refresh-client-token': { client_token: newToken } });
	assert.equal(await new SiteGroundClient(freshSession({ token: null })).token(), newToken);
	assert.equal(await new SiteGroundClient(freshSession({ token: tokenExpiringIn(-5) })).token(), newToken);
});

test('refresh(): a session from the environment is not written to disk', async (t) => {
	mockApi(t, { 'POST /auth/refresh-client-token': { client_token: tokenExpiringIn(3600) } });
	await new SiteGroundClient(freshSession({ token: null, fromEnv: true })).token();
	assert.equal(existsSync(SESSION_FILE), false);
});

test('refresh(): throws "Refresh token expired" without a request when the refresh token is past', async (t) => {
	const { calls } = mockApi(t, {});
	const sg = new SiteGroundClient({ token: null, refreshToken: tokenExpiringIn(-1) });
	await assert.rejects(sg.token(), /^Error: Refresh token expired \(24h lifetime\)\. Run "labelvier siteground login" again\.$/);
	assert.equal(calls.length, 0);
});

test('refresh(): an answer without client_token is an ApiError', async (t) => {
	mockApi(t, { 'POST /auth/refresh-client-token': () => jsonResponse({ status: 401, message: 'expired' }, 401) });
	await assert.rejects(new SiteGroundClient(freshSession({ token: null })).refresh(), (err) => {
		assert.ok(err instanceof ApiError);
		assert.equal(err.status, 401);
		assert.equal(err.message, '401 /auth/refresh-client-token: expired');
		return true;
	});
});

// --- request -------------------------------------------------------------------

test('request(): GET sends Accept + Bearer, no body, and returns the data of the envelope', async (t) => {
	const { calls } = mockApi(t, { 'GET /sites/list': { websites: [{ id: 'S1' }] } });
	const sg = new SiteGroundClient(freshSession());
	assert.deepEqual(await sg.get('/sites/list'), { websites: [{ id: 'S1' }] });
	assert.equal(calls[0].headers.accept, 'application/json');
	assert.equal(calls[0].headers.authorization, `Bearer ${sg.session.token}`);
	assert.equal(calls[0].headers['content-type'], undefined);
	assert.equal(calls[0].body, undefined);
});

test('request(): POST sends a JSON body with content-type', async (t) => {
	const { calls } = mockApi(t, { 'POST /x': { ok: 1 } });
	await new SiteGroundClient(freshSession()).post('/x', { a: 1 });
	assert.equal(calls[0].headers['content-type'], 'application/json');
	assert.deepEqual(calls[0].body, { a: 1 });
});

test('request(): non-2xx becomes an ApiError with status, path and message', async (t) => {
	mockApi(t, { 'GET /nope': () => jsonResponse({ status: 404, message: 'Not found' }, 404) });
	await assert.rejects(new SiteGroundClient(freshSession()).get('/nope'), (err) => {
		assert.ok(err instanceof ApiError);
		assert.equal(err.status, 404);
		assert.equal(err.message, '404 /nope: Not found');
		assert.deepEqual(err.body, { status: 404, message: 'Not found' });
		return true;
	});
});

test('request(): an envelope status >= 400 inside a 200 response is an error; message.intl_id is used', async (t) => {
	mockApi(t, { 'GET /domain/checkexisting/A/x': () => jsonResponse({ status: 400, message: { intl_id: 'validation.domain', text: 'Invalid' } }, 200) });
	await assert.rejects(new SiteGroundClient(freshSession()).get('/domain/checkexisting/A/x'), /^Error: 200 \/domain\/checkexisting\/A\/x: validation\.domain$/);
});

test('request(): a body that is not JSON still gives an ApiError', async (t) => {
	mockApi(t, { 'GET /html': () => new Response('<html>', { status: 502 }) });
	await assert.rejects(new SiteGroundClient(freshSession()).get('/html'), (err) => {
		assert.equal(err.status, 502);
		assert.equal(err.body, null);
		return true;
	});
});

test('request(): a 401 triggers one refresh and a retry, a second 401 is thrown', async (t) => {
	const newToken = tokenExpiringIn(3600);
	let hits = 0;
	const { calls } = mockApi(t, {
		'POST /auth/refresh-client-token': { client_token: newToken },
		'GET /accounts?sort_field=created&sort_order=DESC': () => (++hits === 1 ? jsonResponse({ status: 401 }, 401) : jsonResponse({ status: 200, data: { accounts: [] } })),
	});
	const sg = new SiteGroundClient(freshSession());
	assert.deepEqual(await sg.accounts(), []);
	assert.deepEqual(calls.map((c) => `${c.method} ${c.path}`), [
		'GET /accounts?sort_field=created&sort_order=DESC',
		'POST /auth/refresh-client-token',
		'GET /accounts?sort_field=created&sort_order=DESC',
	]);
	assert.equal(calls[2].headers.authorization, `Bearer ${newToken}`);

	mockApi(t, { 'POST /auth/refresh-client-token': { client_token: newToken }, 'GET /always401': () => jsonResponse({ status: 401 }, 401) });
	await assert.rejects(sg.get('/always401'), (err) => err.status === 401);
});

// --- fromSavedSession ----------------------------------------------------------------

test('fromSavedSession() reads .session.json, or throws without one', async () => {
	await assert.rejects(SiteGroundClient.fromSavedSession(), /No session found/);
	mkdirSync(STATE_DIR, { recursive: true });
	writeFileSync(SESSION_FILE, JSON.stringify({ token: 't', refreshToken: 'r' }));
	const sg = await SiteGroundClient.fromSavedSession();
	assert.ok(sg instanceof SiteGroundClient);
	assert.deepEqual(sg.session, { token: 't', refreshToken: 'r' });
});

// --- domain helpers --------------------------------------------------------------------

const ACCOUNTS = [
	{ id: 'TFFEeVkzOEZJQT09', name: 'Develop - Hamerkop' },
	{ id: 'TFE3L1oza01JUT09', name: 'Basis - Albatros' },
	{ id: 'TFFIK1lua0tKUT09', name: 'Basis - Aalscholver' },
];

test('findAccount(): by id, by partial case-insensitive name; ambiguous or unknown throws with the list', async (t) => {
	mockApi(t, { 'GET /accounts?sort_field=created&sort_order=DESC': { accounts: ACCOUNTS } });
	const sg = new SiteGroundClient(freshSession());
	assert.equal((await sg.findAccount('hamerkop')).id, 'TFFEeVkzOEZJQT09');
	assert.equal((await sg.findAccount('TFE3L1oza01JUT09')).name, 'Basis - Albatros');
	await assert.rejects(sg.findAccount('Basis'), (err) => {
		assert.match(err.message, /^Account "Basis" matched 2 accounts\. Available:/);
		assert.ok(err.message.includes('TFFEeVkzOEZJQT09  Develop - Hamerkop'));
		return true;
	});
	await assert.rejects(sg.findAccount('Zeearend'), /matched 0 accounts/);
});

test('sites(), autoscaleSettings(), autoscaleLogs(), orderStatus(), checkExistingDomain() hit the documented paths', async (t) => {
	const { calls } = mockApi(t, {
		'GET /sites/list': { websites: [{ id: 'S1' }] },
		'GET /accounts/A1/autoscalesettings': { autoscale_settings: { cpu: { current_value: 2 } } },
		'GET /accounts/A1/autoscalelogs': [{ type: 'autoscale_cpu' }],
		'GET /order/O1/status': { order_item_activations: [] },
		'GET /domain/checkexisting/A1/x.labelvier.dev': { registered: 1 },
	});
	const sg = new SiteGroundClient(freshSession());
	assert.deepEqual(await sg.sites(), [{ id: 'S1' }]);
	assert.deepEqual(await sg.autoscaleSettings('A1'), { cpu: { current_value: 2 } });
	assert.deepEqual(await sg.autoscaleLogs('A1'), [{ type: 'autoscale_cpu' }]);
	assert.deepEqual(await sg.orderStatus('O1'), { order_item_activations: [] });
	assert.deepEqual(await sg.checkExistingDomain('A1', 'x.labelvier.dev'), { registered: 1 });
	assert.equal(calls.length, 5);
	assert.ok(calls.every((c) => c.method === 'GET'));
});

test('accountStats(): builds the query, with timeZone/clientTimeZone only when given', async (t) => {
	const { calls } = mockApi(t, {
		'GET /account/A1/stats/cpu_seconds?fromDate=100&toDate=200&step=d': { points: [] },
		'GET /account/A1/stats/ram?fromDate=100&toDate=200&timeZone=Europe%2FAmsterdam&clientTimeZone=Europe%2FAmsterdam&step=m3': { points: [1] },
	});
	const sg = new SiteGroundClient(freshSession());
	assert.deepEqual(await sg.accountStats('A1', 'cpu_seconds', { from: 100, to: 200 }), { points: [] });
	assert.deepEqual(await sg.accountStats('A1', 'ram', { from: 100, to: 200, step: 'm3', timeZone: 'Europe/Amsterdam' }), { points: [1] });
	assert.equal(calls.length, 2);
});

test('installableApps(): names of the free apps only', async (t) => {
	mockApi(t, { 'GET /sites/wizard/step2/A1/w1': { other: [{ name: 'WordPress', is_paid: false }, { name: 'Pro', is_paid: true }, { name: 'Joomla', is_paid: 0 }] } });
	assert.deepEqual(await new SiteGroundClient(freshSession()).installableApps('A1'), ['WordPress', 'Joomla']);
});

test('createSite(): step3 then the wizard payload for an empty site; returns the order id', async (t) => {
	const { calls } = mockApi(t, { 'POST /sites/wizard/step3/A1': { extras: [] }, 'POST /sites/wizard': { id: 'ORDER1' } });
	const id = await new SiteGroundClient(freshSession()).createSite({ accountId: 'A1', domain: 'x.labelvier.dev' });
	assert.equal(id, 'ORDER1');
	const step1 = { account: 'A1', domain_type: 'e', domains: [{ domain: 'x.labelvier.dev', is_primary: 1 }], datacenter: '', site: '' };
	assert.deepEqual(calls.map((c) => `${c.method} ${c.path}`), ['POST /sites/wizard/step3/A1', 'POST /sites/wizard']);
	assert.deepEqual(calls[0].body, { order: { step1, step2: {} } });
	assert.deepEqual(calls[1].body, { order: { step1, step2: {}, step3: { extras: {} } } });
});

test('createSite(): an app goes into step2 as a new installation', async (t) => {
	const { calls } = mockApi(t, { 'POST /sites/wizard/step3/A1': {}, 'POST /sites/wizard': { id: 'O2' } });
	await new SiteGroundClient(freshSession()).createSite({ accountId: 'A1', domain: 'x.labelvier.dev', app: { name: 'WordPress', email: 'a@b.nl', password: 'pw', ignored: true } });
	const step2 = { installation_type: 'n', installation_candidate: { name: 'WordPress', email: 'a@b.nl', password: 'pw' } };
	assert.deepEqual(calls[0].body.order.step2, step2);
	assert.deepEqual(calls[1].body.order.step2, step2);
	assert.equal(calls[1].body.order.step1.domain_type, 'e', 'never a paid domain registration');
});

test('siteTools() returns a SiteToolsClient bound to this client and site', () => {
	const sg = new SiteGroundClient(freshSession());
	const st = sg.siteTools('S1');
	assert.ok(st instanceof SiteToolsClient);
	assert.equal(st.sg, sg);
	assert.equal(st.siteId, 'S1');
});

// --- waitForOrder --------------------------------------------------------------------

function orderSequence(t, statuses) {
	let i = 0;
	return mockApi(t, {
		'GET /order/O1/status': () => jsonResponse({ status: 200, data: { order_item_activations: statuses[Math.min(i++, statuses.length - 1)] } }),
	});
}

test('waitForOrder(): polls until every activation is 100 and reports each tick', async (t) => {
	const { calls } = orderSequence(t, [
		[{ product_name: 'site_activation', status: 0 }],
		[{ product_name: 'site_activation', status: 1 }, { product_name: 'cms_install', status: 0 }],
		[{ product_name: 'site_activation', status: 100 }, { product_name: 'cms_install', status: 100 }],
	]);
	const ticks = [];
	const result = await new SiteGroundClient(freshSession()).waitForOrder('O1', { intervalMs: 0, onTick: (items, i) => ticks.push([items.length, i]) });
	assert.equal(result.ok, true);
	assert.equal(result.items.length, 2);
	assert.deepEqual(ticks, [[1, 1], [2, 2], [2, 3]]);
	assert.equal(calls.length, 3);
});

test('waitForOrder(): a failed activation ends the poll with ok: false', async (t) => {
	orderSequence(t, [[{ product_name: 'site_activation', status: 1 }], [{ product_name: 'site_activation', status: 100 }, { product_name: 'cms_install', status: -1 }]]);
	const result = await new SiteGroundClient(freshSession()).waitForOrder('O1', { intervalMs: 0 });
	assert.equal(result.ok, false);
	assert.equal(result.timeout, undefined);
	assert.equal(result.items[1].status, -1);
});

test('waitForOrder(): gives up after `attempts` with timeout: true; an empty item list keeps waiting', async (t) => {
	const { calls } = orderSequence(t, [[]]);
	const result = await new SiteGroundClient(freshSession()).waitForOrder('O1', { intervalMs: 0, attempts: 3 });
	assert.deepEqual(result, { ok: false, timeout: true });
	assert.equal(calls.length, 3);
});

test('ApiError: message falls back to the JSON of the body, cut at 300 characters', () => {
	const err = new ApiError(500, { weird: 'x'.repeat(400) }, '/p');
	assert.ok(err.message.startsWith('500 /p: {"weird":"xxx'));
	assert.ok(err.message.length < 320);
	assert.equal(new ApiError(500, { message: { nested: 1 } }, '/p').message, '500 /p: {"nested":1}');
	assert.equal(jwt({ a: 1 }).split('.').length, 3);
});
