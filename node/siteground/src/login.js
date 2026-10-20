import path from 'node:path';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { saveSession, saveLoginEnv, SESSION_FILE, ENV_FILE, decodeJwt, loadLoginEnv } from './session.js';
import { totp } from './totp.js';
import { confirm, ask, askSecret } from './prompt.js';

const USERNAME_SELECTOR = 'input[name="username"], input[type="email"], input[autocomplete="username"]';
const OTP_SELECTOR = 'input[autocomplete="one-time-code"], input[name*="code" i], input[name*="otp" i], input[name*="token" i], input[name*="2fa" i], input[inputmode="numeric"]';
/** Pause between the last keystroke and Enter (ms). SG_SUBMIT_DELAY overrides it. */
const SUBMIT_DELAY_MS = Number(process.env.SG_SUBMIT_DELAY || 1000);
/** Extra pause after the page is complete and idle, before touching a form (ms). SG_HYDRATE_DELAY overrides it. */
const HYDRATE_DELAY_MS = Number(process.env.SG_HYDRATE_DELAY || 1000);

const isEmail = (v) => (/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(v) ? null : 'Not a valid email address');

/**
 * `labelvier siteground setup`: store the login credentials for the automatic login in
 * STATE_DIR/.env. The TOTP secret is optional and off by default: with it, the file alone is
 * enough to log in, so keep the number of machines that hold it small.
 */
export async function setupLogin() {
	const current = loadLoginEnv();
	console.log(`Credentials for the automatic login go to ${ENV_FILE} (chmod 600).`);
	const email = await ask('Email', { defaultValue: current.email, validate: isEmail });
	const password = (await askSecret(current.password ? 'Password (Enter keeps the stored one)' : 'Password')) || current.password;
	if (!password) throw new Error('A password is needed for the automatic login.');

	let totpSecret = null;
	const withTotp = await confirm('Also store the TOTP secret, so the 2FA step is automatic too?', { defaultValue: false });
	if (withTotp) {
		const hint = current.totpSecret ? ' (Enter keeps the stored one)' : '';
		totpSecret = (await askSecret(`TOTP secret, base32 from the authenticator setup${hint}`)).replace(/\s+/g, '') || current.totpSecret;
		if (totpSecret) totp(totpSecret); // throws on invalid base32 before anything is stored
	}

	await saveLoginEnv({ email, password, totpSecret });
	console.log(`Saved. ${totpSecret ? 'Login and 2FA run automatically.' : 'Login runs automatically; you type the 2FA code yourself.'}`);
	console.log('Remove again with: labelvier siteground logout --forget');
}

/**
 * Open a real (headed) browser, fill in what SG_LOGIN_EMAIL / SG_LOGIN_PASSWORD / SG_TOTP_SECRET
 * (env or STATE_DIR/.env) provide, and lift the tokens the SPA stores in localStorage ("ua_session").
 * Anything that is missing or fails (reCAPTCHA, changed page layout) is left to the human in the window.
 */
export async function interactiveLogin({ timeoutMs = 15 * 60_000 } = {}) {
	let chromium;
	try {
		({ chromium } = await import('playwright'));
	} catch {
		throw new Error('Playwright missing. Run: npm install && npx playwright install chromium (labelvier siteground login does this for you)');
	}

	const creds = loadLoginEnv();
	const profileDir = path.join(path.dirname(SESSION_FILE), '.browser-profile');
	await disablePasswordManager(profileDir);
	const context = await chromium.launchPersistentContext(profileDir, {
		headless: false,
		viewport: null,
		args: ['--disable-save-password-bubble'],
	});
	const page = context.pages()[0] || (await context.newPage());

	// One pass over the page after every load (and every second: the login app is a SPA), see autoLogin.
	const state = { creds, loginSubmittedAt: 0, totpSubmittedAt: 0, lastSeen: '', busy: false };
	// Serialised: a load event and the interval must not inspect the same page at the same time.
	const step = async () => {
		if (state.busy) return;
		state.busy = true;
		const startedAt = Date.now();
		const watchdog = setTimeout(() => console.log('  step is taking long (>30 s), still waiting…'), 30_000);
		try {
			await autoLogin(page, state);
		} catch (err) {
			// Navigating away mid-step is normal; anything else is worth seeing.
			if (!/context was destroyed|navigation|closed/i.test(err.message)) console.log(`  step failed: ${err.message.split('\n')[0]}`);
		} finally {
			clearTimeout(watchdog);
			if (Date.now() - startedAt > 30_000) console.log(`  step took ${Math.round((Date.now() - startedAt) / 1000)} s`);
			state.busy = false;
		}
	};
	page.on('domcontentloaded', step);
	page.on('load', step);
	const timer = setInterval(step, 1500);

	if (creds.email && creds.password) {
		console.log('Logging in as %s…', creds.email);
	} else {
		console.log('Log in by hand in the browser window (automatic login: labelvier siteground setup).');
	}
	await page.goto('https://my.siteground.com/');
	console.log('Waiting for the login in the browser window (max %d min)…', timeoutMs / 60_000);

	let session;
	try {
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
		session = await handle.jsonValue();
	} finally {
		clearInterval(timer);
		await context.close().catch(() => {});
	}

	await saveSession(session);
	const exp = new Date(decodeJwt(session.refreshToken).exp * 1000);
	console.log(`Session saved to ${SESSION_FILE}. Valid until ${exp.toLocaleString()}.`);
}

