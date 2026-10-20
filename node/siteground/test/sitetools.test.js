import { jsonResponse, jwt, now } from './helpers.js'; // first: sets HOME/SG_STATE_DIR, guards fetch
import { test, mock } from 'node:test';
import assert from 'node:assert/strict';
import { SiteToolsClient, SiteToolsError } from '../src/sitetools.js';

const API_URL = 'c1103939.sgvps.net';
const BASE = `https://${API_URL}/api-sgcp/v00`;

/** Site token as uapi hands it out: claims api_url, cts (issued at) and vsec (lifetime). */
const siteToken = ({ ageSeconds = 0, vsec = 3600, apiUrl = API_URL } = {}) => jwt({ ...(apiUrl ? { api_url: apiUrl } : {}), cts: now() - ageSeconds, vsec });

/** Fake uapi client: only `get` is used by SiteToolsClient. */
function fakeSg(responses = {}) {
	return {
		get: mock.fn(async (path) => {
			if (!(path in responses)) throw new Error(`fakeSg: no response for ${path}`);
			return responses[path];
		}),
	};
}

/** Mock fetch against the Site Tools API. routes: { 'METHOD /endpoint': data | (init, n) => Response }. */
function mockSiteTools(t, routes) {
	const calls = [];
	t.mock.method(globalThis, 'fetch', async (url, init = {}) => {
		const method = init.method || 'GET';
		assert.ok(url.startsWith(BASE), `unexpected url ${url}`);
		const endpoint = url.slice(BASE.length);
		calls.push({ method, endpoint, headers: init.headers, body: init.body ? JSON.parse(init.body) : undefined });
		const route = routes[`${method} ${endpoint}`];
		if (route === undefined) throw new Error(`No fake route for ${method} ${endpoint}`);
		return typeof route === 'function' ? route(init, calls.length) : jsonResponse({ status: 200, data: route });
	});
	return calls;
}

function client(t, routes, { token = siteToken(), sgResponses = {} } = {}) {
	const sg = fakeSg({ '/auth/sites/S1/token': { site_token: token }, ...sgResponses });
	const st = new SiteToolsClient(sg, 'S1');
	const calls = mockSiteTools(t, routes);
	return { st, sg, calls };
}

// --- auth --------------------------------------------------------------------

test('auth(): fetches the site token from uapi, takes api_url from the token, reuses it while valid', async () => {
	const token = siteToken();
	const sg = fakeSg({ '/auth/sites/S1/token': { site_token: token } });
	const st = new SiteToolsClient(sg, 'S1');
	await st.auth();
	assert.equal(st.siteToken, token);
	assert.equal(st.apiUrl, API_URL);
	await st.auth();
	assert.equal(sg.get.mock.callCount(), 1);
	assert.deepEqual(sg.get.mock.calls[0].arguments, ['/auth/sites/S1/token']);
});

test('auth(): renews the token when less than a quarter of its lifetime is left', async () => {
	const stale = siteToken({ ageSeconds: 3000, vsec: 3600 }); // 600 s left < 900
	const fresh = siteToken();
	let n = 0;
	const sg = { get: mock.fn(async () => ({ site_token: n++ === 0 ? stale : fresh })) };
	const st = new SiteToolsClient(sg, 'S1');
	await st.auth();
	assert.equal(st.siteToken, stale);
	await st.auth();
	assert.equal(st.siteToken, fresh);
	assert.equal(sg.get.mock.callCount(), 2);

	// Still over a quarter left: kept.
	const st2 = new SiteToolsClient(fakeSg({ '/auth/sites/S1/token': { site_token: siteToken({ ageSeconds: 2600, vsec: 3600 }) } }), 'S1');
	await st2.auth();
	await st2.auth();
	assert.equal(st2.sg.get.mock.callCount(), 1);
});

