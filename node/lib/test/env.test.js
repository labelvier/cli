import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { parseEnv, readEnvFile, writeEnvFile } from '../env.js';

const dir = mkdtempSync(path.join(tmpdir(), 'lib-env-'));

test('parseEnv: comments, blank lines, quotes, export prefix and CRLF', () => {
	const env = parseEnv('# c\r\n\r\nA = 1\r\nexport B="two words"\nC=\'$HOME\'\nNOT_A_LINE\n  # indented\n');
	assert.deepEqual(env, { A: '1', B: 'two words', C: '$HOME' });
});

test('parseEnv keeps "=", "#" and unmatched quotes inside a value', () => {
	assert.deepEqual(parseEnv("P='p=a=ss#word'\nQ=a=b=c\nR=\"half\nS=x # not a comment"), {
		P: 'p=a=ss#word',
		Q: 'a=b=c',
		R: '"half',
		S: 'x # not a comment',
	});
});

test('readEnvFile returns {} for a missing file', () => {
	assert.deepEqual(readEnvFile(path.join(dir, 'missing')), {});
});

test('writeEnvFile: header, non-empty keys only, chmod 600 in a 0700 dir', async () => {
	const file = path.join(dir, 'state', '.env');
	await writeEnvFile(file, 'Header line', { A: 'one', B: '', C: null, D: 'four' });
	assert.equal(readFileSync(file, 'utf8'), '# Header line\nA=one\nD=four\n');
	assert.equal(statSync(file).mode & 0o777, 0o600);
	assert.equal(statSync(path.dirname(file)).mode & 0o777, 0o700);
	assert.deepEqual(readEnvFile(file), { A: 'one', D: 'four' });
});
