const FRAMES = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
const out = process.stderr;
const tty = out.isTTY;
const color = (code, s) => (tty ? `\x1b[${code}m${s}\x1b[0m` : s);

/**
 * Terminal spinner on stderr. Without a TTY (CI, pipes) it prints plain lines instead,
 * so logs stay readable.
 */
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
		if (tty) out.write('\r\x1b[2K');
		out.write(`${symbol} ${message ?? current}\n`);
	};

	if (tty) {
		render();
		timer = setInterval(() => {
			frame = (frame + 1) % FRAMES.length;
			render();
		}, 80);
	} else {
		out.write(`… ${text}\n`);
	}

	return {
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
