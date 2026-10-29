// The Topout multiplayer server: rooms for up to 8 climbers, and a relay for
// their climber states. Run with `npm start`; it listens on $PORT (3000).
//
// Client to server (each with an answer callback, except state and leave):
//   create {name, route, mode, dateKey, climber}  -> {you, token, room, startsIn} or {error}
//   join   {code, name, climber}                  -> same
//   rejoin {code, token}                          -> same (after a dropped connection)
//   pick   climber
//   ready  true or false   (in the lobby: ready to climb)
//   start                                         -> {} or {error} (host only)
//   topped secs       you reached the top, secs after the start
//   end                                           -> {} or {error} (host only: the results show)
//   again                                         -> {} or {error} (host only, after the results: a new climb)
//   state  [...]      relayed to the others in the room (an emote or a chat phrase sent too soon is taken out)
//   leave
// Server to client:
//   room    the room and its players, on every change; from the start it
//           also has the lane count and each player's lane and side, and
//           each player's finish (seconds) once topped out. ended: the
//           climb is over and the results show; round: which climb it is
//   started {startsIn, lanes}  ms until everyone starts climbing
//   state   [playerId, [...]]
const http = require('http');
const { Server } = require('socket.io');
const { Rooms } = require('./rooms');

/// Browsers may connect from the Vercel site, localhost and the local network.
/// More origins (a custom domain) can be added with ALLOWED_ORIGINS=a,b.
function originAllowed(origin, extra = []) {
  if (!origin) return true; // not a browser (the bots, the tests)
  if (extra.includes(origin)) return true;
  let u;
  try {
    u = new URL(origin);
  } catch {
    return false;
  }
  const h = u.hostname;
  if (u.protocol === 'https:' && h.endsWith('.vercel.app')) return true;
  if (h === 'localhost' || h === '127.0.0.1' || h === '[::1]') return true;
  return /^192\.168\.\d+\.\d+$/.test(h) || /^10\.\d+\.\d+\.\d+$/.test(h);
}

function createServer({ graceMs, countdownMs } = {}) {
  const extra = (process.env.ALLOWED_ORIGINS || '').split(',').map((s) => s.trim()).filter(Boolean);
  const rooms = new Rooms({ graceMs, countdownMs });

  const httpServer = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url.split('?')[0] === '/health') {
      res.writeHead(200, { 'Content-Type': 'text/plain', 'Access-Control-Allow-Origin': '*' });
      res.end('ok');
      return;
    }
    res.writeHead(404);
    res.end();
  });

  const io = new Server(httpServer, {
    cors: { origin: (origin, cb) => cb(null, originAllowed(origin, extra)) },
    // websockets have no CORS check of their own, so the origin is checked here too
    allowRequest: (req, cb) => cb(null, originAllowed(req.headers.origin, extra)),
    maxHttpBufferSize: 8 * 1024,
    pingInterval: 10000,
    pingTimeout: 8000,
  });

  const send = (room) => {
    if (room) io.to(room.code).emit('room', rooms.view(room));
  };
  const startsIn = (room) => (room.started ? Math.max(0, room.startAt - Date.now()) : null);
  const reply = (ack, v) => typeof ack === 'function' && ack(v);

  io.on('connection', (socket) => {
    /// Ties this connection to [player], leaving any room it was in before.
    const attach = (room, player, ack) => {
      const old = socket.data.player;
      if (old && old !== player) {
        socket.leave(old.code);
        send(rooms.leave(old));
      }
      // a half-dead older connection of the same player stops speaking for them
      const before = player.socketId && io.sockets.sockets.get(player.socketId);
      if (before && before !== socket) {
        before.data.player = null;
        before.leave(room.code);
      }
      socket.data.player = player;
      player.socketId = socket.id;
      socket.join(room.code);
      reply(ack, { you: player.id, token: player.token, room: rooms.view(room), startsIn: startsIn(room) });
      send(room);
    };
    const answer = (r, ack) => (r.error ? reply(ack, { error: r.error }) : attach(r.room, r.player, ack));

    socket.on('create', (d, ack) => answer(rooms.create(d || {}), ack));
    socket.on('join', (d, ack) => answer(rooms.join(d?.code, d || {}), ack));
    socket.on('rejoin', (d, ack) => answer(rooms.rejoin(d?.code, d?.token), ack));

    socket.on('pick', (climber) => send(rooms.pick(socket.data.player, climber)));
    socket.on('ready', (on) => send(rooms.ready(socket.data.player, on)));

    socket.on('topped', (secs) => send(rooms.topped(socket.data.player, secs)));

    /// A creator's action: [act] answers { room } or { error }; after a yes,
    /// [after] tells the room. The answer callback comes first or after a
    /// payload, depending on the client.
    const hostOnly = (act, after) => (...args) => {
      const ack = args.find((a) => typeof a === 'function');
      const r = act(socket.data.player);
      if (r.error) return reply(ack, { error: r.error });
      reply(ack, {});
      after(r.room);
    };
    /// A climb starts (the first one, or Play again): everyone counts down.
    const begun = (room) => {
      io.to(room.code).emit('started', { startsIn: startsIn(room), lanes: room.lanes, round: room.round });
      send(room);
    };
    socket.on('start', hostOnly((p) => rooms.start(p), begun));
    socket.on('end', hostOnly((p) => rooms.end(p), send));
    socket.on('again', hostOnly((p) => rooms.again(p), begun));

    socket.on('state', (s) => {
      const p = socket.data.player, room = rooms.roomOf(p);
      if (!room || !room.started || room.ended || !Array.isArray(s)) return;
      // volatile: a state that cannot go out now is dropped, the next one is newer anyway
      socket.to(room.code).volatile.emit('state', [p.id, rooms.gate(p, s)]);
    });

    socket.on('leave', () => {
      const p = socket.data.player;
      if (!p) return;
      socket.data.player = null;
      socket.leave(p.code);
      send(rooms.leave(p));
    });

    socket.on('disconnect', () => {
      const p = socket.data.player;
      // a newer connection may have taken this slot already
      if (!p || p.socketId !== socket.id) return;
      send(rooms.drop(p, send));
    });
  });

  return {
    httpServer,
    io,
    rooms,
    listen: (port, host) => new Promise((done) => httpServer.listen(port, host, () => done(httpServer.address().port))),
    close: () => new Promise((done) => io.close(() => done())),
  };
}

module.exports = { createServer, originAllowed };

if (require.main === module) {
  const port = Number(process.env.PORT) || 3000;
  // no host: every network interface, IPv4 and IPv6 (so "localhost" is quick on Windows too)
  createServer()
    .listen(port)
    .then((p) => console.log(`Topout server on port ${p}. Check http://localhost:${p}/health`));
}
