import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { parseEnv, loadConfig, saveConfig, credentialsFromProjectEnv, DEFAULT_URL } from '../src/config.js';

const dir = mkdtempSync(path.join(tmpdir(), 'kuma-test-'));

test('parseEnv handles comments, quotes, export and CRLF without expanding', () => {
	const env = parseEnv('# c\r\nA=1\r\nexport B="two words"\nC=\'$HOME\'\nD=x # note\nbroken line\n');
	assert.deepEqual(env, { A: '1', B: 'two words', C: '$HOME', D: 'x' });
});

test('credentialsFromProjectEnv reads only the login keys from the Docker project .env', () => {
	const file = path.join(dir, 'project.env');
	writeFileSync(file, 'DB_ROOT_PASSWORD=secret\nUSERNAME=labelvier\nPASSWORD="p@ss word"\n');
	assert.deepEqual(credentialsFromProjectEnv(file), { username: 'labelvier', password: 'p@ss word', url: '' });
});

test('loadConfig: environment wins over the stored file, default URL otherwise', () => {
	const file = path.join(dir, 'state.env');
	writeFileSync(file, 'KUMA_URL=https://stored.example/\nKUMA_USERNAME=stored\nKUMA_TOKEN=t1\n');
	assert.deepEqual(loadConfig({}, file), { url: 'https://stored.example', username: 'stored', password: '', token: 't1' });
	assert.equal(loadConfig({ UPTIME_KUMA_TOKEN: 't2' }, file).token, 't2');
	assert.equal(loadConfig({}, path.join(dir, 'missing.env')).url, DEFAULT_URL);
});

test('loadConfig ignores plain USERNAME / PASSWORD from the environment', () => {
	const config = loadConfig({ USERNAME: 'mulder', PASSWORD: 'x' }, path.join(dir, 'missing.env'));
	assert.equal(config.username, '');
	assert.equal(config.password, '');
});

test('saveConfig writes a 600 file with the token and no password', async () => {
	const file = path.join(dir, 'nested', '.env');
	await saveConfig({ url: 'https://k.example', username: 'u', token: 'jwt' }, file);
	const text = readFileSync(file, 'utf8');
	assert.match(text, /^KUMA_TOKEN=jwt$/m);
	assert.doesNotMatch(text, /PASSWORD/);
	assert.equal(statSync(file).mode & 0o777, 0o600);
});
