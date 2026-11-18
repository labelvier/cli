#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { existsSync } from 'node:fs';
import { KumaClient } from './client.js';
import { selectMonitors, monitorHost, normalizeDomain } from './filter.js';
import { monitorUrl, newHttpMonitor, DEFAULTS } from './monitor.js';
import { loadConfig, saveConfig, clearConfig, credentialsFromProjectEnv, ENV_FILE, PROJECT_ENV_FILE, DEFAULT_URL } from './config.js';
import { ask, askSecret, confirm, closePrompt, interactive } from '../../lib/prompt.js';

const HELP = `Usage: labelvier uptime-kuma <command> [filter] [options]

Session
  login [--url <url>] [--username <name>] [--from-env <file>]
                         Log in once and store a token (no password) in ~/.config/labelvier/uptime-kuma
  logout                 Remove the stored token
  session:status         Show the server, user and whether the token still works

Monitors
  list [filter] [--json] List monitors (all when no filter is given)
  add <url> [--name <name>] [--interval <s>] [--timeout <s>] [--retries <n>] [--method <M>] [--paused]
                         Add an HTTP monitor (defaults: ${DEFAULTS.interval}s, ${DEFAULTS.method}, ${DEFAULTS.maxretries} retries, default notifications)
  pause <filter>         Pause monitors
  resume <filter>        Resume monitors
  delete <filter>        Delete monitors (always asks, or --yes)
  update <filter> [--interval <s>] [--timeout <s>] [--retries <n>] [--retry-interval <s>] [--method <M>]
  set-interval <s> <filter>   Shortcut for update --interval
  set-timeout <s> <filter>    Shortcut for update --timeout
  set-method <M> <filter>     Shortcut for update --method (GET, HEAD, POST, …)

Filter (one of)
  --all                  Every monitor
  --domain <a.nl,b.nl>   Host is the domain or a subdomain of it (www. is ignored)
  --filter <text,…>      URL or hostname contains the text
  --id <1,2,3>           Monitor ids
  --name <regex>         Name matches (case-insensitive)
  --tag <name>           Has the tag
  --groups               Include group monitors (left out by default, except with --id)

Options
  --yes, -y              Skip the confirmation for writes
  --json                 Machine-readable output for list

Environment: KUMA_URL, KUMA_TOKEN, or KUMA_USERNAME + KUMA_PASSWORD override the stored
login (for CI). Default server: ${DEFAULT_URL}.`;

const HOW_TO_LOGIN = `The CLI logs in with the shared Uptime Kuma user of ${DEFAULT_URL}, not your own account.
Where to find it:
  - USERNAME and PASSWORD in the .env of the uptime-kuma Docker project
    (git@bitbucket.org:labelvier/uptime-kuma.git). With that checkout in ~/Sites/uptime-kuma,
    "labelvier uptime-kuma login" reads them by itself; another file: --from-env <file>.
  - No checkout: ask a colleague for the login and type it when asked.
The password is swapped for a token: only the token is stored, in ${ENV_FILE}.`;

const OPTIONS = {
	all: { type: 'boolean' },
	domain: { type: 'string' },
	filter: { type: 'string' },
	id: { type: 'string' },
	name: { type: 'string' },
	tag: { type: 'string' },
	groups: { type: 'boolean' },
	json: { type: 'boolean' },
	yes: { type: 'boolean', short: 'y' },
	interval: { type: 'string' },
	timeout: { type: 'string' },
	retries: { type: 'string' },
	'retry-interval': { type: 'string' },
	method: { type: 'string' },
	url: { type: 'string' },
	username: { type: 'string' },
	'from-env': { type: 'string' },
	paused: { type: 'boolean' },
	help: { type: 'boolean', short: 'h' },
};

const METHODS = ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'];
const FILTER_KEYS = ['all', 'domain', 'filter', 'id', 'name', 'tag'];

function hasFilter(values) {
	return FILTER_KEYS.some((k) => values[k] !== undefined);
}

function integer(value, flag, min) {
	const n = Number(value);
	if (!Number.isInteger(n) || n < min) throw new Error(`--${flag} must be a whole number of at least ${min}, got "${value}"`);
	return n;
}

