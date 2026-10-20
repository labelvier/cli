/**
 * Shared test setup. Import this FIRST in every test file: src/session.js computes
 * STATE_DIR and friends at import time, so HOME and SG_STATE_DIR must point at the
 * sandbox before any src module is evaluated (ESM evaluates imports in order).
 *
 * - One throwaway root per test process (fs.mkdtemp), removed on exit. `resetDirs()`
 *   empties HOME and STATE_DIR so every test starts clean.
 * - No network: global fetch throws unless a test mocks it (`t.mock.method(globalThis, 'fetch', …)`).
 * - DNS: `startDnsStub()` answers A queries from a local UDP server, nothing leaves the machine.
 */
import { mkdtempSync, rmSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import dgram from 'node:dgram';
import { Writable } from 'node:stream';
import dns from 'node:dns/promises';
import { syncBuiltinESMExports } from 'node:module';

export const ROOT = mkdtempSync(path.join(tmpdir(), 'sg-test-'));
export const HOME = path.join(ROOT, 'home');
export const STATE_DIR = path.join(ROOT, 'state');
export const PKG_DIR = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
export const REPO_DIR = path.resolve(PKG_DIR, '..', '..');

process.env.HOME = HOME;
process.env.SG_STATE_DIR = STATE_DIR;
process.env.NO_COLOR = '1';
for (const key of ['SG_SESSION_FILE', 'SG_REFRESH_TOKEN', 'SG_TOKEN', 'SG_DEMO', 'SG_LOGIN_EMAIL', 'SG_LOGIN_PASSWORD', 'SG_TOTP_SECRET']) {
	delete process.env[key];
}
mkdirSync(HOME, { recursive: true });
process.on('exit', () => rmSync(ROOT, { recursive: true, force: true }));

/** Empty the sandbox: HOME exists again (empty), STATE_DIR does not (src creates it). */
export function resetDirs() {
	rmSync(HOME, { recursive: true, force: true });
	rmSync(STATE_DIR, { recursive: true, force: true });
	mkdirSync(HOME, { recursive: true });
}

// --- network guard -----------------------------------------------------------

globalThis.fetch = async (url) => {
	throw new Error(`Unexpected network call in tests: fetch ${url}`);
};

/** A fetch Response with a JSON body. */
export function jsonResponse(body, status = 200) {
	return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

// --- JWTs ------------------------------------------------------------------------

const b64url = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');

/** Unsigned-looking JWT (header.payload.sig) with the given payload. */
export function jwt(payload) {
	return `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url(payload)}.sig`;
}

export const now = () => Math.floor(Date.now() / 1000);

/** Access/refresh-style token that expires in `seconds` (negative = already expired). */
export const tokenExpiringIn = (seconds, extra = {}) => jwt({ exp: now() + seconds, ...extra });

// --- output capture --------------------------------------------------------------

/** Replace stream.write with a recorder. Call restore() when done (or let t.after do it). */
export function captureStream(stream) {
	const chunks = [];
	const original = stream.write;
	stream.write = (chunk, ...rest) => {
		chunks.push(typeof chunk === 'string' ? chunk : chunk.toString());
		const cb = rest.find((r) => typeof r === 'function');
		if (cb) cb();
		return true;
	};
	return {
		text: () => chunks.join(''),
		chunks,
		restore: () => {
			stream.write = original;
		},
	};
}

/**
 * Replace process.stdout / process.stderr (the whole object, not just write) with a recording
 * stream. Replacing only `write` would swallow the test reporter, which writes through the
 * original object. Returns { stream, text, reset, restore }.
 */
export function fakeStream(name, { isTTY = true } = {}) {
	let buffer = '';
	const stream = new Writable({
		write(chunk, _enc, cb) {
			buffer += chunk.toString();
			cb();
		},
	});
	stream.isTTY = isTTY;
	stream.columns = 80;
	stream.rows = 24;
	const original = Object.getOwnPropertyDescriptor(process, name);
	Object.defineProperty(process, name, { value: stream, configurable: true, enumerable: true });
	return {
		stream,
		text: () => buffer,
		reset: () => (buffer = ''),
		restore: () => Object.defineProperty(process, name, original),
	};
}

// --- DNS stub ----------------------------------------------------------------------

/**
 * Minimal DNS server on 127.0.0.1 answering A queries from `records` ({ 'host.example': '1.2.3.4' }),
 * NXDOMAIN for anything else. Installs itself as the resolver of node:dns/promises until close().
 *
 * dns.promises.setServers() swaps in a new default Resolver; a named ESM import such as
 * `import { resolve4 } from 'node:dns/promises'` (src/actions.js) stays bound to the old one until
 * syncBuiltinESMExports() refreshes the live bindings.
 */
export async function startDnsStub(records) {
	const server = dgram.createSocket('udp4');
	server.on('message', (msg, rinfo) => {
		let off = 12;
		const labels = [];
		while (msg[off] !== 0) {
			const len = msg[off];
			labels.push(msg.subarray(off + 1, off + 1 + len).toString());
			off += len + 1;
		}
		off += 1;
		const qtype = msg.readUInt16BE(off);
		off += 4;
		const question = msg.subarray(12, off);
		const ip = records[labels.join('.')];
		const answer = ip && qtype === 1 ? Buffer.alloc(16) : Buffer.alloc(0);
		if (answer.length) {
			answer.writeUInt16BE(0xc00c, 0); // pointer to the question name
			answer.writeUInt16BE(1, 2); // A
			answer.writeUInt16BE(1, 4); // IN
			answer.writeUInt32BE(60, 6); // TTL
			answer.writeUInt16BE(4, 10);
			ip.split('.').forEach((o, i) => (answer[12 + i] = Number(o)));
		}
		const header = Buffer.alloc(12);
		msg.copy(header, 0, 0, 2);
		header.writeUInt16BE(0x8180 | (ip ? 0 : 3), 2); // response + RD + RA, rcode NXDOMAIN when unknown
		header.writeUInt16BE(1, 4);
		header.writeUInt16BE(answer.length ? 1 : 0, 6);
		server.send(Buffer.concat([header, question, answer]), rinfo.port, rinfo.address);
	});
	await new Promise((resolve) => server.bind(0, '127.0.0.1', resolve));
	const previous = dns.getServers();
	dns.setServers([`127.0.0.1:${server.address().port}`]);
	syncBuiltinESMExports();
	return {
		port: server.address().port,
		close: () =>
			new Promise((resolve) => {
				dns.setServers(previous);
				syncBuiltinESMExports();
				server.close(resolve);
			}),
	};
}
