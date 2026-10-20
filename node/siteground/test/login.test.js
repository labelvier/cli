import { STATE_DIR, fakeStream } from './helpers.js'; // first: sandbox + fetch guard
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { register } from 'node:module';
import { setupLogin, interactiveLogin } from '../src/login.js';

// Only the parts that need neither a browser nor a terminal. The Playwright flow itself
// (autoLogin, inspect, hydrated, settle) is not exported and drives a real page: not covered here.

test('setupLogin() without a terminal fails on the first question and stores nothing', async () => {
	const out = fakeStream('stdout', { isTTY: false });
	try {
		await assert.rejects(setupLogin(), /^Error: Missing Email \(no terminal to ask it in; pass it as option\)$/);
	} finally {
		out.restore();
	}
	assert.match(out.text(), /^Credentials for the automatic login go to .*\/state\/\.env \(chmod 600\)\.\n$/);
	assert.equal(existsSync(STATE_DIR), false);
});

test('interactiveLogin() explains how to install Playwright when it cannot be imported', async () => {
	// A resolve hook hides the installed package for this process only; no browser is started.
	register('./fixtures/no-playwright-hook.mjs', import.meta.url);
	await assert.rejects(interactiveLogin(), /^Error: Playwright missing\. Run: npm install && npx playwright install chromium \(labelvier siteground login does this for you\)$/);
	assert.equal(existsSync(STATE_DIR), false, 'no browser profile was prepared');
});
