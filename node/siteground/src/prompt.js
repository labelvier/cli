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
