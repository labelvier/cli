/** Defaults for a new HTTP monitor: the settings our existing monitors use (5 minutes, HEAD, 3 retries). */
export const DEFAULTS = { interval: 300, timeout: 30, maxretries: 3, method: 'HEAD' };

/** Normalize a URL for a monitor: https:// when no scheme is given; only http(s) is accepted. */
export function monitorUrl(input) {
	const value = String(input || '').trim();
	if (!value) throw new Error('Usage: labelvier uptime-kuma add <url> [--name <name>]');
	let url;
	try {
		url = new URL(/^[a-z]+:\/\//i.test(value) ? value : `https://${value}`);
	} catch {
		throw new Error(`Invalid URL: ${value}`);
	}
	if (!['http:', 'https:'].includes(url.protocol)) throw new Error(`Only http(s) URLs can be monitored, got ${url.protocol}`);
	return url.pathname === '/' && !url.search && !value.endsWith('/') ? url.origin : url.href;
}

/**
 * The payload for the "add" event, as the web form sends it for an HTTP monitor.
 * The JSON-ish fields (conditions, kafka, rabbitmq) are sent empty: the server stringifies them.
 */
export function newHttpMonitor({ url, name, interval, timeout, maxretries, method, active = true, notificationIds = [] }) {
	const notificationIDList = Object.fromEntries(notificationIds.map((id) => [id, true]));
	return {
		type: 'http',
		name: name || new URL(url).hostname,
		url,
		method: method || DEFAULTS.method,
		interval: interval ?? DEFAULTS.interval,
		retryInterval: interval ?? DEFAULTS.interval,
		resendInterval: 0,
		maxretries: maxretries ?? DEFAULTS.maxretries,
		timeout: timeout ?? DEFAULTS.timeout,
		maxredirects: 10,
		accepted_statuscodes: ['200-299'],
		ignoreTls: false,
		upsideDown: false,
		expiryNotification: false,
		active,
		notificationIDList,
		conditions: [],
		kafkaProducerBrokers: [],
		kafkaProducerSaslOptions: { mechanism: 'None' },
		rabbitmqNodes: [],
	};
}
