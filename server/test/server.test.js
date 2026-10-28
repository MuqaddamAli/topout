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
const next = (s, ev) => new Promise((done) => s.once(ev, done));
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

/// A room with [n] players (the host first), started. Returns the sockets in
/// join order and the room everyone is sent after the start.
async function startedRoom(n) {
  const host = await makeRoom('P1');
  const all = [host.s];
  for (let k = 2; k <= n; k++) {
    const s = await connect();
    await ask(s, 'join', { code: host.code, name: `P${k}` });
    all.push(s);
  }
  const after = roomWhen(host.s, (r) => r.started);
  assert.deepEqual(await ask(host.s, 'start'), {});
  return { host, all, room: await after };
}

for (const [n, lanes] of [[1, 1], [2, 1], [3, 2], [5, 3], [8, 4]]) {
  test(`${n} player(s) get ${lanes} lane(s), in join order: lane 1 left, lane 1 right, lane 2 left...`, async () => {
    const { all, room } = await startedRoom(n);
    assert.equal(room.lanes, lanes);
    assert.deepEqual(
      room.players.map((p) => [p.name, p.lane, p.side]),
      Array.from({ length: n }, (_, k) => [`P${k + 1}`, Math.floor(k / 2), k % 2]),
    );
    for (const s of all) s.emit('leave');
  });
}

test('before the start nobody has a lane, and the started event says how many', async () => {
  const host = await makeRoom();
  assert.equal(host.r.room.lanes, null);
  assert.equal(host.r.room.players[0].lane, null);
  const b = await connect();
  await ask(b, 'join', { code: host.code, name: 'B' });
  const c = await connect();
  await ask(c, 'join', { code: host.code, name: 'C' });
  const started = next(c, 'started');
  await ask(host.s, 'start');
  assert.equal((await started).lanes, 2);
});

test('the creator leaves before the start: the next player gets lane 1 left', async () => {
  const host = await makeRoom('A');
  const b = await connect();
  const rb = await ask(b, 'join', { code: host.code, name: 'B' });
  const c = await connect();
  await ask(c, 'join', { code: host.code, name: 'C' });
  const d = await connect();
  await ask(d, 'join', { code: host.code, name: 'D' });
  const left = roomWhen(b, (r) => r.players.length === 3);
  host.s.emit('leave');
  assert.equal((await left).host, rb.you);
  const after = roomWhen(b, (r) => r.started);
  assert.deepEqual(await ask(b, 'start'), {});
  const room = await after;
  assert.equal(room.lanes, 2);
  assert.deepEqual(room.players.map((p) => [p.name, p.lane, p.side]), [['B', 0, 0], ['C', 0, 1], ['D', 1, 0]]);
});

test('someone leaving during the climb changes no lanes, nor how many there are', async () => {
  const { all, room } = await startedRoom(5);
  assert.equal(room.lanes, 3);
  const update = roomWhen(all[4], (r) => r.players.length === 4);
  all[1].emit('leave');
  const now = await update;
  assert.equal(now.lanes, 3);
  assert.deepEqual(now.players.map((p) => [p.name, p.lane, p.side]), [['P1', 0, 0], ['P3', 1, 0], ['P4', 1, 1], ['P5', 2, 0]]);
});

test('a player who drops out and comes back keeps their lane', async () => {
  const host = await makeRoom();
  const b = await connect();
  await ask(b, 'join', { code: host.code, name: 'B' });
  const c = await connect();
  const rc = await ask(c, 'join', { code: host.code, name: 'C' });
  const after = roomWhen(host.s, (r) => r.started);
  await ask(host.s, 'start');
  await after;
  const dropped = roomWhen(host.s, (r) => r.players[2]?.connected === false);
  c.close();
  await dropped;
  const back = await ask(await connect(), 'rejoin', { code: host.code, token: rc.token });
  assert.equal(back.room.lanes, 2);
  assert.deepEqual(back.room.players.map((p) => [p.name, p.lane, p.side]), [['Host', 0, 0], ['B', 0, 1], ['C', 1, 0]]);
});

test('topping out: each time counts once, and when everyone is up the climb ends', async () => {
  const { all, room } = await startedRoom(3);
  assert.equal(room.ended, false);
  assert.equal(room.round, 1);
  let update = roomWhen(all[0], (r) => r.players[1].finish != null);
  all[1].emit('topped', 64.23);
  assert.equal((await update).players[1].finish, 64.2);
  // a second top-out, junk and a negative time change nothing
  all[1].emit('topped', 10);
  all[2].emit('topped', 'soon');
  all[2].emit('topped', -5);
  update = roomWhen(all[0], (r) => r.players[0].finish != null);
  all[0].emit('topped', 70);
  const two = await update;
  assert.deepEqual(two.players.map((p) => p.finish), [70, 64.2, null]);
  assert.equal(two.ended, false);
  update = roomWhen(all[0], (r) => r.ended);
  all[2].emit('topped', 99.9);
  assert.deepEqual((await update).players.map((p) => p.finish), [70, 64.2, 99.9]);
  for (const s of all) s.emit('leave');
});

test('End climb: only the creator, and then the climb is over (no more states)', async () => {
  const { all } = await startedRoom(2);
  assert.equal((await ask(all[1], 'end')).error, 'Only the creator can start');
  const update = roomWhen(all[1], (r) => r.ended);
  assert.deepEqual(await ask(all[0], 'end'), {});
  assert.equal((await update).ended, true);
  assert.equal((await ask(all[0], 'end')).error, 'Something went wrong. Try again.');
  // after the end nothing is relayed
  let got = false;
  all[0].on('state', () => (got = true));
  all[1].emit('state', [1, 'ada', 180, 100]);
  await wait(80);
  assert.equal(got, false);
  for (const s of all) s.emit('leave');
});

test('Play again: only after the results and only the creator; a new round with fresh times', async () => {
  const { all } = await startedRoom(3);
  assert.equal((await ask(all[0], 'again')).error, 'The climb is still on');
  all[1].emit('topped', 30);
  await roomWhen(all[0], (r) => r.players[1].finish != null);
  const over = roomWhen(all[0], (r) => r.ended);
  await ask(all[0], 'end');
  await over;
  assert.equal((await ask(all[1], 'again')).error, 'Only the creator can start');
  const started = next(all[2], 'started');
  const fresh = roomWhen(all[2], (r) => r.round === 2);
  assert.deepEqual(await ask(all[0], 'again'), {});
  const st = await started;
  assert.equal(st.round, 2);
  assert.equal(st.lanes, 2);
  const room = await fresh;
  assert.equal(room.ended, false);
  assert.equal(room.started, true);
  assert.deepEqual(room.players.map((p) => [p.name, p.lane, p.side, p.finish]), [['P1', 0, 0, null], ['P2', 0, 1, null], ['P3', 1, 0, null]]);
  // still no joining while the room climbs
  assert.equal((await ask(await connect(), 'join', { code: room.code, name: 'Late' })).error, 'This climb has already started');
  for (const s of all) s.emit('leave');
});

test('the last one still climbing leaves: everyone who stayed is up, so the climb ends', async () => {
  const { all } = await startedRoom(3);
  all[0].emit('topped', 50);
  all[2].emit('topped', 60);
  await roomWhen(all[0], (r) => r.players[2].finish != null);
  const update = roomWhen(all[0], (r) => r.players.length === 2);
  all[1].emit('leave');
  const room = await update;
  assert.equal(room.ended, true);
  for (const s of all) s.emit('leave');
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