test('auth(): falls back to GET /sites for api_url when the token has none', async () => {
	const sg = fakeSg({
		'/auth/sites/S1/token': { site_token: siteToken({ apiUrl: null }) },
		'/sites': [{ id: 'S0', api_url: 'other.sgvps.net' }, { id: 'S1', api_url: 'fallback.sgvps.net' }],
	});
	const st = new SiteToolsClient(sg, 'S1');
	await st.auth();
	assert.equal(st.apiUrl, 'fallback.sgvps.net');
	assert.deepEqual(sg.get.mock.calls.map((c) => c.arguments[0]), ['/auth/sites/S1/token', '/sites']);
});

// --- request -----------------------------------------------------------------

test('request(): builds the URL with query params, sends Bearer site token and JSON body', async (t) => {
	const { st, calls } = client(t, { 'GET /domain-all?x=1&y=a+b': [{ id: 1 }], 'POST /ssh': { id: 9 } });
	assert.deepEqual(await st.get('/domain-all', { x: 1, y: 'a b' }), [{ id: 1 }]);
	assert.equal(calls[0].headers.accept, 'application/json');
	assert.equal(calls[0].headers.authorization, `Bearer ${st.siteToken}`);
	assert.equal(calls[0].headers['content-type'], undefined);

	const res = await st.post('/ssh', { key_pub: 'k' });
	assert.deepEqual(res, { status: 200, data: { id: 9 } }, 'post returns the whole envelope');
	assert.equal(calls[1].headers['content-type'], 'application/json');
	assert.deepEqual(calls[1].body, { key_pub: 'k' });
});

test('request(): a 401 drops the site token, re-authenticates and retries once', async (t) => {
	let n = 0;
	let always401 = false;
	const { st, sg, calls } = client(t, { 'GET /ssl': () => (++n === 1 || always401 ? jsonResponse({ status: 401 }, 401) : jsonResponse({ status: 200, data: [] })) });
	assert.deepEqual(await st.certificates(), []);
	assert.equal(calls.length, 2);
	assert.equal(sg.get.mock.callCount(), 2, 'token fetched again after the 401');

	always401 = true;
	await assert.rejects(st.certificates(), (err) => err instanceof SiteToolsError && err.status === 401);
});

test('request(): errors carry status, "METHOD /endpoint" and the message or err_message', async (t) => {
	const { st } = client(t, {
		'GET /a': () => jsonResponse({ status: 400, message: 'Unsupported input field' }, 400),
		'GET /b': () => jsonResponse({ status: 500, err_message: 'boom' }, 200),
		'GET /c': () => new Response('nope', { status: 503 }),
	});
	await assert.rejects(st.get('/a'), (err) => {
		assert.ok(err instanceof SiteToolsError);
		assert.equal(err.status, 400);
		assert.equal(err.message, '400 GET /a: Unsupported input field');
		return true;
	});
	await assert.rejects(st.get('/b'), /^Error: 500 GET \/b: boom$/, 'envelope status wins over HTTP 200');
	await assert.rejects(st.get('/c'), (err) => err.status === 503 && err.body === null);
});

test('request(): a 202 hands the task id to waitForTask', async (t) => {
	const { st, calls } = client(t, { 'POST /ssl-le': () => jsonResponse({ status: 202, task_id: 'T1' }, 202), 'GET /uservice': [], 'POST /uservice': { task_id: 'T2' } });
	const waited = [];
	st.waitForTask = async (id, initial) => {
		waited.push([id, initial]);
		return { done: id };
	};
	assert.deepEqual(await st.installLetsEncrypt(1), { done: 'T1' });
	assert.deepEqual(waited[0], ['T1', { status: 202, task_id: 'T1' }]);
	// A 200 with a task_id is returned as is (only 202 polls).
	assert.deepEqual(await st.enableMemcached(), { status: 200, data: { task_id: 'T2' } });
	assert.equal(waited.length, 1);
	assert.deepEqual(calls.at(-1).body, { type: 'memcached', settings: {} });
});

