const START = '<!-- kongctl-plan:start -->';
const END = '<!-- kongctl-plan:end -->';

function updateBody(body, diff, sha) {
  if (!/^[a-f0-9]{40}$/.test(sha)) throw new Error('Invalid plan commit SHA');
  const starts = body.split(START).length - 1;
  const ends = body.split(END).length - 1;
  if (starts !== ends || starts > 1 || (starts && body.indexOf(START) > body.indexOf(END))) {
    throw new Error('Malformed kongctl plan markers in PR description');
  }
  const ticks = Math.max(3, ...[...diff.matchAll(/`+/g)].map(m => m[0].length + 1));
  const fence = '`'.repeat(ticks);
  const section = `${START}\n### Kong AI Gateway plan\n\nAdditive plan committed as \`ci/plan.json\` at ${sha}.\n\n${fence}diff\n${diff.trimEnd()}\n${fence}\n${END}`;
  const result = starts
    ? body.slice(0, body.indexOf(START)) + section + body.slice(body.indexOf(END) + END.length)
    : body + (body ? '\n\n' : '') + section;
  if (result.length > 65536) throw new Error('Complete diff exceeds the PR description size limit');
  return result;
}

module.exports = { updateBody, START, END };