/** Changes for editMonitor from the update options. Throws on invalid values or when nothing is given. */
export function buildChanges(values) {
	const changes = {};
	if (values.interval !== undefined) changes.interval = integer(values.interval, 'interval', 20);
	if (values.timeout !== undefined) changes.timeout = integer(values.timeout, 'timeout', 1);
	if (values.retries !== undefined) changes.maxretries = integer(values.retries, 'retries', 0);
	if (values['retry-interval'] !== undefined) changes.retryInterval = integer(values['retry-interval'], 'retry-interval', 20);
	if (values.method !== undefined) {
		const method = values.method.toUpperCase();
		if (!METHODS.includes(method)) throw new Error(`--method must be one of ${METHODS.join(', ')}, got "${values.method}"`);
		changes.method = method;
	}
	if (Object.keys(changes).length === 0) {
		throw new Error('Nothing to update: pass --interval, --timeout, --retries, --retry-interval or --method');
	}
	return changes;
}

/** Settings for a new monitor from the add options; defaults for what is not given. */
export function buildNewMonitor(values) {
	const url = monitorUrl(values.target);
	const settings = values.interval || values.timeout || values.retries || values.method ? buildChanges(values) : {};
	return newHttpMonitor({ url, name: values.name, ...settings, active: !values.paused });
}

/** Parse argv into { command, values }. The set-* shortcuts take their value as first positional. */
export function parseCommand(argv) {
	const { values, positionals } = parseArgs({ args: argv, options: OPTIONS, allowPositionals: true, strict: true });
	const [command, value, ...rest] = positionals;
	if (rest.length) throw new Error(`Unexpected argument: ${rest[0]}`);
	const shortcut = { 'set-interval': 'interval', 'set-timeout': 'timeout', 'set-method': 'method' }[command];
	if (shortcut) {
		if (value === undefined) throw new Error(`Usage: labelvier uptime-kuma ${command} <value> <filter>`);
		values[shortcut] = value;
		return { command: 'update', values };
	}
	if (command === 'add') return { command, values: { ...values, target: value } };
	if (value !== undefined) throw new Error(`Unexpected argument: ${value}`);
	return { command, values };
}

function row(m) {
	const status = m.active ? 'active' : 'paused';
	const target = m.url && m.url !== 'https://' ? m.url : m.hostname || '';
	return `${String(m.id).padStart(4)}  ${status.padEnd(6)}  ${String(m.interval ?? '').padStart(5)}s  ${m.type.padEnd(5)}  ${m.name}${target ? `  ${target}` : ''}`;
}

function printMonitors(monitors) {
	if (monitors.length === 0) return;
	console.log('  ID  STATUS  INTERV  TYPE   NAME  URL');
	for (const m of monitors) console.log(row(m));
}

/** True when the config holds something to log in with. */
function hasLogin(config) {
	return Boolean(config.token || (config.username && config.password));
}

/**
 * Explain how to get the login and, in a terminal, offer to log in right away.
 * Returns the fresh config, or throws with the explanation when there is no terminal or the answer is no.
 */
async function offerLogin(problem) {
	const message = `${problem}\n\n${HOW_TO_LOGIN}`;
	if (!interactive) throw new Error(`${message}\n\nRun "labelvier uptime-kuma login" in a terminal.`);
	console.log(`${message}\n`);
	if (!(await confirm('Log in now?', { defaultValue: true }))) throw new Error('Not logged in.');
	await login({ explained: true });
	return loadConfig();
}

async function connected(config) {
	if (!hasLogin(config)) config = await offerLogin(`Not logged in to ${config.url}.`);
	const client = new KumaClient(config.url);
	await client.connect();
	try {
		if (config.token) await client.loginByToken(config.token);
		else await client.login(config.username, config.password);
		return client;
	} catch (err) {
		client.close();
		if (err.code !== 'authInvalidToken' || process.env.KUMA_TOKEN) throw err;
		return connected(await offerLogin(`The stored token for ${config.url} no longer works (password changed?).`));
	}
}

