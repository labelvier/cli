import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { loadConfig, saveConfig, credentialsFromProjectEnv, DEFAULT_URL } from '../src/config.js';

const dir = mkdtempSync(path.join(tmpdir(), 'kuma-test-'));

test('credentialsFromProjectEnv reads only the login keys from the Docker project .env', () => {
	const file = path.join(dir, 'project.env');
	writeFileSync(file, 'DB_ROOT_PASSWORD=secret\nUSERNAME=labelvier\nPASSWORD="p@ss word"\n');
	assert.deepEqual(credentialsFromProjectEnv(file), { username: 'labelvier', password: 'p@ss word', url: '' });
});

test('loadConfig: KUMA_* from the environment win over the same keys in the file', () => {
	const file = path.join(dir, 'state.env');
	writeFileSync(file, 'KUMA_URL=https://stored.example/\nKUMA_USERNAME=stored\nKUMA_TOKEN=t1\n');
	assert.deepEqual(loadConfig({}, file), { url: 'https://stored.example', username: 'stored', password: '', token: 't1' });
	assert.equal(loadConfig({ KUMA_TOKEN: 't2' }, file).token, 't2');
	assert.equal(loadConfig({}, path.join(dir, 'missing.env')).url, DEFAULT_URL);
});

test('loadConfig: password only from the environment, plain USERNAME / PASSWORD ignored', () => {
	const file = path.join(dir, 'pw.env');
	writeFileSync(file, 'KUMA_PASSWORD=from-file\n');
	assert.equal(loadConfig({}, file).password, '');
	assert.equal(loadConfig({ KUMA_PASSWORD: 'env' }, file).password, 'env');
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
