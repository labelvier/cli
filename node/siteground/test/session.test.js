import { STATE_DIR, resetDirs, jwt, tokenExpiringIn, now } from './helpers.js'; // first: sets HOME/SG_STATE_DIR
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import {
	STATE_DIR as SRC_STATE_DIR,
	SESSION_FILE,
	ENV_FILE,
	loadLoginEnv,
	saveLoginEnv,
	decodeJwt,
	loadSession,
	saveSession,
	clearSession,
	secondsLeft,
} from '../src/session.js';

const mode = (file) => statSync(file).mode & 0o777;
const writeEnv = (text) => {
	mkdirSync(STATE_DIR, { recursive: true });
	writeFileSync(ENV_FILE, text);
};

beforeEach(() => {
	resetDirs();
	for (const key of ['SG_LOGIN_EMAIL', 'SG_LOGIN_PASSWORD', 'SG_TOTP_SECRET', 'SG_REFRESH_TOKEN', 'SG_TOKEN']) delete process.env[key];
});

test('constants follow SG_STATE_DIR', () => {
	assert.equal(SRC_STATE_DIR, STATE_DIR);
	assert.equal(SESSION_FILE, path.join(STATE_DIR, '.session.json'));
	assert.equal(ENV_FILE, path.join(STATE_DIR, '.env'));
});

// --- loadLoginEnv --------------------------------------------------------------

test('loadLoginEnv returns nulls when there is no .env and no env vars', () => {
	assert.deepEqual(loadLoginEnv(), { email: null, password: null, totpSecret: null });
});

test('loadLoginEnv reads KEY=value lines, strips quotes, skips comments and blank lines', () => {
	writeEnv(['# a comment', '', 'SG_LOGIN_EMAIL = "eric@example.com"', "SG_LOGIN_PASSWORD='p=a=ss#word'", 'SG_TOTP_SECRET=JBSW Y3DP', 'NOT_A_LINE', '  # indented comment', ''].join('\n'));
	assert.deepEqual(loadLoginEnv(), { email: 'eric@example.com', password: 'p=a=ss#word', totpSecret: 'JBSW Y3DP' });
});

test('loadLoginEnv keeps a value with "=" inside and unmatched quotes as is', () => {
	writeEnv('SG_LOGIN_PASSWORD=a=b=c\nSG_LOGIN_EMAIL="half@quoted.nl\n');
	const env = loadLoginEnv();
	assert.equal(env.password, 'a=b=c');
	assert.equal(env.email, '"half@quoted.nl');
});

test('loadLoginEnv: environment variables win over the file', () => {
	writeEnv('SG_LOGIN_EMAIL=file@example.com\nSG_LOGIN_PASSWORD=filepass\n');
	process.env.SG_LOGIN_EMAIL = 'env@example.com';
	assert.deepEqual(loadLoginEnv(), { email: 'env@example.com', password: 'filepass', totpSecret: null });
});

// --- saveLoginEnv --------------------------------------------------------------