/**
 * Tick "Stay logged in" by clicking its label inside the page. The checkbox itself is a hidden
 * input behind a styled label, so Playwright's check() waits 30 s for it to become visible and gives up.
 */
async function tickStayLoggedIn(page) {
	await page.evaluate(() => {
		const label = [...document.querySelectorAll('label')].find((l) => /stay logged in/i.test(l.textContent));
		if (label && label.control && !label.control.checked) label.click();
	}).catch(() => {});
}

/** Chrome's own "Save password?" bubble is noise here: turn the password manager off in the profile. */
async function disablePasswordManager(profileDir) {
	const file = path.join(profileDir, 'Default', 'Preferences');
	let prefs = {};
	try {
		prefs = JSON.parse(await readFile(file, 'utf8'));
	} catch {
		// fresh profile
	}
	prefs.credentials_enable_service = false;
	prefs.profile = { ...(prefs.profile || {}), password_manager_enabled: false };
	await mkdir(path.dirname(file), { recursive: true });
	await writeFile(file, JSON.stringify(prefs));
}

/** What the current page shows: login form, one-time-code field, "stay logged in" box. Cheap, no waiting. */
async function inspect(page) {
	const timeout = new Promise((_, reject) => setTimeout(() => reject(new Error('inspect timed out')), 5_000));
	return Promise.race([timeout, page.evaluate(() => {
		const visible = (el) => !!el && el.offsetParent !== null && !el.disabled;
		const first = (sel) => [...document.querySelectorAll(sel)].find(visible) || null;
		const username = first('input[name="username"], input[type="email"], input[autocomplete="username"]');
		const password = first('input[type="password"]');
		const otp = first('input[autocomplete="one-time-code"], input[name*="code" i], input[name*="otp" i], input[name*="token" i], input[name*="2fa" i], input[inputmode="numeric"]');
		const stay = [...document.querySelectorAll('label')].find((l) => /stay logged in/i.test(l.textContent))?.control || null;
		const describe = (el) => el && `${el.tagName.toLowerCase()}[name=${el.name || ''}][type=${el.type || ''}]`;
		return {
			url: location.href,
			login: visible(username) && visible(password),
			empty: !!username && username.value === '' && !!password && password.value === '',
			otp: !!otp && !password,
			stayChecked: stay ? stay.checked : null,
			fields: [...document.querySelectorAll('input')].filter(visible).map(describe).join(' '),
		};
	})]);
}

/**
 * Act on what the page shows right now: fill the login form once, fill the TOTP code once per
 * 30 s window. Runs on every load and every second; everything else is left to the human.
 */
async function autoLogin(page, state) {
	const { creds } = state;
	if (!creds.email || !creds.password) return;
	const seen = await inspect(page);
	const summary = `${seen.url} login=${seen.login} otp=${seen.otp} fields=${seen.fields || '-'}`;
	if (summary !== state.lastSeen) {
		state.lastSeen = summary;
		console.log(`  page: ${summary}`);
	}

	if (seen.login) {
		// One submit; a second only when the form came back empty (reload) and 30 s have passed.
		if (state.loginSubmittedAt && (Date.now() - state.loginSubmittedAt < 30_000 || !seen.empty)) return;
		await hydrated(page);
		const username = page.locator(USERNAME_SELECTOR).first();
		const password = page.locator('input[type="password"]').first();
		await username.fill(creds.email, { timeout: 5_000 });
		await password.fill(creds.password, { timeout: 5_000 });
		if (seen.stayChecked === false) await tickStayLoggedIn(page);
		await settle(page, 'input[type="password"]', creds.password);
		console.log('  filled email + password, submitting');
		await password.press('Enter', { timeout: 5_000 });
		state.loginSubmittedAt = Date.now();
		return;
	}

	if (seen.otp && creds.totpSecret) {
		const window = Math.floor(Date.now() / 30_000);
		if (state.totpSubmittedAt === window) return; // one code per 30 s window
		state.totpSubmittedAt = window;
		await hydrated(page);
		const code = totp(creds.totpSecret);
		const field = page.locator(OTP_SELECTOR).first();
		await field.fill(code, { timeout: 5_000 });
		await settle(page, OTP_SELECTOR, code);
		console.log('  filled 2FA code, submitting');
		await field.press('Enter', { timeout: 5_000 });
	}
}

/**
 * Wait until the page has finished loading and its scripts have had a moment to attach
 * (document complete + no network activity). Before that, Enter is a plain HTML form submit
 * that reloads the page with empty fields. Bounded: a page that keeps polling does not block us.
 */
async function hydrated(page) {
	await page.waitForFunction(() => document.readyState === 'complete', null, { timeout: 10_000 }).catch(() => {});
	await page.waitForLoadState('networkidle', { timeout: 8_000 }).catch(() => {});
	await page.waitForTimeout(HYDRATE_DELAY_MS);
}

/**
 * The login app is a SPA with controlled inputs: give it a moment to take the value over
 * before Enter, otherwise the form submits with what it had (nothing).
 */
async function settle(page, selector, expected) {
	const field = page.locator(selector).first();
	for (let i = 0; i < 10; i++) {
		await page.waitForTimeout(150);
		if ((await field.inputValue().catch(() => '')) === expected) break;
	}
	await page.waitForTimeout(SUBMIT_DELAY_MS);
}
