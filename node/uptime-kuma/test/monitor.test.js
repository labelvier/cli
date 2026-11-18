import { test } from 'node:test';
import assert from 'node:assert/strict';
import { monitorUrl, newHttpMonitor, DEFAULTS } from '../src/monitor.js';
import { parseCommand, buildNewMonitor } from '../src/cli.js';

test('monitorUrl adds https:// and keeps paths', () => {
	assert.equal(monitorUrl('apple.com'), 'https://apple.com');
	assert.equal(monitorUrl('http://example.com/status?x=1'), 'http://example.com/status?x=1');
	assert.throws(() => monitorUrl(''), /Usage/);
	assert.throws(() => monitorUrl('ftp://example.com'), /Only http/);
});

test('newHttpMonitor uses our defaults and string status codes', () => {
	const m = newHttpMonitor({ url: 'https://apple.com', notificationIds: [2, 5] });
	assert.equal(m.name, 'apple.com');
	assert.equal(m.interval, DEFAULTS.interval);
	assert.equal(m.retryInterval, DEFAULTS.interval);
	assert.equal(m.method, 'HEAD');
	assert.deepEqual(m.accepted_statuscodes, ['200-299']);
	assert.deepEqual(m.notificationIDList, { 2: true, 5: true });
	assert.equal(m.active, true);
});

test('add takes the URL as positional and options as overrides', () => {
	const { command, values } = parseCommand(['add', 'apple.com', '--name', 'Apple', '--interval', '60', '--paused']);
	assert.equal(command, 'add');
	const m = buildNewMonitor(values);
	assert.equal(m.url, 'https://apple.com');
	assert.equal(m.name, 'Apple');
	assert.equal(m.interval, 60);
	assert.equal(m.active, false);
	assert.throws(() => buildNewMonitor({ target: 'apple.com', interval: '5' }), /at least 20/);
});
