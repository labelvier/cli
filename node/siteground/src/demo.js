/**
 * Hidden demo mode (--demo or SG_DEMO=1), for screen recordings.
 *
 * - All reads and checks really happen against SiteGround.
 * - Every write is blocked; creating a site and the Site Tools steps are simulated with
 *   realistic delays and success messages, so the demo can "create" a site that already exists.
 * - Server details are masked on stdout/stderr: IPs, sgvps.net hosts, SSH users and every
 *   account/site id seen in an API response. Plan, site and domain names stay visible.
 */
import { SiteGroundClient } from './client.js';
import { SiteToolsClient } from './sitetools.js';

export const demo = { enabled: false };

const secrets = new Set();
const SECRET_KEYS = new Set(['id', 'site_id', 'account_id', 'ip', 'location', 'api_url', 'username', 'ns1ip', 'ns2ip', 'ns1name', 'ns2name', 'ssh_host', 'ftp_host']);

const PATTERNS = [
	[/\b(?!127\.0\.0\.1\b)\d{1,3}(?:\.\d{1,3}){3}\b/g, '•••.•••.•••.•••'],
	[/\b[a-z0-9-]+\.sgvps\.net\b/gi, '••••••.sgvps.net'],
	[/\bu\d+-[a-z0-9]{6,}\b/g, 'u•••-••••••••'],
];

export function mask(text) {
	let out = text;
	for (const [real, fake] of renames) out = out.split(real).join(fake);
	for (const s of secrets) out = out.split(s).join('•'.repeat(Math.min(s.length, 10)));
	for (const [re, replacement] of PATTERNS) out = out.replace(re, replacement);
	return out;
}