async function login(values) {
	const stored = loadConfig();
	let source = '';
	let username = '';
	let password = '';
	let url = values.url || process.env.KUMA_URL || '';

	const envFile = values['from-env'] || (existsSync(PROJECT_ENV_FILE) ? PROJECT_ENV_FILE : '');
	if (process.env.KUMA_USERNAME && process.env.KUMA_PASSWORD) {
		username = process.env.KUMA_USERNAME;
		password = process.env.KUMA_PASSWORD;
		source = 'KUMA_USERNAME / KUMA_PASSWORD';
	} else if (envFile) {
		if (!existsSync(envFile)) throw new Error(`${envFile} does not exist`);
		const found = credentialsFromProjectEnv(envFile);
		if (found.username && found.password) {
			({ username, password } = found);
			url ||= found.url;
			source = envFile;
		} else if (values['from-env']) {
			throw new Error(`No USERNAME and PASSWORD in ${envFile}`);
		}
	}
	if (values.username && values.username !== username) {
		username = values.username;
		password = '';
		source = '';
	}

	url = (url || stored.url || DEFAULT_URL).replace(/\/+$/, '');
	if (!source && interactive && !values.username && !values.explained) console.log(`Log in to ${url}. ${HOW_TO_LOGIN.split('\n')[0]}`);
	if (!username) username = await ask('Uptime Kuma username', { defaultValue: stored.username || undefined, flag: '--username' });
	if (!password) password = await askSecret(`Password for ${username}`, { flag: 'a password (KUMA_PASSWORD or --from-env)' });
	if (source) console.log(`Using the login of ${username} from ${source}`);

	const client = new KumaClient(url);
	try {
		await client.connect();
		let token;
		try {
			token = await client.login(username, password);
		} catch (err) {
			if (!err.tokenRequired) throw err;
			const code = await ask('Two-factor code', { flag: 'a 2FA code (needs a terminal)' });
			token = await client.login(username, password, code);
		}
		await saveConfig({ url, username, token });
		console.log(`✔ Logged in to ${url} as ${username}. Token stored in ${ENV_FILE} (no password).`);
	} finally {
		client.close();
	}
}

async function sessionStatus() {
	const config = loadConfig();
	console.log(`Server:   ${config.url}`);
	console.log(`User:     ${config.username || '(unknown)'}`);
	console.log(`Login:    ${process.env.KUMA_TOKEN ? 'KUMA_TOKEN' : config.token ? ENV_FILE : config.password ? 'KUMA_USERNAME / KUMA_PASSWORD' : 'none'}`);
	if (!hasLogin(config)) {
		console.log(`\n${HOW_TO_LOGIN}\n\nLog in with: labelvier uptime-kuma login`);
		return 1;
	}
	const client = await connected(config);
	try {
		const monitors = Object.values(await client.monitors());
		console.log(`Version:  ${client.version || 'unknown'}`);
		console.log(`Monitors: ${monitors.length} (${monitors.filter((m) => m.active).length} active)`);
		console.log('✔ Login works');
	} finally {
		client.close();
	}
	return 0;
}

async function add(values) {
	if (values.name !== undefined && !values.name.trim()) throw new Error('--name cannot be empty');
	const monitor = buildNewMonitor({ ...values, name: values.name?.trim() });
	const client = await connected(loadConfig());
	try {
		const host = normalizeDomain(monitor.url);
		const existing = Object.values(await client.monitors()).filter((m) => m.url === monitor.url || normalizeDomain(monitorHost(m)) === host);
		if (existing.length) {
			printMonitors(existing);
			const question = `${existing.length} monitor(s) already watch ${host}. Add another one?`;
			if (!values.yes) {
				if (!interactive) throw new Error(`${question} Pass --yes to add it anyway.`);
				if (!(await confirm(question, { defaultValue: false }))) {
					console.log('Cancelled.');
					return 1;
				}
			}
		}
		monitor.notificationIDList = Object.fromEntries(client.defaultNotificationIds().map((id) => [id, true]));
		const id = await client.add(monitor);
		const notifications = Object.keys(monitor.notificationIDList).length;
		console.log(`✔ Added monitor ${id}: ${monitor.name} (${monitor.url}), every ${monitor.interval}s, ${monitor.method}, ${monitor.active ? 'active' : 'paused'}, ${notifications} default notification(s)`);
		return 0;
	} finally {
		client.close();
	}
}

