import { loadSession, saveSession, secondsLeft } from './session.js';
import { SiteToolsClient } from './sitetools.js';

const API = 'https://uapi.siteground.com/v1';
// Site Tools sends a few writes (parked domains) here with the same client token instead of to the server.
const ST_API = 'https://st.siteground.com/v1';

export class ApiError extends Error {
	constructor(status, body, url) {
		const msg = body?.message?.intl_id || body?.message || JSON.stringify(body).slice(0, 300);
		super(`${status} ${url}: ${typeof msg === 'string' ? msg : JSON.stringify(msg)}`);
		this.status = status;
		this.body = body;
	}
}

/**
 * Thin client for the internal SiteGround client-area API (uapi.siteground.com/v1),
 * the same API the my.siteground.com SPA uses.
 *
 * Auth: short-lived access JWT (1h) as Bearer, renewed with a refresh JWT (24h, not rotated).
 */
export class SiteGroundClient {
	constructor(session) {
		this.session = session;
	}

	static async fromSavedSession() {
		return new SiteGroundClient(await loadSession());
	}

	async refresh() {
		if (secondsLeft(this.session.refreshToken) <= 0) {
			throw new Error('Refresh token expired (24h lifetime). Run "labelvier siteground login" again.');
		}
		const res = await fetch(`${API}/auth/refresh-client-token`, {
			method: 'POST',
			headers: { accept: 'application/json', 'content-type': 'application/json' },
			body: JSON.stringify({ refresh_token: this.session.refreshToken }),
		});
		const body = await res.json().catch(() => null);
		if (!res.ok || !body?.data?.client_token) throw new ApiError(res.status, body, '/auth/refresh-client-token');
		this.session.token = body.data.client_token;
		await saveSession(this.session);
	}

	async token() {
		// Renew a bit before expiry so long-running polls don't hit a 401 halfway.
		if (secondsLeft(this.session.token) < 120) await this.refresh();
		return this.session.token;
	}

	async request(method, path, body, { retry = true, base = API } = {}) {
		const res = await fetch(`${base}${path}`, {
			method,
			headers: {
				accept: 'application/json',
				authorization: `Bearer ${await this.token()}`,
				// st.siteground.com: like Site Tools, a JSON body without content-type (fetch sends text/plain).
				...(body && base === API ? { 'content-type': 'application/json' } : {}),
			},
			body: body ? JSON.stringify(body) : undefined,
		});
		if (res.status === 401 && retry) {
			await this.refresh();
			return this.request(method, path, body, { retry: false, base });
		}
		const json = await res.json().catch(() => null);
		if (!res.ok || (json && json.status && json.status >= 400)) throw new ApiError(res.status, json, path);
		return json?.data;
	}

	get(path) {
		return this.request('GET', path);
	}

	post(path, body) {
		return this.request('POST', path, body);
	}

	// --- Domain helpers ---------------------------------------------------

	async accounts() {
		return (await this.get('/accounts?sort_field=created&sort_order=DESC')).accounts;
	}

	/** Resolve a hosting account by id or (case-insensitive, partial) name, e.g. "Hamerkop". */
	async findAccount(nameOrId) {
		const accounts = await this.accounts();
		const needle = nameOrId.toLowerCase();
		const matches = accounts.filter((a) => a.id === nameOrId || a.name.toLowerCase().includes(needle));
		if (matches.length !== 1) {
			const names = accounts.map((a) => `  ${a.id}  ${a.name}`).join('\n');
			throw new Error(`Account "${nameOrId}" matched ${matches.length} accounts. Available:\n${names}`);
		}
		return matches[0];
	}

	async sites() {
		return (await this.get('/sites/list')).websites;
	}

