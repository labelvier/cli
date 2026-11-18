import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { KumaClient } from '../src/client.js';

/** Fake Socket.IO socket: answers emits from a handler table, records what was sent. */
function fakeSocket(handlers) {
	const socket = new EventEmitter();
	const on = socket.on.bind(socket);
	socket.sent = [];
	socket.on = (event, fn) => on(event, fn);
	socket.emit = (event, ...args) => {
		const callback = typeof args.at(-1) === 'function' ? args.pop() : null;
		socket.sent.push([event, ...args]);
		const reply = handlers[event];
		if (callback && reply) queueMicrotask(() => callback(typeof reply === 'function' ? reply(...args) : reply));
		return true;
	};
	socket.close = () => {};
	queueMicrotask(() => EventEmitter.prototype.emit.call(socket, 'connect'));
	return socket;
}

async function client(handlers) {
	const socket = fakeSocket(handlers);
	const c = new KumaClient('https://kuma.test', { connect: () => socket });
	await c.connect();
	return { c, socket };
}

test('login returns the token, and flags a required 2FA code', async () => {
	const { c } = await client({ login: (data) => (data.token ? { ok: true, token: 'jwt' } : { ok: false, tokenRequired: true }) });
	await assert.rejects(c.login('u', 'p'), (err) => err.tokenRequired === true);
	assert.equal(await c.login('u', 'p', '123456'), 'jwt');
});

test('an invalid token gives a clear message', async () => {
	const { c } = await client({ loginByToken: { ok: false, msg: 'authInvalidToken' } });
	await assert.rejects(c.loginByToken('old'), /no longer valid/);
});

test('monitors() waits for the pushed monitorList', async () => {
	const { c, socket } = await client({});
	const pending = c.monitors();
	EventEmitter.prototype.emit.call(socket, 'monitorList', { 1: { id: 1 } });
	assert.deepEqual(await pending, { 1: { id: 1 } });
});

test('edit sends the full monitor with the changes applied', async () => {
	const { c, socket } = await client({
		getMonitor: { ok: true, monitor: { id: 7, name: 'x', interval: 300, accepted_statuscodes: ['200-299'] } },
		editMonitor: { ok: true },
	});
	await c.edit(7, { interval: 60 });
	assert.deepEqual(socket.sent.at(-1), ['editMonitor', { id: 7, name: 'x', interval: 60, accepted_statuscodes: ['200-299'] }]);
});

test('delete never deletes group children', async () => {
	const { c, socket } = await client({ deleteMonitor: { ok: true } });
	await c.delete(9);
	assert.deepEqual(socket.sent.at(-1), ['deleteMonitor', 9, false]);
});

test('add returns the new id; default notifications come from the pushed list', async () => {
	const { c, socket } = await client({ add: { ok: true, monitorID: 42 } });
	EventEmitter.prototype.emit.call(socket, 'notificationList', [{ id: 1, isDefault: true }, { id: 2, isDefault: false }]);
	assert.deepEqual(c.defaultNotificationIds(), [1]);
	assert.equal(await c.add({ name: 'x' }), 42);
});
