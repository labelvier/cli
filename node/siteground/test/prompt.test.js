import { fakeStream } from './helpers.js'; // first: sandbox + fetch guard
import { test, describe, before, after, beforeEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { PassThrough } from 'node:stream';

// src/prompt.js computes `interactive` at import time from process.stdin/stdout.isTTY.
// Under node --test both are pipes: that is the non-interactive module. The interactive one is
// imported a second time (query string) after swapping process.stdin for a fake TTY.

describe('without a terminal', () => {
	let prompt;
	before(async () => {
		assert.equal(process.stdin.isTTY, undefined, 'the runner pipes stdin');
		prompt = await import('../src/prompt.js?notty');
	});

	test('interactive is false (a real boolean, even though stdin.isTTY is undefined on a pipe)', () => {
		assert.equal(prompt.interactive, false);
	});

	test('ask/confirm/select/askSecret throw "Missing …" naming the flag, or the question without one', async () => {
		const missing = (what) => new RegExp(`^Error: Missing ${what.replace(/[-]/g, '\\$&')} \\(no terminal to ask it in; pass it as option\\)$`);
		await assert.rejects(prompt.ask('Domain', { flag: '--domain' }), missing('--domain'));
		await assert.rejects(prompt.ask('Admin email'), missing('Admin email'));
		await assert.rejects(prompt.confirm('Enable Memcached?', { flag: '--memcached' }), missing('--memcached'));
		await assert.rejects(prompt.select('Hosting plan:', [], { flag: '--account' }), missing('--account'));
		await assert.rejects(prompt.askSecret('Password'), missing('Password'));
	});

	test('closePrompt() without an open readline is a no-op', () => {
		prompt.closePrompt();
	});
});

describe('with a fake terminal', () => {
	let prompt, input, out;
	const realStdin = Object.getOwnPropertyDescriptor(process, 'stdin');

	before(async () => {
		input = new PassThrough();
		input.isTTY = true;
		input.isRaw = false;
		input.setRawMode = mock.fn((on) => {
			input.isRaw = on;
			return input;
		});
		Object.defineProperty(process, 'stdin', { value: input, configurable: true, enumerable: true });
		out = fakeStream('stdout'); // the readline interface keeps a reference to it: swap once, reset per test
		prompt = await import('../src/prompt.js?tty');
	});
	after(() => {
		prompt.closePrompt();
		Object.defineProperty(process, 'stdin', realStdin);
		out.restore();
	});
	beforeEach(() => {
		out.reset();
		input.setRawMode.mock.resetCalls();
	});

	/** Queue an answer: written after the prompt had a tick to attach its listener. */
	const type = (text) => setImmediate(() => input.write(text));

	test('interactive is true', () => {
		assert.equal(prompt.interactive, true);
	});

	test('confirm(): y / j / n / empty (default) / other', async () => {
		type('y\n');
		assert.equal(await prompt.confirm('Go?'), true);
		type('Ja\n');
		assert.equal(await prompt.confirm('Go?', { defaultValue: false }), true);
		type('n\n');
		assert.equal(await prompt.confirm('Go?'), false);
		type('\n');
		assert.equal(await prompt.confirm('Go?', { defaultValue: true }), true);
		type('\n');
		assert.equal(await prompt.confirm('Go?', { defaultValue: false }), false);
		type('whatever\n');
		assert.equal(await prompt.confirm('Go?'), false);
		assert.match(out.text(), /Go\? \(Y\/n\): /);
		assert.match(out.text(), /Go\? \(y\/N\): /);
	});

	test('ask(): trims, falls back to the default, repeats until validate passes', async () => {
		type('  x.labelvier.dev \n');
		assert.equal(await prompt.ask('Domain'), 'x.labelvier.dev');
		type('\n');
		assert.equal(await prompt.ask('Alias', { defaultValue: 'analytics' }), 'analytics');
		assert.match(out.text(), /Alias \[analytics\]: /);
		type('nope\n');
		setTimeout(() => input.write('a@b.nl\n'), 20);
		const validate = (v) => (v.includes('@') ? null : 'Not a valid email address');
		assert.equal(await prompt.ask('Email', { validate }), 'a@b.nl');
		assert.match(out.text(), /  Not a valid email address\n/);
	});

	test('select(): numbered options, invalid and disabled choices are refused', async () => {
		const options = [
			{ label: 'None', value: null },
			{ label: 'Full', value: 'full', disabled: 'cannot create sites' },
			{ label: 'WordPress', value: 'wp' },
		];
		type('9\n');
		setTimeout(() => input.write('2\n'), 20);
		setTimeout(() => input.write('3\n'), 40);
		assert.equal(await prompt.select('Application:', options), 'wp');
		const text = out.text();
		assert.match(text, /Application:\n   1\) None\n   2\) Full  \(cannot create sites\)\n   3\) WordPress\n/);
		assert.equal(text.match(/  Invalid choice\n/g).length, 2);
		type('1\n');
		assert.equal(await prompt.select('Application:', options), null);
	});

	test('askSecret(): raw mode, no echo, backspace, Enter; pauses stdin when no readline exists', async () => {
		prompt.closePrompt(); // start without a readline interface (its close() also calls setRawMode(false))
		input.setRawMode.mock.resetCalls();
		const resume = mock.method(input, 'resume');
		const pause = mock.method(input, 'pause');
		type('ab\u007fc\r');
		const value = await prompt.askSecret('Password');
		assert.equal(value, 'ac');
		assert.equal(out.text(), 'Password: \n', 'nothing typed is echoed');
		assert.deepEqual(input.setRawMode.mock.calls.map((c) => c.arguments), [[true], [false]]);
		assert.equal(pause.mock.callCount(), 1);
		assert.ok(resume.mock.callCount() >= 1, 'resumed to start reading (adding a data listener resumes too)');
		resume.mock.restore();
		pause.mock.restore();
		assert.equal(input.listenerCount('data'), 0, 'listener removed');
	});

	test('askSecret(): empty Enter gives "", \\n also ends the input, stdin is resumed when a readline is open', async () => {
		type('\n');
		await prompt.confirm('Warm up readline?'); // creates the shared readline interface
		const resume = mock.method(input, 'resume');
		const pause = mock.method(input, 'pause');
		type('\n');
		assert.equal(await prompt.askSecret('TOTP'), '');
		assert.equal(pause.mock.callCount(), 0);
		assert.ok(resume.mock.callCount() >= 2, 'resumed at start and again for the readline');
		resume.mock.restore();
		pause.mock.restore();
	});

	test('askSecret(): Ctrl-C exits with 130', async () => {
		const exit = mock.method(process, 'exit', () => {});
		type('\u0003\r');
		await prompt.askSecret('Password');
		assert.deepEqual(exit.mock.calls[0].arguments, [130]);
		exit.mock.restore();
	});
});
