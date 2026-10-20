import { createInterface } from 'node:readline/promises';

export const interactive = process.stdin.isTTY && process.stdout.isTTY;

let rl;
function readline() {
	rl ??= createInterface({ input: process.stdin, output: process.stdout });
	return rl;
}

export function closePrompt() {
	rl?.close();
	rl = undefined;
}

function requireTTY(what) {
	if (!interactive) throw new Error(`Missing ${what} (no terminal to ask it in; pass it as option)`);
}

export async function ask(question, { defaultValue, validate, flag } = {}) {
	requireTTY(flag || question);
	for (;;) {
		const suffix = defaultValue ? ` [${defaultValue}]` : '';
		const answer = (await readline().question(`${question}${suffix}: `)).trim() || defaultValue || '';
		const error = validate?.(answer);
		if (!error) return answer;
		console.log(`  ${error}`);
	}
}

/** Ask for a secret without echoing it. Empty answer returns ''. */
export async function askSecret(question, { flag } = {}) {
	requireTTY(flag || question);
	const { stdin, stdout } = process;
	stdout.write(`${question}: `);
	const wasRaw = stdin.isRaw;
	stdin.setRawMode(true);
	stdin.resume();
	stdin.setEncoding('utf8');
	let value = '';
	// Listener instead of `for await`: an async iterator destroys stdin when it ends, which would break later prompts.
	return new Promise((resolve) => {
		const onData = (chunk) => {
			for (const ch of chunk) {
				if (ch === '\r' || ch === '\n') {
					stdin.removeListener('data', onData);
					stdin.setRawMode(wasRaw ?? false);
					// A readline interface that already exists keeps reading from stdin; only pause when there is none.
					if (rl) stdin.resume();
					else stdin.pause();
					stdout.write('\n');
					return resolve(value);
				}
				if (ch === '\u0003') {
					stdout.write('\n');
					process.exit(130);
				}
				if (ch === '\u007f' || ch === '\b') value = value.slice(0, -1);
				else value += ch;
			}
		};
		stdin.on('data', onData);
	});
}

export async function confirm(question, { defaultValue = true, flag } = {}) {
	requireTTY(flag || question);
	const hint = defaultValue ? 'Y/n' : 'y/N';
	const answer = (await readline().question(`${question} (${hint}): `)).trim().toLowerCase();
	if (!answer) return defaultValue;
	return answer.startsWith('y') || answer.startsWith('j');
}

/** options: [{ label, value, disabled? }] */
export async function select(question, options, { flag } = {}) {
	requireTTY(flag || question);
	console.log(question);
	options.forEach((o, i) => console.log(`  ${String(i + 1).padStart(2)}) ${o.label}${o.disabled ? `  (${o.disabled})` : ''}`));
	for (;;) {
		const n = Number((await readline().question('Choice: ')).trim());
		const option = options[n - 1];
		if (option && !option.disabled) return option.value;
		console.log('  Invalid choice');
	}
}
