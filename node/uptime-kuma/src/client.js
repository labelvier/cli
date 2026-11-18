import { io } from 'socket.io-client';

const TIMEOUT_MS = 20000;

/** Error messages Uptime Kuma sends as i18n keys. */
const MESSAGES = {
	authIncorrectCreds: 'Incorrect username or password',
	authInvalidToken: 'The stored token is no longer valid (password changed?). Run "labelvier uptime-kuma login"',
	authUserInactiveOrDeleted: 'The Uptime Kuma user is inactive or deleted',
};

function message(response) {
	return MESSAGES[response?.msg] || response?.msg || 'Unknown error';
}

/**
 * Minimal client for the Socket.IO API the Uptime Kuma web app uses (tested against 2.3).
 * After a login the server pushes the full monitor list on its own; `monitors()` waits for it.
 */
export class KumaClient {
	constructor(url, { connect = io } = {}) {
		this.url = url;
		this.connectFn = connect;
		this.monitorList = null;
		this.waiters = [];
		this.version = null;
	}

	async connect() {
		this.socket = this.connectFn(this.url, { transports: ['websocket'], reconnection: false, timeout: TIMEOUT_MS });
		this.socket.on('monitorList', (list) => {
			this.monitorList = list;
			for (const resolve of this.waiters.splice(0)) resolve(list);
		});
		this.socket.on('info', (info) => {
			if (info?.version) this.version = info.version;
		});
		await new Promise((resolve, reject) => {
			const timer = setTimeout(() => reject(new Error(`No connection to ${this.url} within ${TIMEOUT_MS / 1000}s`)), TIMEOUT_MS);
			this.socket.once('connect', () => {
				clearTimeout(timer);
				resolve();
			});
			this.socket.once('connect_error', (err) => {
				clearTimeout(timer);
				reject(new Error(`Cannot connect to ${this.url}: ${err.message}`));
			});
		});
	}

	/** Emit an event and wait for the server's callback. */
	call(event, ...args) {
		return new Promise((resolve, reject) => {
			const timer = setTimeout(() => reject(new Error(`No answer to "${event}" within ${TIMEOUT_MS / 1000}s`)), TIMEOUT_MS);
			this.socket.emit(event, ...args, (response) => {
				clearTimeout(timer);
				resolve(response);
			});
		});
	}

	async callOk(event, ...args) {
		const response = await this.call(event, ...args);
		if (!response?.ok) throw new Error(`${event} failed: ${message(response)}`);
		return response;
	}

	/** Username + password (+ 2FA code). Returns the JWT to store instead of the password. */
	async login(username, password, twoFactorToken = '') {
		const response = await this.call('login', { username, password, token: twoFactorToken });
		if (response?.tokenRequired) {
			const err = new Error('Two-factor code required');
			err.tokenRequired = true;
			throw err;
		}
		if (!response?.ok) throw new Error(`Login failed: ${message(response)}`);
		return response.token;
	}

	async loginByToken(token) {
		await this.callOk('loginByToken', token);
	}

	/** Object of id -> monitor, as pushed after login. */
	monitors() {
		if (this.monitorList) return Promise.resolve(this.monitorList);
		return new Promise((resolve, reject) => {
			const timer = setTimeout(() => reject(new Error(`No monitor list within ${TIMEOUT_MS / 1000}s`)), TIMEOUT_MS);
			this.waiters.push((list) => {
				clearTimeout(timer);
				resolve(list);
			});
		});
	}

	async getMonitor(id) {
		return (await this.callOk('getMonitor', id)).monitor;
	}

	pause(id) {
		return this.callOk('pauseMonitor', id);
	}

	resume(id) {
		return this.callOk('resumeMonitor', id);
	}

	delete(id) {
		return this.callOk('deleteMonitor', id, false);
	}

	/** Fetch the full monitor, apply the changes and save it, the same way the edit form does. */
	async edit(id, changes) {
		const monitor = await this.getMonitor(id);
		return this.callOk('editMonitor', { ...monitor, ...changes });
	}

	close() {
		this.socket?.close();
	}
}
