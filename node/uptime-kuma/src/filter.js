/** Host of a monitor: the URL's hostname for http monitors, `hostname` for ping/port/dns. */
export function monitorHost(monitor) {
	if (monitor.url && /^https?:\/\//i.test(monitor.url)) {
		try {
			return new URL(monitor.url).hostname.toLowerCase();
		} catch {
			// fall through to hostname
		}
	}
	return (monitor.hostname || '').toLowerCase();
}

function list(value) {
	return String(value)
		.split(',')
		.map((v) => v.trim())
		.filter(Boolean);
}

/** Strip scheme, path and a leading www. so "https://www.example.com/" and "example.com" match the same. */
export function normalizeDomain(value) {
	let domain = value.trim().toLowerCase();
	domain = domain.replace(/^[a-z]+:\/\//, '').replace(/[/:?#].*$/, '');
	return domain.replace(/^www\./, '');
}

/**
 * Build a predicate from the filter options. Exactly one of all/domain/filter/id/name/tag is required.
 * - domain: the host equals the domain or is a subdomain of it (www.example.com matches example.com)
 * - filter: any of the patterns is a substring of the URL or hostname
 * - id: one of the ids
 * - name: case-insensitive regular expression on the name
 * - tag: has a tag with that name
 */
export function buildFilter(options) {
	const given = ['all', 'domain', 'filter', 'id', 'name', 'tag'].filter((key) => options[key] !== undefined && options[key] !== false);
	if (given.length === 0) throw new Error('Choose monitors with --all, --domain, --filter, --id, --name or --tag');
	if (given.length > 1) throw new Error(`Use one filter at a time, got --${given.join(' and --')}`);
	const [kind] = given;
	const value = options[kind];

	switch (kind) {
		case 'all':
			return { describe: 'all monitors', match: () => true };
		case 'domain': {
			const domains = list(value).map(normalizeDomain);
			return {
				describe: `domain ${domains.join(', ')}`,
				match: (m) => {
					const host = monitorHost(m);
					return Boolean(host) && domains.some((d) => host === d || host.endsWith(`.${d}`));
				},
			};
		}
		case 'filter': {
			const patterns = list(value).map((p) => p.toLowerCase());
			return {
				describe: `URL contains ${patterns.join(' or ')}`,
				match: (m) => {
					const haystack = `${m.url || ''} ${m.hostname || ''}`.toLowerCase();
					return patterns.some((p) => haystack.includes(p));
				},
			};
		}
		case 'id': {
			const ids = list(value).map((v) => {
				const n = Number(v);
				if (!Number.isInteger(n) || n <= 0) throw new Error(`Invalid monitor id: ${v}`);
				return n;
			});
			return { describe: `id ${ids.join(', ')}`, match: (m) => ids.includes(m.id) };
		}
		case 'name': {
			let regex;
			try {
				regex = new RegExp(value, 'i');
			} catch (err) {
				throw new Error(`Invalid --name pattern: ${err.message}`);
			}
			return { describe: `name matches /${value}/i`, match: (m) => regex.test(m.name || '') };
		}
		case 'tag':
			return {
				describe: `tag ${value}`,
				match: (m) => (m.tags || []).some((t) => (t.name || '').toLowerCase() === String(value).toLowerCase()),
			};
	}
}

/** Monitors matching the filter, sorted by id. Groups are left out unless asked for by id. */
export function selectMonitors(monitors, options) {
	const filter = buildFilter(options);
	const all = Object.values(monitors).sort((a, b) => a.id - b.id);
	const matched = all.filter((m) => filter.match(m) && (m.type !== 'group' || options.id !== undefined || options.groups));
	return { matched, describe: filter.describe };
}
