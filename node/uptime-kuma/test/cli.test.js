import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseCommand, buildChanges } from '../src/cli.js';

test('set-* shortcuts become update with the value', () => {
	assert.deepEqual(parseCommand(['set-interval', '300', '--all']).values.interval, '300');
	assert.equal(parseCommand(['set-method', 'head', '--domain', 'x.nl']).command, 'update');
	assert.throws(() => parseCommand(['set-timeout', '--all']), /Usage/);
});

test('stray positionals and unknown flags are refused', () => {
	assert.throws(() => parseCommand(['list', 'extra']), /Unexpected argument/);
	assert.throws(() => parseCommand(['list', '--nope']), /Unknown option/);
});

test('buildChanges validates and maps --retries to maxretries', () => {
	assert.deepEqual(buildChanges({ interval: '60', timeout: '30', retries: '2', method: 'head' }), {
		interval: 60,
		timeout: 30,
		maxretries: 2,
		method: 'HEAD',
	});
	assert.throws(() => buildChanges({}), /Nothing to update/);
	assert.throws(() => buildChanges({ interval: '10' }), /at least 20/);
	assert.throws(() => buildChanges({ method: 'FETCH' }), /--method must be one of/);
});
