/**
 * Preload for test/cli.test.js (`node --import <this file> src/cli.js …`): replaces global fetch
 * with a canned SiteGround (uapi + Site Tools) and answers DNS from a local stub, so the CLI runs
 * without network. Every request is appended as a JSON line to $SG_TEST_FETCH_LOG; anything
 * without a canned answer throws, which the CLI reports as "Error: …" (exit 1).
 */
import { appendFileSync } from 'node:fs';
import dgram from 'node:dgram';
import dns from 'node:dns/promises';
import { syncBuiltinESMExports } from 'node:module';

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const jwt = (payload) => `${b64({ alg: 'HS256' })}.${b64(payload)}.sig`;
const now = Math.floor(Date.now() / 1000);

export const SERVER_IP = '35.214.252.94';
export const API_URL = 'c1103939.sgvps.net';

const accounts = [
	{ id: 'TFFEeVkzOEZJQT09', name: 'Develop - Hamerkop', status: 'active', can_create_sites: true, plan_description: 'GoGeek', server: { ip: SERVER_IP, location: 'Amsterdam' }, quota_info: { usage: 1 } },
	{ id: 'TFE3L1oza01JUT09', name: 'Basis - Albatros', status: 'active', can_create_sites: true, plan_description: 'GrowBig', server: { ip: '35.214.165.2', location: 'Amsterdam' }, quota_info: { usage: 1 } },
];
const websites = [
	{ id: 'SmczellITUpKZz09', domain: 'analytics.labelvier.dev', account_id: 'TFFEeVkzOEZJQT09', account_name: 'Develop - Hamerkop', cms: 'wordpress', status: 'active', server: API_URL },
	{ id: 'TXpBd05EZz09', domain: 'yoni.care', account_id: 'TFE3L1oza01JUT09', account_name: 'Basis - Albatros', cms: 'wordpress', status: 'active', server: 'c125667.sgvps.net' },
];

const uapi = {
	'GET /accounts?sort_field=created&sort_order=DESC': { accounts },
	'GET /sites/list': { websites },
	'GET /sites': websites.map((w) => ({ id: w.id, domain: w.domain, api_url: w.server })),
	'GET /account/TFFEeVkzOEZJQT09/stats/disk': { total: 10240, limit: 40960 },
	'GET /account/TFE3L1oza01JUT09/stats/disk': { total: 30720, limit: 40960 },
	'GET /domain/checkexisting/TFFEeVkzOEZJQT09/new.labelvier.dev': { registered: 1, client_is_owner_of_domain: true },
	'GET /auth/sites/SmczellITUpKZz09/token': { site_token: jwt({ api_url: API_URL, cts: now, vsec: 3600 }) },
	'POST /auth/refresh-client-token': { client_token: jwt({ exp: now + 3600, tokenType: 'access' }) },
};
const siteTools = {
	'GET /wordpress': [{ id: 3, app: 'wordpress', app_url: 'https://analytics.labelvier.dev/', path: '/' }],
	'PUT /wordpress/3?auto_login=1': { autologin_url: 'http://analytics.labelvier.dev/wp_auto_login_abc.php' },
	'GET /php-version': [{ id: 82, version: 'PHP 8.2.29', mod_php: true }, { id: 83, version: 'PHP 8.3.35', default: true, recommended: true, mod_php: true }],
};

globalThis.fetch = async (url, init = {}) => {
	const method = init.method || 'GET';
	if (process.env.SG_TEST_FETCH_LOG) appendFileSync(process.env.SG_TEST_FETCH_LOG, `${JSON.stringify({ method, url, body: init.body ? JSON.parse(init.body) : undefined })}\n`);
	let table = uapi;
	let key = `${method} ${url.replace('https://uapi.siteground.com/v1', '')}`;
	if (url.startsWith(`https://${API_URL}/api-sgcp/v00`)) {
		table = siteTools;
		key = `${method} ${url.replace(`https://${API_URL}/api-sgcp/v00`, '')}`;
	}
	if (!(key in table)) throw new Error(`fake-api: no canned answer for ${key}`);
	return new Response(JSON.stringify({ status: 200, message: 'OK', data: table[key] }), { status: 200, headers: { 'content-type': 'application/json' } });
};

// DNS: new.labelvier.dev points to the Hamerkop server, nothing else resolves.
const records = { 'new.labelvier.dev': SERVER_IP };
const server = dgram.createSocket('udp4');
server.on('message', (msg, rinfo) => {
	let off = 12;
	const labels = [];
	while (msg[off] !== 0) {
		labels.push(msg.subarray(off + 1, off + 1 + msg[off]).toString());
		off += msg[off] + 1;
	}
	off += 1;
	const qtype = msg.readUInt16BE(off);
	off += 4;
	const ip = records[labels.join('.')];
	const answer = ip && qtype === 1 ? Buffer.alloc(16) : Buffer.alloc(0);
	if (answer.length) {
		answer.writeUInt16BE(0xc00c, 0);
		answer.writeUInt16BE(1, 2);
		answer.writeUInt16BE(1, 4);
		answer.writeUInt32BE(60, 6);
		answer.writeUInt16BE(4, 10);
		ip.split('.').forEach((o, i) => (answer[12 + i] = Number(o)));
	}
	const header = Buffer.alloc(12);
	msg.copy(header, 0, 0, 2);
	header.writeUInt16BE(0x8180 | (ip ? 0 : 3), 2);
	header.writeUInt16BE(1, 4);
	header.writeUInt16BE(answer.length ? 1 : 0, 6);
	server.send(Buffer.concat([header, msg.subarray(12, off), answer]), rinfo.port, rinfo.address);
});
await new Promise((resolve) => server.bind(0, '127.0.0.1', resolve));
server.unref(); // must not keep the CLI process alive
dns.setServers([`127.0.0.1:${server.address().port}`]);
syncBuiltinESMExports();
