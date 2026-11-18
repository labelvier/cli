import { readFileSync, existsSync } from 'node:fs';
import { writeFile, chmod, mkdir, rm } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';

export const DEFAULT_URL = 'https://status.labelvier.nl';

/** Secrets live here, never in the code checkout. */
export const STATE_DIR = process.env.KUMA_STATE_DIR || path.join(homedir(), '.config', 'labelvier', 'uptime-kuma');
export const ENV_FILE = path.join(STATE_DIR, '.env');

/** The Docker project that runs the Uptime Kuma server. Its .env holds the CLI user next to server secrets. */
export const PROJECT_ENV_FILE = path.join(homedir(), 'Sites', 'uptime-kuma', '.env');

/**
 * Parse a dotenv file: KEY=value lines, `#` comments, an optional `export ` prefix,
 * single or double quotes around the value, CRLF line endings. Nothing is expanded.
 */
export function parseEnv(text) {
	const result = {};
	for (const raw of text.split(/\r?\n/)) {
		const line = raw.trim();
		if (!line || line.startsWith('#')) continue;
		const match = line.match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
		if (!match) continue;
		let value = match[2];
		const quote = value[0];
		if ((quote === '"' || quote === "'") && value.endsWith(quote) && value.length >= 2) {
			value = value.slice(1, -1);
		} else {
			value = value.replace(/\s+#.*$/, '');
		}
		result[match[1]] = value;
	}
	return result;
}

export function readEnvFile(file) {
	if (!existsSync(file)) return {};
	return parseEnv(readFileSync(file, 'utf8'));
}

/**
 * Pick the CLI login from the Uptime Kuma Docker project's .env. That file also holds the
 * database root password and other server settings; only the two login keys are read.
 */
export function credentialsFromProjectEnv(file) {
	const env = readEnvFile(file);
	const username = env.KUMA_USERNAME || env.USERNAME || '';
	const password = env.KUMA_PASSWORD || env.PASSWORD || '';
	const url = env.KUMA_URL || '';
	return { username, password, url };
}

/**
 * Connection settings. Environment variables win over the stored file, so CI or a one-off
 * run can pass UPTIME_KUMA_URL / UPTIME_KUMA_TOKEN (or UPTIME_KUMA_USERNAME + UPTIME_KUMA_PASSWORD).
 * The plain USERNAME / PASSWORD names are never read from the environment: zsh treats
 * USERNAME as the logged-in user and silently ignores an assignment to it.
 */
export function loadConfig(env = process.env, file = ENV_FILE) {
	const stored = readEnvFile(file);
	return {
		url: (env.UPTIME_KUMA_URL || stored.KUMA_URL || DEFAULT_URL).replace(/\/+$/, ''),
		username: env.UPTIME_KUMA_USERNAME || stored.KUMA_USERNAME || '',
		password: env.UPTIME_KUMA_PASSWORD || '',
		token: env.UPTIME_KUMA_TOKEN || stored.KUMA_TOKEN || '',
	};
}

/** Write the state file (chmod 600). Only url, username and the login token: never the password. */
export async function saveConfig({ url, username, token }, file = ENV_FILE) {
	await mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
	const lines = [
		'# Written by `labelvier uptime-kuma login`. The token replaces the password; a password change invalidates it.',
		`KUMA_URL=${url}`,
		`KUMA_USERNAME=${username}`,
		`KUMA_TOKEN=${token}`,
		'',
	];
	await writeFile(file, lines.join('\n'), { mode: 0o600 });
	await chmod(file, 0o600);
}

export async function clearConfig(file = ENV_FILE) {
	await rm(file, { force: true });
}
