import { readFile, writeFile, chmod, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';

// Secrets live outside the code checkout so `labelvier core update` (git pull) never touches them.
export const STATE_DIR = process.env.SG_STATE_DIR || path.join(homedir(), '.config', 'labelvier', 'siteground');
export const SESSION_FILE = process.env.SG_SESSION_FILE || path.join(STATE_DIR, '.session.json');

/** Decode the payload of a JWT without verifying it. */
export function decodeJwt(token) {
	const [, payload] = token.split('.');
	return JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
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

/** Seconds until the given JWT expires (negative when expired). */
export function secondsLeft(token) {
	if (!token) return -1;
	return decodeJwt(token).exp - Math.floor(Date.now() / 1000);
}
