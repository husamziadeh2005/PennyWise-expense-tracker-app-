import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addDays, daysInMonth, isValidIsoDate, monthRange, shiftMonth } from '../../src/lib/dates.js';
import { fromCents, percent, toCents } from '../../src/lib/money.js';
import { sniffMimeType } from '../../src/lib/files.js';
import { ApiError, fromSupabaseError } from '../../src/lib/errors.js';

test('dates', () => {
  assert.equal(isValidIsoDate('2026-02-28'), true);
  assert.equal(isValidIsoDate('2026-02-30'), false);
  assert.equal(isValidIsoDate('2028-02-29'), true);
  assert.equal(isValidIsoDate('26-1-1'), false);
  assert.equal(daysInMonth('2026-02'), 28);
  assert.deepEqual(monthRange('2026-12'), { start: '2026-12-01', end: '2026-12-31' });
  assert.equal(shiftMonth('2026-01', -1), '2025-12');
  assert.equal(shiftMonth('2026-12', 1), '2027-01');
  assert.equal(addDays('2026-12-31', 1), '2027-01-01');
});

test('money', () => {
  assert.equal(toCents(19.99), 1999);
  assert.equal(toCents('0.29'), 29); // 0.29 * 100 = 28.999999999999996 in floats
  assert.equal(fromCents(toCents(0.1) + toCents(0.2)), 0.3);
  assert.equal(percent(1, 3), 33.3);
  assert.equal(percent(5, 0), null);
});

test('file type is detected from bytes, not from the name', () => {
  const png = Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex');
  const jpg = Buffer.from('ffd8ffe000104a4649460001', 'hex');
  const pdf = Buffer.from('%PDF-1.7\n%âãÏÓ', 'latin1');
  const webp = Buffer.from('RIFF\x00\x00\x00\x00WEBPVP8 ', 'latin1');
  const heic = Buffer.from('\x00\x00\x00\x18ftypheic\x00\x00', 'latin1');
  assert.equal(sniffMimeType(png), 'image/png');
  assert.equal(sniffMimeType(jpg), 'image/jpeg');
  assert.equal(sniffMimeType(pdf), 'application/pdf');
  assert.equal(sniffMimeType(webp), 'image/webp');
  assert.equal(sniffMimeType(heic), 'image/heic');
  assert.equal(sniffMimeType(Buffer.from('<script>alert(1)</script>')), null);
  assert.equal(sniffMimeType(Buffer.alloc(3)), null);
});

test('database errors become proper HTTP errors', () => {
  assert.equal(fromSupabaseError({ code: '23505' }, { conflictMessage: 'dup' }).status, 409);
  assert.equal(fromSupabaseError({ code: '23505' }, { conflictMessage: 'dup' }).message, 'dup');
  assert.equal(fromSupabaseError({ code: '23503' }).code, 'invalid_reference');
  assert.equal(fromSupabaseError({ code: '22P02' }).status, 400);
  assert.equal(fromSupabaseError({ code: '42501' }).status, 403);
  assert.equal(fromSupabaseError({ code: 'PGRST116' }).status, 404);
  const hinted = fromSupabaseError({ code: '23514', hint: 'category_type_mismatch' });
  assert.equal(hinted.code, 'category_type_mismatch');
  assert.equal(hinted.status, 400);
  const unknown = fromSupabaseError({ code: 'XX000', message: 'boom' });
  assert.equal(unknown.status, 500);
  assert.equal(unknown.message, 'Something went wrong. Please try again.'); // never leak DB text
  assert.ok(fromSupabaseError(ApiError.notFound()) instanceof ApiError);
});