	/**
	 * Usage statistics of a hosting account, with a series per site in aggregated_site_stats_responses.
	 * metric: cpu_seconds | program_executions (step h/d/m), or cpu_core_usage | ram on cloud plans
	 * (these need timeZone/clientTimeZone, step m3 = 20 min). from/to in unix seconds.
	 */
	accountStats(accountId, metric, { from, to, step = 'd', timeZone } = {}) {
		const tz = timeZone ? `&timeZone=${encodeURIComponent(timeZone)}&clientTimeZone=${encodeURIComponent(timeZone)}` : '';
		return this.get(`/account/${accountId}/stats/${metric}?fromDate=${from}&toDate=${to}${tz}&step=${step}`);
	}

	/** Cloud plans: autoscale settings (cpu/mem: current_value, current_cap, current_threshold %). */
	async autoscaleSettings(accountId) {
		return (await this.get(`/accounts/${accountId}/autoscalesettings`)).autoscale_settings;
	}

	/** Cloud plans: resources added by autoscaling (type autoscale_cpu/…, units, date_added, expiration_date). */
	autoscaleLogs(accountId) {
		return this.get(`/accounts/${accountId}/autoscalelogs`);
	}

	checkExistingDomain(accountId, domain) {
		return this.get(`/domain/checkexisting/${accountId}/${encodeURIComponent(domain)}`);
	}

	orderStatus(orderId) {
		return this.get(`/order/${orderId}/status`);
	}

	/** Apps the wizard can install (name as the API expects it, e.g. "WordPress", "WooCommerce"). */
	async installableApps(accountId) {
		const data = await this.get(`/sites/wizard/step2/${accountId}/w1`);
		return data.other.filter((a) => !a.is_paid).map((a) => a.name);
	}

	/**
	 * Create a site on a hosting account with an existing domain. Mirrors the payload the wizard
	 * sends to POST /sites/wizard. Returns the order id.
	 *
	 * app: null for an empty site, or { name: 'WordPress' | 'WooCommerce' | ..., email, password }
	 * for an app installed by SiteGround (admin user = email).
	 */
	async createSite({ accountId, domain, app = null }) {
		const step1 = {
			account: accountId,
			domain_type: 'e', // e = existing domain, n = new registration (paid!), t = temporary sg-host.com domain
			domains: [{ domain, is_primary: 1 }],
			datacenter: '',
			site: '',
		};
		// installation_type: n = new install, m = migrate, wpa = WP auto-migration, pm = professional migration (paid)
		const step2 = app
			? { installation_type: 'n', installation_candidate: { name: app.name, email: app.email, password: app.password } }
			: {};
		// The wizard always fetches step3 (extras/upsells) before submitting; mimic it.
		await this.post(`/sites/wizard/step3/${accountId}`, { order: { step1, step2 } });
		const data = await this.post('/sites/wizard', {
			order: { step1, step2, step3: { extras: {} } },
		});
		return data.id;
	}

	/**
	 * Park `domain` on a site as an alias of `aliasTo` (the site's main domain). Same call the
	 * Site Tools "Parked Domains" form makes; it goes to st.siteground.com, not to the server.
	 */
	addDomainAlias(siteId, domain, aliasTo) {
		return this.request('POST', `/sites/${siteId}/domain-alias`, { domain, alias_to: aliasTo }, { base: ST_API });
	}

	siteTools(siteId) {
		return new SiteToolsClient(this, siteId);
	}

	/** Poll an order until every activation is done. Status: -1 failed, 0 pending, 1 started, 100 ok. */
	async waitForOrder(orderId, { intervalMs = 10_000, attempts = 30, onTick } = {}) {
		for (let i = 1; i <= attempts; i++) {
			await new Promise((r) => setTimeout(r, intervalMs));
			const data = await this.orderStatus(orderId);
			const items = data?.order_item_activations || [];
			onTick?.(items, i);
			if (items.length && items.every((it) => it.status === 100)) return { ok: true, items };
			if (items.length && items.every((it) => it.status === 100 || it.status === -1)) return { ok: false, items };
		}
		return { ok: false, timeout: true };
	}
}
