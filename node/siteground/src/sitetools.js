import { decodeJwt } from './session.js';

export class SiteToolsError extends Error {
	constructor(status, body, url) {
		const msg = body?.message || body?.err_message || JSON.stringify(body)?.slice(0, 300);
		super(`${status} ${url}: ${typeof msg === 'string' ? msg : JSON.stringify(msg)}`);
		this.status = status;
		this.body = body;
	}
}

/**
 * Client for the per-site "Site Tools" API: https://<server>.sgvps.net/api-sgcp/v00/<endpoint>
 * Same API tools.siteground.com uses. Auth with a site token from uapi
 * (GET /auth/sites/{siteId}/token), not with the client-area token.
 *
 * Writes can return 202 + task id; those are polled on GET /task/{id}.
 */
export class SiteToolsClient {
	constructor(sg, siteId) {
		this.sg = sg;
		this.siteId = siteId;
		this.siteToken = null;
		this.apiUrl = null;
	}

	async auth() {
		const tokenValid = () => {
			if (!this.siteToken) return false;
			const { cts, vsec } = decodeJwt(this.siteToken);
			// Same rule as the SPA: renew when less than a quarter of the lifetime is left.
			return cts + vsec - Math.round(Date.now() / 1000) > vsec / 4;
		};
		if (tokenValid()) return;
		const data = await this.sg.get(`/auth/sites/${this.siteId}/token`);
		this.siteToken = data.site_token;
		this.apiUrl = decodeJwt(this.siteToken).api_url;
		if (!this.apiUrl) {
			const site = (await this.sg.get('/sites')).find((s) => s.id === this.siteId);
			this.apiUrl = site?.api_url;
		}
	}

	async request(method, endpoint, { body, params = {} } = {}, retry = true) {
		await this.auth();
		const qs = new URLSearchParams(params).toString();
		const url = `https://${this.apiUrl}/api-sgcp/v00${endpoint}${qs ? `?${qs}` : ''}`;
		const res = await fetch(url, {
			method,
			headers: {
				accept: 'application/json',
				authorization: `Bearer ${this.siteToken}`,
				...(body ? { 'content-type': 'application/json' } : {}),
			},
			body: body ? JSON.stringify(body) : undefined,
		});
		if (res.status === 401 && retry) {
			this.siteToken = null;
			return this.request(method, endpoint, { body, params }, false);
		}
		const json = await res.json().catch(() => null);
		if (res.status === 202 || json?.status === 202) return this.waitForTask(json?.task_id ?? json?.data?.task_id, json);
		if (!res.ok || json?.status >= 400) throw new SiteToolsError(json?.status || res.status, json, `${method} ${endpoint}`);
		return json;
	}

	async waitForTask(taskId, initial, { intervalMs = 3000, attempts = 100 } = {}) {
		if (!taskId) return initial;
		for (let i = 0; i < attempts; i++) {
			await new Promise((r) => setTimeout(r, intervalMs));
			const { data: task } = await this.request('GET', `/task/${taskId}`);
			if (task?.options?.completed === 0) continue;
			if (task?.response && parseInt(task.response.err_code, 10) !== 0) {
				throw new SiteToolsError(task.response.err_code, task.response, `task ${taskId}`);
			}
			return task;
		}
		throw new Error(`Task ${taskId} did not finish in time`);
	}

	get(endpoint, params) {
		return this.request('GET', endpoint, { params }).then((r) => r.data);
	}

	post(endpoint, body) {
		return this.request('POST', endpoint, { body });
	}

	put(endpoint, body) {
		return this.request('PUT', endpoint, { body });
	}

	del(endpoint) {
		return this.request('DELETE', endpoint);
	}

	// --- Domains -----------------------------------------------------------

	domains() {
		return this.get('/domain-all');
	}

	async mainDomain() {
		const all = await this.domains();
		return all.find((d) => d.main === 1) || all[0];
	}

	// --- Caching -----------------------------------------------------------

	async memcached() {
		return (await this.get('/uservice')).find((s) => s?.type === 'memcached') || null;
	}

	async enableMemcached() {
		if (await this.memcached()) return { alreadyEnabled: true };
		return this.post('/uservice', { type: 'memcached', settings: {} });
	}

	// --- PHP ---------------------------------------------------------------

	/** Available versions: [{ id: 83, version: 'PHP 8.3.35', default?, recommended?, mod_php }]. */
	phpVersions() {
		return this.get('/php-version');
	}

	/** The "apache" uservice: present when the site runs Ultrafast PHP (mod_php), else null. */
	async apacheService() {
		return (await this.get('/uservice')).find((s) => s?.type === 'apache') || null;
	}

