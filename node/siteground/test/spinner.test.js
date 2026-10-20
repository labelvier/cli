import { captureStream } from './helpers.js'; // first: sandbox + fetch guard
import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';

// src/spinner.js reads process.stderr.isTTY at import time: one import per mode (query string = fresh module).
const stderrIsTTY = process.stderr.isTTY;

describe('without a TTY (CI, pipes)', () => {
	let spinner, task, out;
	before(async () => {
		process.stderr.isTTY = false;
		({ spinner, task } = await import('../src/spinner.js?notty'));
	});
	after(() => {
		process.stderr.isTTY = stderrIsTTY;
	});
	const capture = (t) => {
		out = captureStream(process.stderr);
		t.after(out.restore);
		return out;
	};

	test('task(): prints a plain "…" line, then ✔ with the done text; returns the result', async (t) => {
		capture(t);
		const result = await task('Getting plans…', async () => 42, { done: '2 plans' });
		assert.equal(result, 42);
		assert.equal(out.text(), '… Getting plans…\n✔ 2 plans\n');
	});

	test('task(): done defaults to the label without its ellipsis, or is computed from the result', async (t) => {
		capture(t);
		await task('Checking...', async () => null);
		await task('Looking up…', async () => ({ n: 3 }), { done: (r) => `${r.n} found` });
		assert.equal(out.text(), '… Checking...\n✔ Checking\n… Looking up…\n✔ 3 found\n');
	});

	test('task(): a failure prints ✖ "<label> failed" and rethrows the error', async (t) => {
		capture(t);
		const boom = new Error('boom');
		await assert.rejects(task('Creating site…', async () => { throw boom; }), (err) => err === boom);
		assert.equal(out.text(), '… Creating site…\n✖ Creating site failed\n');
	});

	test('task(): when fn finishes the spinner itself (info), no second line is printed', async (t) => {
		capture(t);
		const r = await task('Setting up SSL…', async (s) => {
			s.info('SSL skipped: DNS not pointed');
			return { ok: false };
		}, { done: 'never' });
		assert.deepEqual(r, { ok: false });
		assert.equal(out.text(), '… Setting up SSL…\nℹ SSL skipped: DNS not pointed\n');
	});

	test('spinner(): text updates are silent without a TTY, stop happens once, no cursor codes', (t) => {
		capture(t);
		const s = spinner('Waiting…');
		s.text = 'Waiting: site running (3s)…';
		assert.equal(s.text, 'Waiting: site running (3s)…');
		assert.equal(s.finished, false);
		s.succeed();
		s.fail('ignored');
		assert.equal(s.finished, true);
		assert.equal(out.text(), '… Waiting…\n✔ Waiting: site running (3s)…\n');
		assert.doesNotMatch(out.text(), /\x1b\[/);
	});
});

describe('with a TTY', () => {
	let spinner, task, out;
	before(async () => {
		process.stderr.isTTY = true;
		({ spinner, task } = await import('../src/spinner.js?tty'));
	});
	after(() => {
		process.stderr.isTTY = stderrIsTTY;
	});

	test('spinner(): renders a coloured frame, clears the line on stop, stops the interval', async (t) => {
		out = captureStream(process.stderr);
		t.after(out.restore);
		const s = spinner('Working…');
		assert.match(out.chunks[0], /^\r\x1b\[2K\x1b\[36m⠋\x1b\[0m Working…$/);
		s.text = 'Still working…';
		assert.match(out.chunks.at(-1), /Still working…$/);
		s.succeed('Done');
		assert.equal(out.chunks.at(-2), '\r\x1b[2K');
		assert.equal(out.chunks.at(-1), '\x1b[32m✔\x1b[0m Done\n');
		const written = out.chunks.length;
		await new Promise((r) => setTimeout(r, 120));
		assert.equal(out.chunks.length, written, 'no frames after stop');
	});

	test('task(): failure line is red', async (t) => {
		out = captureStream(process.stderr);
		t.after(out.restore);
		await assert.rejects(task('X…', async () => { throw new Error('no'); }), /no/);
		assert.equal(out.chunks.at(-1), '\x1b[31m✖\x1b[0m X failed\n');
	});
});