test('waitForTask(): polls /task/{id} until completed, throws on err_code != 0, times out', async (t) => {
	let n = 0;
	const { st, calls } = client(t, {
		'GET /task/T1': () => jsonResponse({ status: 200, data: ++n < 3 ? { options: { completed: 0 } } : { options: { completed: 1 }, response: { err_code: '0' } } }),
		'GET /task/T2': () => jsonResponse({ status: 200, data: { options: { completed: 1 }, response: { err_code: 17, err_message: 'exists' } } }),
		'GET /task/T3': () => jsonResponse({ status: 200, data: { options: { completed: 0 } } }),
	});
	const task = await st.waitForTask('T1', null, { intervalMs: 0 });
	assert.deepEqual(task, { options: { completed: 1 }, response: { err_code: '0' } });
	assert.equal(calls.filter((c) => c.endpoint === '/task/T1').length, 3);

	await assert.rejects(st.waitForTask('T2', null, { intervalMs: 0 }), /^Error: 17 task T2: exists$/);
	await assert.rejects(st.waitForTask('T3', null, { intervalMs: 0, attempts: 2 }), /^Error: Task T3 did not finish in time$/);
	assert.deepEqual(await st.waitForTask(undefined, { initial: true }), { initial: true }, 'no task id: initial response');
});

test('enableMemcached() on an already enabled service makes no write', async (t) => {
	const { st, calls } = client(t, { 'GET /uservice': [{ id: 3, type: 'apache' }, { id: 4, type: 'memcached' }] });
	assert.deepEqual(await st.memcached(), { id: 4, type: 'memcached' });
	assert.deepEqual(await st.enableMemcached(), { alreadyEnabled: true });
	assert.ok(calls.every((c) => c.method === 'GET'));
	const { st: st2 } = client(t, { 'GET /uservice': [null, { type: 'apache' }] });
	assert.equal(await st2.memcached(), null);
});

// --- domains / SSL -------------------------------------------------------------

test('mainDomain(): the domain with main === 1, else the first one', async (t) => {
	const { st } = client(t, { 'GET /domain-all': [{ id: 2, name: 'www.x.nl', main: 0 }, { id: 1, name: 'x.nl', main: 1 }] });
	assert.equal((await st.mainDomain()).id, 1);
	const { st: st2 } = client(t, { 'GET /domain-all': [{ id: 7, main: 0 }] });
	assert.equal((await st2.mainDomain()).id, 7);
});

test('enforceHttps(): PUT /domain-all/{id} keeping https_rewrite_links', async (t) => {
	const { st, calls } = client(t, { 'PUT /domain-all/5': {} });
	await st.enforceHttps({ id: 5, settings: { https_rewrite_links: 1 } });
	assert.deepEqual(calls[0].body, { settings: { https_enforce: 1, https_rewrite_links: 1 } });
	await st.enforceHttps({ id: 5 }, false);
	assert.deepEqual(calls[1].body, { settings: { https_enforce: 0, https_rewrite_links: 0 } });
});

test("installLetsEncrypt(): POST /ssl-le with the domain id only (no 'generate' field)", async (t) => {
	const { st, calls } = client(t, { 'POST /ssl-le': {} });
	await st.installLetsEncrypt(1);
	assert.deepEqual(calls[0].body, { domain_id: 1 });
});

// --- PHP -------------------------------------------------------------------------

test('phpVersion() / setPhpVersion(): apache uservice settings; managed = empty settings; no apache throws', async (t) => {
	const { st, calls } = client(t, { 'GET /uservice': [{ id: 11, type: 'apache', settings: { php_version: 83 } }], 'PUT /uservice/11': {} });
	assert.equal(await st.phpVersion(), 83);
	await st.setPhpVersion(82);
	assert.deepEqual(calls.at(-1).body, { settings: { php_version: 82 } });
	await st.setPhpVersion(null);
	assert.deepEqual(calls.at(-1).body, { settings: {} });

	const { st: st2 } = client(t, { 'GET /uservice': [{ id: 11, type: 'apache', settings: {} }] });
	assert.equal(await st2.phpVersion(), null);
	const { st: st3 } = client(t, { 'GET /uservice': [] });
	await assert.rejects(st3.setPhpVersion(83), /No apache uservice found/);
});

