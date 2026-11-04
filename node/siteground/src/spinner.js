const FRAMES = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
const out = process.stderr;
const tty = out.isTTY;
const color = (code, s) => (tty ? `\x1b[${code}m${s}\x1b[0m` : s);

/**
 * Terminal spinner on stderr. Without a TTY (CI, pipes) it prints plain lines instead,
 * so logs stay readable.
 */
let active = null;

/** Run fn (e.g. a browser login that prints its own lines) with the running spinner cleared, then redraw it. */
export async function suspendSpinner(fn) {
	const s = active;
	s?.pause();
	try {
		return await fn();
	} finally {
		s?.resume();
	}
}

export function spinner(text) {
	let frame = 0;
	let current = text;
	let timer = null;
	let finished = false;

	const render = () => out.write(`\r\x1b[2K${color(36, FRAMES[frame])} ${current}`);
	const stop = (symbol, message) => {
		if (finished) return;
		finished = true;
		if (timer) clearInterval(timer);
		timer = null;
		if (active === api) active = null;
		if (tty) out.write('\r\x1b[2K');
		out.write(`${symbol} ${message ?? current}\n`);
	};

	const start = () => {
		render();
		timer = setInterval(() => {
			frame = (frame + 1) % FRAMES.length;
			render();
		}, 80);
	};

	if (tty) start();
	else out.write(`… ${text}\n`);

	const api = {
		pause() {
			if (finished || !timer) return;
			clearInterval(timer);
			timer = null;
			out.write('\r\x1b[2K');
		},
		resume() {
			if (!finished && tty && !timer) start();
		},
		set text(value) {
			current = value;
			if (tty) render();
		},
		get text() {
			return current;
		},
		get finished() {
			return finished;
		},
		succeed: (message) => stop(color(32, '✔'), message),
		fail: (message) => stop(color(31, '✖'), message),
		info: (message) => stop(color(33, 'ℹ'), message),
	};
	active = api;
	return api;
}

/**
 * Run fn with a spinner. `done` (string or (result) => string) is the success line;
 * defaults to the task text without a trailing ellipsis.
 */
export async function task(text, fn, { done } = {}) {
	const s = spinner(text);
	try {
		const result = await fn(s);
		if (s.finished) return result;
		s.succeed(typeof done === 'function' ? done(result) : (done ?? text.replace(/(\.\.\.|…)$/, '')));
		return result;
	} catch (err) {
		s.fail(`${text.replace(/(\.\.\.|…)$/, '')} failed`);
		throw err;
	}
}
