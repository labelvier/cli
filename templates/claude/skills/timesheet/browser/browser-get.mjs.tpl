// GET one Timesheet API path inside a real browser session.
//
// The Timesheet host sits behind SiteGround's bot challenge (sgcaptcha). Per
// SiteGround's advice, the challenge is shown to the person running the report:
// when one appears, a browser window opens and waits until that person has
// solved it. This script never solves or skips the challenge itself. The API
// call then runs as fetch() inside that same browser session; no cookies leave
// the browser profile.
//
// Usage: node browser-get.mjs <base-url> <path-under-/api/v1>
// Env:   TIMESHEET_API_TOKEN (required), TIMESHEET_BROWSER_PROFILE (optional)
// Output: response body on stdout. Exit 0 on 2xx, 22 otherwise (like curl --fail-with-body).

import { chromium } from 'playwright';
import { homedir } from 'node:os';
import { join } from 'node:path';

const [base, path] = process.argv.slice(2);
const token = process.env.TIMESHEET_API_TOKEN;
if (!base || !path || !token) {
	console.error('Usage: TIMESHEET_API_TOKEN=... node browser-get.mjs <base-url> <path>');
	process.exit(1);
}

const profile = process.env.TIMESHEET_BROWSER_PROFILE
	|| join(homedir(), '.cache', 'labelvier-timesheet-browser');
const origin = new URL(base).origin;
const CHALLENGE_TIMEOUT_MS = 5 * 60 * 1000;

const isChallenge = (url, body = '') => url.includes('sgcaptcha') || body.includes('/.well-known/sgcaptcha/');

async function apiFetch(page) {
	return page.evaluate(async ({ url, token }) => {
		const r = await fetch(url, {
			headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
			credentials: 'same-origin',
		});
		return { status: r.status, body: await r.text() };
	}, { url: `${origin}/api/v1${path.startsWith('/') ? path : `/${path}`}`, token });
}

async function run(headless) {
	const context = await chromium.launchPersistentContext(profile, { headless });
	try {
		const page = context.pages()[0] || await context.newPage();
		// The challenge page redirects itself (meta refresh), so wait until navigation settles.
		await page.goto(`${origin}/login`, { waitUntil: 'networkidle' });

		if (isChallenge(page.url())) {
			if (headless) return null; // reopen visibly so the person can solve it
			console.error('SiteGround-controle: los de challenge op in het geopende browservenster (max 5 min)...');
			await page.waitForURL((u) => !isChallenge(u.toString()), { timeout: CHALLENGE_TIMEOUT_MS });
			await page.waitForLoadState('domcontentloaded');
		}

		const res = await apiFetch(page);
		if (isChallenge('', res.body)) {
			if (headless) return null;
			throw new Error('SiteGround-controle nog actief na oplossen; probeer opnieuw.');
		}
		return res;
	} finally {
		await context.close();
	}
}

try {
	const res = (await run(true)) ?? (await run(false));
	process.stdout.write(res.body);
	process.exit(res.status >= 200 && res.status < 300 ? 0 : 22);
} catch (e) {
	console.error(`Error: ${e.message}`);
	process.exit(1);
}
