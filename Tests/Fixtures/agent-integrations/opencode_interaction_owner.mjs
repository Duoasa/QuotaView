import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';

const [pluginURL, scenario] = process.argv.slice(2);
const { QuotaView } = await import(pluginURL);
const replies = [];
let typedLookups = 0;

async function waitForMarker(name) {
  const deadline = Date.now() + 10000;
  while (!existsSync(name)) {
    if (Date.now() >= deadline) throw Error('Timed out waiting for ' + name);
    await delay(15);
  }
}

function typedAPI(type) {
  return {
    async reply({ requestID, ...body }) {
      replies.push(['typed', '/' + type + '/' + requestID + '/reply', body]);
      return { response: { ok: true } };
    },
  };
}

let client = {
  get question() { typedLookups++; return typedAPI('question'); },
  get permission() { typedLookups++; return typedAPI('permission'); },
};
if (scenario !== 'fallback') {
  client._client = {
    async post({ url, body }) {
      replies.push(['primary', url, body]);
      if (scenario === 'uncertain') throw Error('Connection closed after accepting the reply');
      return { response: { ok: true } };
    },
  };
} else if (process.env.QV_OPENCODE_SDK) {
  const { createOpencodeClient } = await import(process.env.QV_OPENCODE_SDK);
  const owner = createOpencodeClient({
    baseUrl: 'http://fixture.invalid',
    directory: '/isolated',
    fetch: async req => {
      const url = new URL(req.url);
      assert.equal(url.hostname, 'fixture.invalid');
      assert.equal(req.headers.get('x-opencode-directory'), encodeURIComponent('/isolated'));
      replies.push(['typed', url.pathname, await req.json()]);
      return Response.json(true);
    },
  });
  client = owner;
}
const plugin = await QuotaView({ client });
const emit = (type, properties) => plugin.event({ event: { type, properties: { sessionID: 'session1', ...properties } } });
const ask = id => emit('question.asked', { id, questions: [
  { question: 'Choose a color', options: [{ label: 'Blue' }, { label: 'Orange' }] },
] });
await emit('session.status', { status: { type: 'busy' } });
if (scenario === 'withdrawn') {
  await ask('que_old');
  await waitForMarker('settle-in-client');
  await emit('question.replied', { requestID: 'que_old' });
  await ask('que_old'); // Replay the settled notification before offering the next real question.
  await ask('que_1');
  await waitForMarker('end-turn');
  await emit('session.idle', {});
  await emit('session.status', { status: { type: 'busy' } });
}
await ask('que_1');
if (scenario === 'primary' || scenario === 'fallback') {
  await emit('permission.asked', { id: 'per_2', permission: 'read', patterns: ['file.txt'] });
}
await waitForMarker('finish');
const route = scenario === 'fallback' ? 'typed' : 'primary';
const expected = [[route, '/question/que_1/reply', { answers: [['Orange']] }]];
if (scenario === 'primary' || scenario === 'fallback') {
  expected.push([route, '/permission/per_2/reply', { reply: 'reject' }]);
}
const byPath = (a, b) => a[1].localeCompare(b[1]);
assert.deepEqual(replies.sort(byPath), expected.sort(byPath));
if (route === 'primary') assert.equal(typedLookups, 0);
await emit('session.idle', {});
