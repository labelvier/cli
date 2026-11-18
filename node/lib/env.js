import { readFileSync, existsSync } from 'node:fs';
import { writeFile, chmod, mkdir } from 'node:fs/promises';
import path from 'node:path';

/**
 * Parse a .env file: KEY=value lines, `#` comment lines, blank lines, an optional `export ` prefix.
 * Keys and values are trimmed; a value wrapped in matching single or double quotes loses them.
 * Nothing is expanded and nothing after the first `=` is cut, so `p=a=ss#word` stays as is.
 * Lines without `=` are skipped.
 */
export function parseEnv(text) {
	const result = {};
	for (const raw of text.split(/\r?\n/)) {
		const line = raw.trim();
		if (!line || line.startsWith('#')) continue;
		const eq = line.indexOf('=');
		if (eq === -1) continue;
		const key = line.slice(0, eq).trim().replace(/^export\s+/, '');
		let value = line.slice(eq + 1).trim();
		if (/^(['"]).*\1$/.test(value) && value.length >= 2) value = value.slice(1, -1);
		if (key) result[key] = value;
	}
	return result;
}

/** parseEnv of a file; {} when it does not exist. */
export function readEnvFile(file) {
	if (!existsSync(file)) return {};
	return parseEnv(readFileSync(file, 'utf8'));
}

/**
 * Write a secrets file: `# header`, then KEY=value for every non-empty value, in a 0700 directory
 * with chmod 600 on the file.
 */
export async function writeEnvFile(file, header, values) {
	const lines = [`# ${header}`];
	for (const [key, value] of Object.entries(values)) {
		if (value) lines.push(`${key}=${value}`);
	}
	await mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
	await writeFile(file, lines.join('\n') + '\n', { mode: 0o600 });
	await chmod(file, 0o600);
}
