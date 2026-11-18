import { rm } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';
import { readEnvFile, writeEnvFile } from '../../lib/env.js';

export const DEFAULT_URL = 'https://status.labelvier.nl';

// Secrets live outside the code checkout so `labelvier core update` (git pull) never touches them.
export const STATE_DIR = process.env.KUMA_STATE_DIR || path.join(homedir(), '.config', 'labelvier', 'uptime-kuma');
export const ENV_FILE = path.join(STATE_DIR, '.env');

/** The Docker project that runs the Uptime Kuma server. Its .env holds the CLI user next to server secrets. */
export const PROJECT_ENV_FILE = path.join(homedir(), 'Sites', 'uptime-kuma', '.env');

/**
 * Pick the CLI login from the Uptime Kuma Docker project's .env. That file also holds the
 * database root password and other server settings; only the login keys are read.
 */
export function credentialsFromProjectEnv(file) {
	const env = readEnvFile(file);
	return {
		username: env.KUMA_USERNAME || env.USERNAME || '',
		password: env.KUMA_PASSWORD || env.PASSWORD || '',
		url: env.KUMA_URL || '',
	};
}

/**
 * Connection settings: KUMA_URL, KUMA_USERNAME and KUMA_TOKEN from the environment or STATE_DIR/.env,
 * the environment first (same keys, like SG_LOGIN_* for siteground). KUMA_PASSWORD only comes from
 * the environment, for CI without a token: it is never stored.
 * Plain USERNAME is never read from the environment: zsh treats it as the logged-in user.
 */
export function loadConfig(env = process.env, file = ENV_FILE) {
	const stored = readEnvFile(file);
	const get = (key) => env[key] || stored[key] || '';
	return {
		url: (get('KUMA_URL') || DEFAULT_URL).replace(/\/+$/, ''),
		username: get('KUMA_USERNAME'),
		password: env.KUMA_PASSWORD || '',
		token: get('KUMA_TOKEN'),
	};
}

/** Write STATE_DIR/.env (chmod 600): url, username and the login token, never the password. */
export async function saveConfig({ url, username, token }, file = ENV_FILE) {
	await writeEnvFile(file, 'Written by `labelvier uptime-kuma login`. The token replaces the password; a password change invalidates it.', {
		KUMA_URL: url,
		KUMA_USERNAME: username,
		KUMA_TOKEN: token,
	});
}

export async function clearConfig(file = ENV_FILE) {
	await rm(file, { force: true });
}
