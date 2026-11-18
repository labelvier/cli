import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildFilter, selectMonitors, monitorHost, normalizeDomain } from '../src/filter.js';

const monitors = {
	1: { id: 1, name: 'labelvier.nl', type: 'http', url: 'https://labelvier.nl', active: true, tags: [] },
	2: { id: 2, name: 'www.example.com', type: 'http', url: 'https://www.example.com/path', active: true, tags: [{ name: 'Production' }] },
	3: { id: 3, name: 'example.com | parked', type: 'http', url: 'https://example.com', active: false, tags: [] },
	4: { id: 4, name: 'notexample.com', type: 'http', url: 'https://notexample.com', active: true, tags: [] },
	5: { id: 5, name: 'Server ping', type: 'ping', url: 'https://', hostname: 'srv.example.com', active: true, tags: [] },
	6: { id: 6, name: 'Group', type: 'group', url: null, active: true, tags: [] },
};

const ids = (options) => selectMonitors(monitors, options).matched.map((m) => m.id);

test('monitorHost reads the URL, or hostname for ping monitors', () => {
	assert.equal(monitorHost(monitors[2]), 'www.example.com');
	assert.equal(monitorHost(monitors[5]), 'srv.example.com');
	assert.equal(monitorHost(monitors[6]), '');
});

test('normalizeDomain strips scheme, path and www.', () => {
	assert.equal(normalizeDomain('https://www.Example.com/foo'), 'example.com');
	assert.equal(normalizeDomain(' example.com '), 'example.com');
});

test('--domain matches the domain and its subdomains, not look-alikes', () => {
	assert.deepEqual(ids({ domain: 'example.com' }), [2, 3, 5]);
	assert.deepEqual(ids({ domain: 'https://www.example.com' }), [2, 3, 5]);
	assert.deepEqual(ids({ domain: 'labelvier.nl,notexample.com' }), [1, 4]);
});

test('--filter is a substring of URL or hostname', () => {
	assert.deepEqual(ids({ filter: 'example' }), [2, 3, 4, 5]);
});

test('--id, --name and --tag', () => {
	assert.deepEqual(ids({ id: '3,1' }), [1, 3]);
	assert.deepEqual(ids({ name: 'PARKED' }), [3]);
	assert.deepEqual(ids({ tag: 'production' }), [2]);
});

test('groups are left out unless --id or --groups', () => {
	assert.deepEqual(ids({ all: true }), [1, 2, 3, 4, 5]);
	assert.deepEqual(ids({ all: true, groups: true }), [1, 2, 3, 4, 5, 6]);
	assert.deepEqual(ids({ id: '6' }), [6]);
});

test('exactly one filter is required', () => {
	assert.throws(() => buildFilter({}), /Choose monitors/);
	assert.throws(() => buildFilter({ all: true, domain: 'x.nl' }), /one filter at a time/);
	assert.throws(() => buildFilter({ id: 'abc' }), /Invalid monitor id/);
	assert.throws(() => buildFilter({ name: '(' }), /Invalid --name/);
});
