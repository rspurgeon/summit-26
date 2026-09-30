const { test } = require('node:test');
const assert = require('node:assert/strict');
const { updateBody, START, END } = require('./pr-body.cjs');
const sha = 'a'.repeat(40);

test('append a complete diff and preserve the original description', () => {
  const result = updateBody('User description', '+ model', sha);
  assert.ok(result.startsWith('User description\n\n' + START));
  assert.ok(result.includes('+ model'));
  assert.ok(result.includes(sha));
});
test('replace only the marked section and remain idempotent', () => {
  const body = `Before\n${START}\nold diff\n${END}\nAfter`;
  const result = updateBody(body, 'new diff', sha);
  assert.ok(result.startsWith('Before\n'));
  assert.ok(result.endsWith('\nAfter'));
  assert.ok(!result.includes('old diff'));
  assert.equal(updateBody(result, 'new diff', sha), result);
});
test('handle code fences in diffs without breaking the section', () => {
  assert.ok(updateBody('', '```', sha).includes('````diff'));
});
test('reject malformed markers and oversized descriptions without destroying user text', () => {
  for (const body of [START, END + START, START + END + START + END]) {
    assert.throws(() => updateBody(body, 'diff', sha), /Malformed/);
  }
  assert.throws(() => updateBody('x'.repeat(65536), 'diff', sha), /size limit/);
});