const ACTIONS = {
	pause: { verb: 'Pause', done: 'Paused', run: (c, m) => c.pause(m.id), skip: (m) => !m.active && 'already paused' },
	resume: { verb: 'Resume', done: 'Resumed', run: (c, m) => c.resume(m.id), skip: (m) => m.active && 'already active' },
	delete: { verb: 'DELETE', done: 'Deleted', run: (c, m) => c.delete(m.id), always: true },
	update: { verb: 'Update', done: 'Updated', run: (c, m, changes) => c.edit(m.id, changes) },
};

async function monitorsCommand(command, values) {
	if (command === 'list' && !hasFilter(values)) values.all = true;
	if (!hasFilter(values)) throw new Error(`Choose monitors for ${command}: --all, --domain, --filter, --id, --name or --tag`);
	const changes = command === 'update' ? buildChanges(values) : null;

	const client = await connected(loadConfig());
	try {
		const { matched, describe } = selectMonitors(await client.monitors(), values);

		if (command === 'list') {
			if (values.json) {
				console.log(JSON.stringify(matched.map((m) => ({ id: m.id, name: m.name, type: m.type, active: Boolean(m.active), url: m.url, hostname: m.hostname, host: monitorHost(m), interval: m.interval, timeout: m.timeout, maxretries: m.maxretries, method: m.method, tags: (m.tags || []).map((t) => t.name) })), null, 2));
				return 0;
			}
			printMonitors(matched);
			console.log(`${matched.length} monitor(s), ${describe}`);
			return 0;
		}

		const action = ACTIONS[command];
		const todo = matched.filter((m) => !action.skip?.(m));
		for (const m of matched.filter((m) => action.skip?.(m))) console.log(`- ${m.name}: ${action.skip(m)}`);
		if (todo.length === 0) {
			console.log(`No monitors to ${command} (${describe}).`);
			return command === 'delete' ? 1 : 0;
		}

		printMonitors(todo);
		const what = changes ? ` with ${Object.entries(changes).map(([k, v]) => `${k}=${v}`).join(', ')}` : '';
		const question = `${action.verb} ${todo.length} monitor(s)${what}?${command === 'delete' ? ' This cannot be undone.' : ''}`;
		if (!values.yes) {
			if (!interactive) throw new Error(`${question} Pass --yes to confirm without a terminal.`);
			if (!(await confirm(question, { defaultValue: false }))) {
				console.log('Cancelled.');
				return 1;
			}
		}

		let failed = 0;
		for (const m of todo) {
			try {
				await action.run(client, m, changes);
				console.log(`✔ ${action.done}: ${m.name}`);
			} catch (err) {
				failed++;
				console.error(`✗ ${m.name}: ${err.message}`);
			}
		}
		console.log(`${action.done} ${todo.length - failed} of ${todo.length} monitor(s).`);
		return failed ? 1 : 0;
	} finally {
		client.close();
	}
}

export async function main(argv) {
	let parsed;
	try {
		parsed = parseCommand(argv);
	} catch (err) {
		console.error(`✗ ${err.message}`);
		return 2;
	}
	const { command, values } = parsed;
	if (!command || command === 'help' || values.help) {
		console.log(HELP);
		return command || values.help ? 0 : 1;
	}

	try {
		switch (command) {
			case 'login':
				await login(values);
				return 0;
			case 'logout':
				await clearConfig();
				console.log(`✔ Removed ${ENV_FILE}`);
				return 0;
			case 'session:status':
				return await sessionStatus();
			case 'add':
				return await add(values);
			case 'list':
			case 'pause':
			case 'resume':
			case 'delete':
			case 'update':
				return await monitorsCommand(command, values);
			default:
				console.error(`✗ Unknown command: ${command}\n`);
				console.log(HELP);
				return 1;
		}
	} catch (err) {
		console.error(`✗ ${err.message}`);
		return 1;
	} finally {
		closePrompt();
	}
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('/src/cli.js')) {
	process.exitCode = await main(process.argv.slice(2));
}