// --- SSH / MySQL / cron payloads -----------------------------------------------------

test('SSH: importSshKey trims the key, generateSshKey and sshCredentials shapes', async (t) => {
	const { st, calls } = client(t, { 'POST /ssh': {}, 'POST /ssh-key': {}, 'GET /ssh-key': () => jsonResponse({ status: 404 }, 404) });
	await st.importSshKey('  ssh-ed25519 AAAA eric@mac \n', 'eric@mac');
	assert.deepEqual(calls[0].body, { key_pub: 'ssh-ed25519 AAAA eric@mac', comment: 'eric@mac' });
	await st.generateSshKey('c', 'pw');
	assert.deepEqual(calls[1].body, { comment: 'c', password: 'pw' });
	assert.equal(await st.sshCredentials(), null, 'errors are swallowed');
});

test('MySQL: createDatabase, createDbUser, grantAll payloads', async (t) => {
	const { st, calls } = client(t, { 'POST /db-mysql_db': { id: 1, name: 'dbabc' }, 'POST /db-mysql_user': { id: 2, name: 'uabc' }, 'POST /db-mysql_grant': {} });
	assert.deepEqual((await st.createDatabase('shop')).data, { id: 1, name: 'dbabc' });
	assert.deepEqual((await st.createDbUser('shop', 'pw')).data, { id: 2, name: 'uabc' });
	await st.grantAll(1, 2);
	assert.deepEqual(calls.map((c) => c.body), [{ label: 'shop' }, { label: 'shop', password: 'pw' }, { db_id: 1, dbuser_id: 2, grants: { all: 1 } }]);
});

test('Cron: create/update/delete payloads, day-of-week 7 is sent as 0', async (t) => {
	const { st, calls } = client(t, { 'POST /cron': {}, 'PUT /cron/4': {}, 'DELETE /cron/4': {} });
	const schedule = { min: '0', hour: '3', day: '*', mon: '*', dow: '7' };
	await st.createCronJob('php cron.php', schedule);
	assert.deepEqual(calls[0].body, { cmd: 'php cron.php', min: '0', hour: '3', day: '*', mon: '*', dow: '0' });
	await st.updateCronJob(4, 'x', { ...schedule, dow: '1' });
	assert.deepEqual(calls[1], { ...calls[1], method: 'PUT', endpoint: '/cron/4', body: { cmd: 'x', min: '0', hour: '3', day: '*', mon: '*', dow: '1' } });
	await st.deleteCronJob(4);
	assert.equal(calls[2].method, 'DELETE');
	assert.equal(calls[2].body, undefined);
});

test('get() unwraps data; the list helpers hit their resources', async (t) => {
	const routes = Object.fromEntries(['/ssl', '/ssh', '/db-mysql_db', '/db-mysql_user', '/db-mysql_grant', '/cron', '/php-version'].map((e) => [`GET ${e}`, [e]]));
	const { st, calls } = client(t, routes);
	assert.deepEqual(await st.certificates(), ['/ssl']);
	assert.deepEqual(await st.sshKeys(), ['/ssh']);
	assert.deepEqual(await st.databases(), ['/db-mysql_db']);
	assert.deepEqual(await st.dbUsers(), ['/db-mysql_user']);
	assert.deepEqual(await st.dbGrants(), ['/db-mysql_grant']);
	assert.deepEqual(await st.cronJobs(), ['/cron']);
	assert.deepEqual(await st.phpVersions(), ['/php-version']);
	assert.equal(calls.length, 7);
});
