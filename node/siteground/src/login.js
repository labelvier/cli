import path from 'node:path';
import { saveSession, SESSION_FILE, decodeJwt } from './session.js';

/**
 * Open a real (headed) browser so a human can log in incl. 2FA / reCAPTCHA,
 * then lift the tokens the SPA stores in localStorage ("ua_session").
 */
export async function interactiveLogin({ timeoutMs = 15 * 60_000 } = {}) {
	let chromium;
	try {
		({ chromium } = await import('playwright'));
	} catch {
		throw new Error('Playwright missing. Run: npm install && npx playwright install chromium (labelvier siteground login does this for you)');
	}

	const profileDir = path.join(path.dirname(SESSION_FILE), '.browser-profile');
	const context = await chromium.launchPersistentContext(profileDir, { headless: false, viewport: null });
	const page = context.pages()[0] || (await context.newPage());
	// Tick "Stay logged in" on the login page as soon as it appears (may give a longer-lived refresh token).
	page.on('domcontentloaded', () => checkStayLoggedIn(page));
	await page.goto('https://my.siteground.com/');
	await checkStayLoggedIn(page);
	console.log('Log in within the opened browser window (waiting max %d min)…', timeoutMs / 60_000);

	const handle = await page.waitForFunction(
		() => {
			try {
				const s = JSON.parse(localStorage.getItem('ua_session') || 'null')?.session;
				return s?.refreshToken && s?.token ? { token: s.token, refreshToken: s.refreshToken } : null;
			} catch {
				return null;
			}
		},
		null,
		{ timeout: timeoutMs, polling: 1000 },
	);
	const session = await handle.jsonValue();
	await context.close();

	await saveSession(session);
	const exp = new Date(decodeJwt(session.refreshToken).exp * 1000);
	console.log(`Session saved to ${SESSION_FILE}. Valid until ${exp.toLocaleString()}.`);
}

async function checkStayLoggedIn(page) {
	try {
		if (!page.url().includes('login.siteground.com')) return;
		const box = page.getByLabel(/stay logged in/i);
		await box.waitFor({ timeout: 10_000 });
		if (!(await box.isChecked())) await box.check();
	} catch {
		// Login page layout changed or not on the login page: user can tick it by hand.
	}
}
