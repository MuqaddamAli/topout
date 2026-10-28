// Starts a real server on a free port and talks to it like the game does.
// Run: npm test
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { io } = require('socket.io-client');
const { createServer, originAllowed } = require('../index');
const { CODE_LETTERS } = require('../rooms');

let server, url;
const sockets = [];

before(async () => {
  server = createServer({ graceMs: 300, countdownMs: 50 });
  url = `http://127.0.0.1:${await server.listen(0, '127.0.0.1')}`;
});
after(async () => {
  for (const s of sockets) s.close();
  await server.close();
});

function connect() {
  const s = io(url, { transports: ['websocket'], reconnection: false, forceNew: true });
  sockets.push(s);
  return new Promise((done) => s.on('connect', () => done(s)));
}
const ask = (s, ev, data) => new Promise((done) => (data === undefined ? s.emit(ev, done) : s.emit(ev, data, done)));
const next = (s, ev) => new Promise((done) => s.once(ev, (...a) => done(a.length > 1 ? a : a[0])));
const wait = (ms) => new Promise((done) => setTimeout(done, ms));
/// The first room update that [ok] accepts (earlier updates may still be on their way).
const roomWhen = (s, ok) =>
  new Promise((done) => {
    const on = (r) => ok(r) && (s.off('room', on), done(r));
    s.on('room', on);
  });
const today = { route: 'daily', mode: 'normal', dateKey: '2026-10-28' };

async function makeRoom(name = 'Host') {
  const s = await connect();
  const r = await ask(s, 'create', { name, ...today });
  return { s, r, code: r.room.code };
}

test('GET /health answers 200', async () => {
  const res = await fetch(`${url}/health`);
  assert.equal(res.status, 200);
});

test('create gives a readable 4-letter code and the creator as host', async () => {
  const { r } = await makeRoom('Ada');
  assert.equal(r.room.code.length, 4);
  for (const ch of r.room.code) assert.ok(CODE_LETTERS.includes(ch), r.room.code);
  assert.equal(r.room.host, r.you);
  assert.equal(r.room.dateKey, '2026-10-28');
  assert.deepEqual(r.room.players.map((p) => p.name), ['Ada']);
});

test('join adds the player and everyone gets the new list', async () => {
  const host = await makeRoom();
  const update = roomWhen(host.s, (r) => r.players.length === 2);
  const b = await connect();
  const r = await ask(b, 'join', { code: host.code.toLowerCase(), name: '  Bo  ' });
  assert.equal(r.error, undefined);
  await update;
  assert.deepEqual(r.room.players.map((p) => p.name), ['Host', 'Bo']);
  // the Daily Wall comes from the creator, not from whoever joins
  assert.equal(r.room.dateKey, '2026-10-28');
});

test('a wrong code gives "Room not found"', async () => {
  const s = await connect();
  assert.equal((await ask(s, 'join', { code: 'ZZZZ', name: 'X' })).error, 'Room not found');
});

test('a 9th player gets "Room is full (8/8)"', async () => {
  const host = await makeRoom();
  for (let k = 0; k < 7; k++) {
    const r = await ask(await connect(), 'join', { code: host.code, name: `P${k}` });
    assert.equal(r.error, undefined);
  }
  const r = await ask(await connect(), 'join', { code: host.code, name: 'Ninth' });
  assert.equal(r.error, 'Room is full (8/8)');
});

test('only the host can start, then joining is closed and states are relayed', async () => {
  const host = await makeRoom();
  const b = await connect();
  const rb = await ask(b, 'join', { code: host.code, name: 'B' });
  assert.equal((await ask(b, 'start')).error, 'Only the creator can start');

  const started = next(b, 'started');
  assert.deepEqual(await ask(host.s, 'start'), {});
  assert.ok((await started).startsIn <= 50);

  const late = await ask(await connect(), 'join', { code: host.code, name: 'Late' });
  assert.equal(late.error, 'This climb has already started');

  const got = next(host.s, 'state');
  b.emit('state', [1, 'ada', 180, 100]);
  assert.deepEqual(await got, [rb.you, [1, 'ada', 180, 100]]);
});

test('picking a climber is sent to everyone', async () => {
  const host = await makeRoom();
  const b = await connect();
  await ask(b, 'join', { code: host.code, name: 'B' });
  const update = roomWhen(host.s, (r) => r.players[1]?.climber === 'kai');
  b.emit('pick', 'kai');
  await update;
});

test('when the creator leaves the next player becomes host; an empty room is gone', async () => {
  const host = await makeRoom();
  const b = await connect();
  const rb = await ask(b, 'join', { code: host.code, name: 'B' });
  const c = await connect();
  await ask(c, 'join', { code: host.code, name: 'C' });

  const update = roomWhen(b, (r) => r.players.length === 2);
  host.s.emit('leave');
  const room = await update;
  assert.equal(room.host, rb.you);
  assert.deepEqual(room.players.map((p) => p.name), ['B', 'C']);

  b.emit('leave');
  c.emit('leave');
  await wait(50);
  assert.equal(server.rooms.rooms.has(host.code), false);
});

test('a dropped player keeps the slot for the grace period and can come back', async () => {
  const host = await makeRoom();
  const b = await connect();
  const rb = await ask(b, 'join', { code: host.code, name: 'B' });

  const dropped = roomWhen(host.s, (r) => r.players[1]?.connected === false);
  b.close();
  await dropped;

  const b2 = await connect();
  const back = await ask(b2, 'rejoin', { code: host.code, token: rb.token });
  assert.equal(back.you, rb.you);
  assert.equal(back.room.players[1].connected, true);

  // a drop that lasts longer than the grace period frees the slot
  const gone = roomWhen(host.s, (r) => r.players.length === 1);
  b2.close();
  assert.deepEqual((await gone).players.map((p) => p.name), ['Host']);
});

test('origins: Vercel, localhost and the local network only', () => {
  assert.ok(originAllowed('https://topout.vercel.app'));
  assert.ok(originAllowed('http://localhost:5000'));
  assert.ok(originAllowed('http://192.168.1.20:8080'));
  assert.ok(originAllowed('http://10.0.0.7:8080'));
  assert.ok(originAllowed(undefined));
  assert.ok(!originAllowed('https://evil.example.com'));
  assert.ok(!originAllowed('http://topout.vercel.app.evil.com'));
});
