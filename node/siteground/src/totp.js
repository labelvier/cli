import { createHmac } from 'node:crypto';

/** Decode an RFC 4648 base32 string (spaces, dashes and padding are ignored). */
export function base32Decode(input) {
	const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
	const clean = input.toUpperCase().replace(/[^A-Z2-7]/g, '');
	const bytes = [];
	let bits = 0;
	let value = 0;
	for (const char of clean) {
		value = (value << 5) | alphabet.indexOf(char);
		bits += 5;
		if (bits >= 8) {
			bytes.push((value >>> (bits - 8)) & 0xff);
			bits -= 8;
		}
	}
	return Buffer.from(bytes);
}

/** RFC 6238 time-based one-time password (SHA-1, 30 s, 6 digits: what authenticator apps use). */
export function totp(secret, { now = Date.now(), period = 30, digits = 6 } = {}) {
	const key = base32Decode(secret);
	if (key.length === 0) throw new Error('TOTP secret is not valid base32.');
	const counter = Buffer.alloc(8);
	counter.writeBigUInt64BE(BigInt(Math.floor(now / 1000 / period)));
	const digest = createHmac('sha1', key).update(counter).digest();
	const offset = digest[digest.length - 1] & 0x0f;
	const code = digest.readUInt32BE(offset) & 0x7fffffff;
	return String(code % 10 ** digits).padStart(digits, '0');
}
