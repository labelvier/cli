import { test } from 'node:test';
import assert from 'node:assert/strict';
import { totp, base32Decode } from '../src/totp.js';

// RFC 6238 appendix B vectors (SHA-1, secret "12345678901234567890"), last 6 of the 8 digits.
const SECRET = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

test('base32Decode ignores spaces, dashes, case and padding', () => {
	assert.equal(base32Decode('jbsw y3dp-ehpk 3pxp====').toString('hex'), '48656c6c6f21deadbeef');
	assert.equal(base32Decode('').length, 0);
});

test('totp matches the RFC 6238 test vectors', () => {
	assert.equal(totp(SECRET, { now: 59_000 }), '287082');
	assert.equal(totp(SECRET, { now: 1_111_111_109_000 }), '081804');
	assert.equal(totp(SECRET, { now: 1_234_567_890_000 }), '005924');
	assert.equal(totp(SECRET, { now: 20_000_000_000_000 }), '353130');
});

test('totp is stable within a 30 s window and changes after it', () => {
	assert.equal(totp(SECRET, { now: 30_000 }), totp(SECRET, { now: 59_999 }));
	assert.notEqual(totp(SECRET, { now: 59_999 }), totp(SECRET, { now: 60_000 }));
});

test('totp rejects a secret that is not base32', () => {
	assert.throws(() => totp('!!!'), /not valid base32/);
});