test('saveLoginEnv writes only non-empty keys, with a header, chmod 600 in a 0700 dir', async () => {
	assert.equal(existsSync(STATE_DIR), false);
	await saveLoginEnv({ email: 'eric@example.com', password: 'secret', totpSecret: null });
	const text = readFileSync(ENV_FILE, 'utf8');
	assert.match(text.split('\n')[0], /^# Automatic login/);
	assert.equal(text, `${text.split('\n')[0]}\nSG_LOGIN_EMAIL=eric@example.com\nSG_LOGIN_PASSWORD=secret\n`);
	assert.equal(mode(ENV_FILE), 0o600);
	assert.equal(mode(STATE_DIR), 0o700);
});

test('saveLoginEnv round-trips through loadLoginEnv and overwrites an earlier file', async () => {
	await saveLoginEnv({ email: 'a@example.com', password: 'one', totpSecret: 'JBSWY3DP' });
	await saveLoginEnv({ email: 'b@example.com', password: 'two', totpSecret: '' });
	assert.deepEqual(loadLoginEnv(), { email: 'b@example.com', password: 'two', totpSecret: null });
});

// --- decodeJwt / secondsLeft ----------------------------------------------------

test('decodeJwt returns the payload without verifying', () => {
	assert.deepEqual(decodeJwt(jwt({ exp: 123, tokenType: 'access' })), { exp: 123, tokenType: 'access' });
	assert.throws(() => decodeJwt('not-a-jwt'));
});

test('secondsLeft: -1 without a token, positive before exp, negative after', () => {
	assert.equal(secondsLeft(null), -1);
	assert.equal(secondsLeft(undefined), -1);
	const left = secondsLeft(tokenExpiringIn(600));
	assert.ok(left > 595 && left <= 600, `got ${left}`);
	assert.ok(secondsLeft(tokenExpiringIn(-10)) < 0);
	assert.equal(secondsLeft(jwt({ exp: now() })), 0);
});

// --- loadSession / saveSession ----------------------------------------------------

test('loadSession: SG_REFRESH_TOKEN wins and marks the session fromEnv', async () => {
	mkdirSync(STATE_DIR, { recursive: true });
	writeFileSync(SESSION_FILE, JSON.stringify({ token: 'file-token', refreshToken: 'file-refresh' }));
	process.env.SG_REFRESH_TOKEN = 'env-refresh';
	assert.deepEqual(await loadSession(), { token: null, refreshToken: 'env-refresh', fromEnv: true });
	process.env.SG_TOKEN = 'env-token';
	assert.equal((await loadSession()).token, 'env-token');
});

test('loadSession throws a "No session found" error naming the file', async () => {
	await assert.rejects(loadSession(), (err) => {
		assert.match(err.message, /^No session found\. Run "labelvier siteground login" first/);
		assert.ok(err.message.includes(SESSION_FILE));
		return true;
	});
});

test('loadSession reads .session.json', async () => {
	mkdirSync(STATE_DIR, { recursive: true });
	writeFileSync(SESSION_FILE, JSON.stringify({ token: 't', refreshToken: 'r' }));
	assert.deepEqual(await loadSession(), { token: 't', refreshToken: 'r' });
});

test('saveSession writes token + refreshToken only, chmod 600, creates the dir', async () => {
	await saveSession({ token: 't', refreshToken: 'r', extra: 'dropped' });
	assert.deepEqual(JSON.parse(readFileSync(SESSION_FILE, 'utf8')), { token: 't', refreshToken: 'r' });
	assert.equal(mode(SESSION_FILE), 0o600);
	assert.equal(mode(STATE_DIR), 0o700);
});

test('saveSession is a no-op for a session that came from the environment', async () => {
	await saveSession({ token: 't', refreshToken: 'r', fromEnv: true });
	assert.equal(existsSync(SESSION_FILE), false);
	assert.equal(existsSync(STATE_DIR), false);
});

// --- clearSession ------------------------------------------------------------------

function seedState({ env = true } = {}) {
	mkdirSync(path.join(STATE_DIR, '.browser-profile', 'Default'), { recursive: true });
	writeFileSync(path.join(STATE_DIR, '.browser-profile', 'Default', 'Preferences'), '{}');
	writeFileSync(SESSION_FILE, '{}');
	if (env) writeFileSync(ENV_FILE, 'SG_LOGIN_EMAIL=x@example.com\n');
}

test('clearSession removes the session and browser profile, keeps .env, returns what it removed', async () => {
	seedState();
	const removed = await clearSession();
	assert.deepEqual(removed, [SESSION_FILE, path.join(STATE_DIR, '.browser-profile')]);
	assert.equal(existsSync(SESSION_FILE), false);
	assert.equal(existsSync(path.join(STATE_DIR, '.browser-profile')), false);
	assert.equal(existsSync(ENV_FILE), true);
});

test('clearSession with forget also removes .env', async () => {
	seedState();
	const removed = await clearSession({ forget: true });
	assert.deepEqual(removed, [SESSION_FILE, path.join(STATE_DIR, '.browser-profile'), ENV_FILE]);
	assert.equal(existsSync(ENV_FILE), false);
});

test('clearSession only reports what existed; nothing stored is a no-op', async () => {
	assert.deepEqual(await clearSession({ forget: true }), []);
	mkdirSync(STATE_DIR, { recursive: true });
	writeFileSync(ENV_FILE, '');
	assert.deepEqual(await clearSession(), []);
	assert.deepEqual(await clearSession({ forget: true }), [ENV_FILE]);
});