/** Remember identifying values from an API response so they get masked when printed. */
function collectSecrets(value, key) {
	if (Array.isArray(value)) return value.forEach((v) => collectSecrets(v, key));
	if (value && typeof value === 'object') {
		for (const [k, v] of Object.entries(value)) collectSecrets(v, k);
		return;
	}
	// Only id-like strings: long enough, no spaces/dots/@, so plan and domain names stay readable.
	if (typeof value === 'string' && SECRET_KEYS.has(key) && value.length >= 8 && /^[A-Za-z0-9=+/_-]+$/.test(value) && !/^[a-z]+$/i.test(value)) {
		secrets.add(value);
	}
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
/** Somewhat random delay so the recording does not look scripted. */
export const pause = (ms) => sleep(ms * (0.8 + Math.random() * 0.4));

export function enableDemo() {
	demo.enabled = true;

	for (const stream of [process.stdout, process.stderr]) {
		const write = stream.write.bind(stream);
		stream.write = (chunk, ...rest) => write(typeof chunk === 'string' ? mask(chunk) : mask(chunk.toString()), ...rest);
	}

	// Reads pass through (and feed the mask list); writes are blocked unless explicitly allowed.
	const READ_ONLY_POSTS = [/^\/auth\/refresh-client-token$/, /^\/sites\/wizard\/step3\//];
	const request = SiteGroundClient.prototype.request;
	SiteGroundClient.prototype.request = async function (method, path, ...rest) {
		if (method !== 'GET' && !READ_ONLY_POSTS.some((re) => re.test(path))) {
			throw new Error(`Demo mode: blocked ${method} ${path}`);
		}
		const data = await request.call(this, method, path, ...rest);
		collectSecrets(data);
		return data;
	};

	// The domain may already be a site in demo mode; the wizard check then fails, so pretend it passed.
	const checkExistingDomain = SiteGroundClient.prototype.checkExistingDomain;
	SiteGroundClient.prototype.checkExistingDomain = async function (...args) {
		try {
			return await checkExistingDomain.apply(this, args);
		} catch {
			return { registered: 1, client_is_owner_of_domain: true };
		}
	};

	SiteGroundClient.prototype.createSite = async function ({ app } = {}) {
		this.demoApp = !!app;
		await pause(2500);
		return `DEMO${Date.now().toString(36).toUpperCase()}`;
	};

	SiteGroundClient.prototype.waitForOrder = async function (orderId, { onTick } = {}) {
		const steps = [
			[{ product_name: 'site_activation', status: 1 }],
			[{ product_name: 'site_activation', status: 100 }],
		];
		if (this.demoApp) {
			steps[1].push({ product_name: 'cms_install', status: 1 });
			steps.push([{ product_name: 'site_activation', status: 100 }, { product_name: 'cms_install', status: 1 }]);
			steps.push([{ product_name: 'site_activation', status: 100 }, { product_name: 'cms_install', status: 100 }]);
		}
		for (const [i, items] of steps.entries()) {
			// ~3s in total, whatever the number of steps.
			await pause(3000 / steps.length);
			onTick?.(items, i + 1);
		}
		return { ok: true, items: steps.at(-1) };
	};

	const stRequest = SiteToolsClient.prototype.request;
	SiteToolsClient.prototype.request = async function (method, endpoint, ...rest) {
		if (method !== 'GET') throw new Error(`Demo mode: blocked ${method} ${endpoint}`);
		const json = await stRequest.call(this, method, endpoint, ...rest);
		collectSecrets(json?.data);
		collectSecrets(this.apiUrl, 'api_url');
		return json;
	};
}

/**
 * Simulated versions of the Site Tools write actions. Same signatures and return shapes as
 * the real ones in actions.js; they wait a bit and report what a fresh site would show.
 */
export const fakeActions = {
	async enableMemcached() {
		await pause(1800);
		return 'Memcached enabled (127.0.0.1:11211)';
	},
	async setPhpVersion(label) {
		await pause(1500);
		return `PHP set to ${label}`;
	},
	async setupSsl({ domain, https }, progress, pointed) {
		if (!pointed) return { ok: false, message: `SSL skipped: ${domain} does not resolve to the server yet` };
		progress.text = `Installing Let's Encrypt certificate for ${domain}…`;
		await pause(6000);
		const parts = [`Let's Encrypt installed on ${domain} (+ www)`];
		if (https) {
			progress.text = 'Forcing HTTPS…';
			await pause(1500);
			parts.push('HTTPS forced');
		}
		return { ok: true, message: parts.join(', ') };
	},
	async addSshKey(keyFile) {
		await pause(1500);
		return 'SSH key authorized';
	},
	async addSshAlias(name) {
		await pause(800);
		return { ok: true, message: `Added alias '${name}'` };
	},
	async createDatabase(label, progress) {
		progress.text = `Creating database "${label}"…`;
		await pause(1500);
		progress.text = `Creating database user "${label}"…`;
		await pause(1200);
		progress.text = 'Granting privileges…';
		await pause(900);
		const rnd = () => Math.random().toString(36).slice(2, 12);
		return { label, name: `db${rnd()}`, user: `u${rnd()}`, password: '••••••••••••', host: 'localhost' };
	},
};

/**
 * Demo plan list: every plan gets a made-up bird name, and extra made-up plans fill it up to
 * 1 Start, 3 Basis, 2 Compleet, 2 Develop. Real plans take the first names of their type
 * (Develop - Hamerkop shows as "Develop - Reiger"); extras borrow the data of a real plan of the
 * same type, so picking one still runs real checks. Real names are also masked in any output.
 */
const DEMO_PLANS = {
	Start: ['Roodborst'],
	Basis: ['Grutto', 'Tureluur', 'Kievit'],
	Compleet: ['Lepelaar', 'Ooievaar'],
	Develop: ['Reiger', 'Kraanvogel'],
};
const renames = new Map();

export function withDemoPlans(accounts) {
	const result = [];
	for (const [type, names] of Object.entries(DEMO_PLANS)) {
		const real = accounts.filter((a) => a.name.startsWith(`${type} - `)).sort((a, b) => a.name.localeCompare(b.name));
		const base = real[0] || accounts.find((a) => a.name.startsWith('Develop - ')) || accounts[0];
		names.forEach((bird, i) => {
			const name = `${type} - ${bird}`;
			if (real[i]) renames.set(real[i].name, name);
			result.push(real[i] ? { ...real[i], name } : { ...base, name, demoExtra: true });
		});
	}
	const order = Object.keys(DEMO_PLANS);
	const type = (a) => order.indexOf(a.name.split(' - ')[0]);
	return result.sort((a, b) => type(a) - type(b) || a.name.localeCompare(b.name));
}
