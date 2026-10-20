import { readFile, writeFile, chmod, mkdir, rm } from 'node:fs/promises';
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';

// Secrets live outside the code checkout so `labelvier core update` (git pull) never touches them.
export const STATE_DIR = process.env.SG_STATE_DIR || path.join(homedir(), '.config', 'labelvier', 'siteground');
export const SESSION_FILE = process.env.SG_SESSION_FILE || path.join(STATE_DIR, '.session.json');
export const ENV_FILE = path.join(STATE_DIR, '.env');

/**
 * Credentials for the automatic browser login, from the environment or STATE_DIR/.env
 * (KEY=value lines, # comments, optional quotes). All optional: whatever is missing is
 * left to the human in the browser window.
 */
export function loadLoginEnv() {
	const fromFile = {};
	if (existsSync(ENV_FILE)) {
		for (const raw of readFileSync(ENV_FILE, 'utf8').split('\n')) {
			const line = raw.trim();
			if (!line || line.startsWith('#')) continue;
			const eq = line.indexOf('=');
			if (eq === -1) continue;
			const key = line.slice(0, eq).trim();
			let value = line.slice(eq + 1).trim();
			if (/^(['"]).*\1$/.test(value)) value = value.slice(1, -1);
			fromFile[key] = value;
		}
	}
	const get = (key) => process.env[key] || fromFile[key] || null;
	return {
		email: get('SG_LOGIN_EMAIL'),
		password: get('SG_LOGIN_PASSWORD'),
		totpSecret: get('SG_TOTP_SECRET'),
	};
}

/** Write STATE_DIR/.env (chmod 600). Keys with a null/empty value are left out. */
export async function saveLoginEnv({ email, password, totpSecret }) {
	const lines = ['# Automatic login for `labelvier siteground login`. Change with `siteground setup`, remove with `logout --forget`.'];
	const add = (key, value) => value && lines.push(`${key}=${value}`);
	add('SG_LOGIN_EMAIL', email);
	add('SG_LOGIN_PASSWORD', password);
	add('SG_TOTP_SECRET', totpSecret);
	await mkdir(STATE_DIR, { recursive: true, mode: 0o700 });
	await writeFile(ENV_FILE, lines.join('\n') + '\n');
	await chmod(ENV_FILE, 0o600);
}

/**
 * Decode the payload of a JWT without verifying it.
 * Throws "Not a JWT: …" for anything that is not a three-part token with a JSON object payload.
 */
export function decodeJwt(token) {
	if (typeof token !== 'string') throw new Error(`Not a JWT: expected a string, got ${token === null ? 'null' : typeof token}`);
	const parts = token.split('.');
	if (parts.length !== 3 || parts.some((p) => !/^[A-Za-z0-9_-]+$/.test(p))) {
		throw new Error('Not a JWT: expected three base64url parts separated by dots');
	}
	let payload;
	try {
		payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
	} catch {
		throw new Error('Not a JWT: payload is not base64url-encoded JSON');
	}
	if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw new Error('Not a JWT: payload is not a JSON object');
	return payload;
}

/**
 * Session = { token, refreshToken }.
 * Source order: SG_REFRESH_TOKEN env (for hosted/CI use) > .session.json.
 */
export async function loadSession() {
	if (process.env.SG_REFRESH_TOKEN) {
		return { token: process.env.SG_TOKEN || null, refreshToken: process.env.SG_REFRESH_TOKEN, fromEnv: true };
	}
	if (!existsSync(SESSION_FILE)) {
		throw new Error(`No session found. Run "labelvier siteground login" first (expected ${SESSION_FILE}).`);
	}
	return JSON.parse(await readFile(SESSION_FILE, 'utf8'));
}

export async function saveSession(session) {
	if (session.fromEnv) return;
	const { token, refreshToken } = session;
	await mkdir(path.dirname(SESSION_FILE), { recursive: true, mode: 0o700 });
	await writeFile(SESSION_FILE, JSON.stringify({ token, refreshToken }, null, 2));
	await chmod(SESSION_FILE, 0o600);
}

/**
 * Forget the local session: tokens and the browser profile (its "stay logged in" cookies).
 * With `forget` also the stored login credentials (.env). Returns what was removed.
 */
export async function clearSession({ forget = false } = {}) {
	const profileDir = path.join(path.dirname(SESSION_FILE), '.browser-profile');
	const targets = [SESSION_FILE, profileDir];
	if (forget) targets.push(ENV_FILE);
	const removed = [];
	for (const target of targets) {
		if (!existsSync(target)) continue;
		await rm(target, { recursive: true, force: true });
		removed.push(target);
	}
	return removed;
}

/** Seconds until the given JWT expires (negative when expired). */
export function secondsLeft(token) {
	if (!token) return -1;
	return decodeJwt(token).exp - Math.floor(Date.now() / 1000);
}