	/**
	 * Current PHP version id of the main domain; null = "managed" (SiteGround picks and upgrades it).
	 * Ultrafast PHP keeps it in the apache uservice settings; standard PHP on the main domain (GET /domain).
	 */
	async phpVersion() {
		const apache = await this.apacheService();
		if (apache) return apache.settings?.php_version ?? null;
		const domains = await this.get('/domain');
		const main = domains.find((d) => d.main === 1) || domains.find((d) => d.domain_type === 'main_domain');
		return main?.php_version || null;
	}

	/**
	 * versionId: e.g. 83, or null for managed. We always want Ultrafast PHP: a site on standard PHP is
	 * switched first (POST /uservice {type: "apache"}, the "PHP Setup" switch in Site Tools), then the
	 * version goes into the apache uservice settings (empty settings = managed).
	 */
	async setPhpVersion(versionId) {
		let apache = await this.apacheService();
		if (!apache) {
			await this.post('/uservice', { type: 'apache' });
			apache = await this.apacheService();
			if (!apache) throw new Error('Switching to Ultrafast PHP failed: no apache uservice after creating it');
		}
		return this.put(`/uservice/${apache.id}`, { settings: versionId ? { php_version: versionId } : {} });
	}

	// --- SSL ---------------------------------------------------------------

	certificates() {
		return this.get('/ssl');
	}

	/**
	 * Install a Let's Encrypt certificate (covers domain + www). The UI form has a "generate"
	 * field (0 = normal, 1 = wildcard) but the API rejects it as "Unsupported input field".
	 */
	installLetsEncrypt(domainId) {
		return this.post('/ssl-le', { domain_id: domainId });
	}

	enforceHttps(domain, enabled = true) {
		return this.put(`/domain-all/${domain.id}`, {
			settings: { https_enforce: enabled ? 1 : 0, https_rewrite_links: domain.settings?.https_rewrite_links ?? 0 },
		});
	}

	// --- SSH ---------------------------------------------------------------

	/** Installed (authorized) public keys. */
	sshKeys() {
		return this.get('/ssh');
	}

	/** Authorize an existing public key (contents of e.g. ~/.ssh/id_ed25519.pub). */
	importSshKey(keyPub, comment) {
		return this.post('/ssh', { key_pub: keyPub.trim(), comment });
	}

	/** Let SiteGround generate a key pair; the private key is protected with `password`. */
	generateSshKey(comment, password) {
		return this.post('/ssh-key', { comment, password });
	}

	/** SSH login details: host = server, port 18765, username from the site. */
	sshCredentials() {
		return this.get('/ssh-key').catch(() => null);
	}

	// --- MySQL -------------------------------------------------------------

	databases() {
		return this.get('/db-mysql_db');
	}

	dbUsers() {
		return this.get('/db-mysql_user');
	}

	dbGrants() {
		return this.get('/db-mysql_grant');
	}

	/** SiteGround generates the real database name (<prefix>_<random>); label is the human name. */
	createDatabase(label) {
		return this.post('/db-mysql_db', { label });
	}

	createDbUser(label, password) {
		return this.post('/db-mysql_user', { label, password });
	}

	grantAll(dbId, dbUserId) {
		return this.post('/db-mysql_grant', { db_id: dbId, dbuser_id: dbUserId, grants: { all: 1 } });
	}

	// --- WordPress ---------------------------------------------------------

	/** Installed apps: [{ id, app: 'wordpress'|'woocommerce', app_url, admin_url, path, is_staging, … }]. */
	wordpressApps() {
		return this.get('/wordpress');
	}

	/**
	 * One-time link that logs in to wp-admin (wp_auto_login_<hash>.php on the site). Same call as
	 * "Log in to admin panel" in Site Tools. Treat the link as a secret: it is a login.
	 */
	async wpAutoLoginUrl(appId) {
		const { data } = await this.request('PUT', `/wordpress/${appId}`, { body: {}, params: { auto_login: 1 } });
		if (!data?.autologin_url) throw new Error(`No auto-login link returned for WordPress install ${appId}`);
		return data.autologin_url;
	}

	// --- Cron --------------------------------------------------------------

	/** Cron jobs: [{ id, cmd, min, hour, day, mon, dow }]. */
	cronJobs() {
		return this.get('/cron');
	}

	/**
	 * Add a cron job. schedule = { min, hour, day, mon, dow } as strings (crontab fields).
	 * Like the UI, day-of-week 7 (Sunday) is sent as 0.
	 */
	createCronJob(cmd, schedule) {
		return this.post('/cron', { cmd, ...cronFields(schedule) });
	}

	updateCronJob(id, cmd, schedule) {
		return this.put(`/cron/${id}`, { cmd, ...cronFields(schedule) });
	}

	deleteCronJob(id) {
		return this.del(`/cron/${id}`);
	}
}

function cronFields({ min, hour, day, mon, dow }) {
	return { min, hour, day, mon, dow: dow === '7' ? '0' : dow };
}
