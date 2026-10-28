// Fake players for testing a full room on one PC. They join a room, wait for
// the host to start, then climb up and down sending climber states 10 times
// a second, like a real game does.
//
//   npm run bots -- ABCD 7                          # 7 bots into room ABCD
//   npm run bots -- ABCD 7 http://192.168.1.5:3000  # another server
//   npm run bots -- ABCD 7 --top                    # straight up, no falls
//
// On a route with a top they tell the room their time there and walk to
// and fro on the top, so the top-out messages and the results can be tried;
// on the Daily Wall they keep going. After Play again they climb again.
//
// A climber state is one array (the server passes it on without reading it):
//   [t, climber, cx, cy, tilt, lookX, lookUp,
//    leftHandX, leftHandY, rightHandX, rightHandY, leftFootX, leftFootY, rightFootX, rightFootY,
//    bits, metres, secs]
// t is the sender's clock in ms, secs the seconds since the climb started,
// positions are world units (cm, y up), and
// bits packs: 0-1 left hand style (0 grip, 1 fist, 2 open), 2-3 right hand
// style, 4-6 left hand hold kind (0 jug, 1 crimp, 2 sloper, 3 chip, 4 ledge,
// 5 ground, 6 top), 7-9 right hand hold kind, 10 left foot free, 11 right
// foot free, 12 falling, 13 topped out, 14 standing on a flat hold (the
// others play the steps back from how the body moves), 15 facing left.
// While an emote plays, two more numbers follow secs: the emote (1 Cheer,
// 2 Taunt, 3 Aura) and when it started (ms, the same clock as t).
const { io } = require('socket.io-client');

const args = process.argv.slice(2);
// --top: climb straight up without falling, so the room reaches its results fast
const straightUp = args.includes('--top');
const [code, countArg, urlArg] = args.filter((a) => !a.startsWith('--'));
const url = urlArg || process.env.MP_SERVER || 'http://localhost:3000';
const count = Math.max(1, Math.min(7, Number(countArg) || 1));
if (!code) {
  console.log('Usage: npm run bots -- ROOMCODE [count] [server url] [--top]');
  process.exit(1);
}

const CLIMBERS = ['ada', 'rio', 'mei', 'kai'];
const round = (v, k = 10) => Math.round(v * k) / k;
const ORDER = [0, 3, 1, 2]; // left hand, right foot, right hand, left foot
const SIDE = [-1, 1, -1, 1];
// the height of the top of each route (lib/game/core.dart)
const TOPS = { first: 610, steps: 912, crimps: 1192 };
// where the spawns are (lib/game/core.dart, laneWall): a lane is 360 wide,
// every other lane is mirrored; [left, right] spawn in a lane and in a mirrored one
const LANE_WIDTH = 360;
// walking speed (cm/s) and the body's height when standing (lib/game/walk.dart)
const WALK_SPEED = 55, STAND_Y = 107.5;
// how long each emote plays (s); a bot's Aura (lying down) lasts a while too
const EMOTE_LENGTH = [0, 1.6, 2.2, 4];
const SPAWN_X = [[95, 267], [93, 265]];

/// Where a player of [lane] and [side] (0 left, 1 right) starts.
const spawnX = (lane, side) => lane * LANE_WIDTH + SPAWN_X[lane % 2][side];

/// One climber going up the wall at its own pace, now and then falling off.
class Climb {
  constructor(n) {
    this.x0 = spawnX(0, n % 2); // until the start says which lane
    this.speed = straightUp ? 30 + Math.random() * 15 : 12 + Math.random() * 10; // cm per second
    this.climber = CLIMBERS[n % CLIMBERS.length];
    this.top = null; // set from the room's route
    this.topped = false;
    this.reset();
  }

  reset() {
    // first a short walk along the ground, like a player choosing where to start
    this.walkLeft = 2 + Math.random() * 4;
    this.emote = 0;
    this.nextEmote = 1 + Math.random() * 3;
    this.walkDir = Math.random() < 0.5 ? -1 : 1;
    this.y = 100;
    this.fallV = null;
    this.limbs = [0, 1, 2, 3].map((i) => ({ ...this.ideal(i, 0), from: null, t: 1 }));
    this.next = 0;
    this.moveT = 0;
  }

  cx(t) {
    return this.x0 + Math.sin(t * 0.4 + this.x0) * 25;
  }

  /// Where limb [i] rests when the body is [ahead] cm higher than now.
  ideal(i, ahead, t = 0) {
    const hand = i < 2, x = this.cx(t) + SIDE[i] * (hand ? 22 : 16) + (Math.random() - 0.5) * 10;
    return { x, y: this.y + ahead + (hand ? 62 : -78) };
  }

  /// Now and then, while standing: Cheer, Taunt or Aura. Returns true while
  /// one plays (the bot stands still).
  emoting(t) {
    if (this.emote && t > this.emoteUntil) this.emote = 0;
    if (!this.emote && t > this.nextEmote) {
      this.emote = 1 + Math.floor(Math.random() * 3);
      this.emoteStart = Date.now();
      this.emoteUntil = t + EMOTE_LENGTH[this.emote];
      this.nextEmote = this.emoteUntil + 6 + Math.random() * 8;
    }
    return this.emote > 0;
  }

  update(dt, t) {
    if ((this.walkLeft > 0 || this.topped) && this.emoting(t)) return;
    if (this.topped) {
      // to and fro, up to a metre either way
      this.x0 += this.walkDir * WALK_SPEED * dt;
      if (Math.abs(this.x0 - this.walkHome) > 100) this.walkDir = -Math.sign(this.x0 - this.walkHome);
      return;
    }
    if (this.walkLeft > 0) {
      this.walkLeft -= dt;
      this.x0 += this.walkDir * WALK_SPEED * dt;
      return;
    }
    if (this.fallV != null) {
      this.fallV -= 980 * dt;
      this.y = Math.max(100, this.y + this.fallV * dt);
      for (const l of this.limbs) l.y = Math.max(0, l.y + this.fallV * dt);
      if (this.y <= 100 && this.fallV < -50) this.fallV *= -0.2;
      if ((this.fallT += dt) > 2) this.reset();
      return;
    }
    this.y += this.speed * dt;
    if (this.top != null && this.y + 62 >= this.top) {
      // on the top: the time goes to the room, then a stroll along the top
      this.topped = true;
      this.toppedAt = t;
      this.walkHome = this.x0;
      this.onTop?.(t);
      return;
    }
    // every limb moves in turn, a little ahead of the body
    if ((this.moveT += dt) > 0.7) {
      this.moveT = 0;
      const i = ORDER[this.next++ % 4], l = this.limbs[i];
      Object.assign(l, this.ideal(i, 30, t), { from: { x: l.x, y: l.y }, t: 0 });
    }
    for (const l of this.limbs) l.t = Math.min(1, l.t + dt / 0.35);
    if ((this.top == null && this.y > 2200) || (!straightUp && Math.random() < dt / 45)) {
      this.fallV = 0;
      this.fallT = 0;
    }
  }

  limbAt(i) {
    const l = this.limbs[i];
    if (!l.from || l.t >= 1) return l;
    const e = l.t * l.t * (3 - 2 * l.t);
    return { x: l.from.x + (l.x - l.from.x) * e, y: l.from.y + (l.y - l.from.y) * e + Math.sin(l.t * Math.PI) * 8 };
  }

  state(t) {
    if (this.walkLeft > 0 || this.topped) {
      // standing, walking: the hands hang, the feet are on the ground or the top
      const x = this.x0, y = this.topped ? this.top : 0, s = [Date.now(), this.climber, round(x), y + STAND_Y, 0, 0, 0.5];
      s.push(round(x - 31), y + 80, round(x + 31), y + 80, round(x - 12), y, round(x + 12), y);
      let bits = 2 | (2 << 2) | (5 << 4) | (5 << 7) | (1 << 14) | (this.walkDir < 0 ? 1 << 15 : 0);
      if (this.topped) bits |= 1 << 13;
      const st = [...s, bits, round(y / 100), round(this.topped ? this.toppedAt : t)];
      return this.emote ? [...st, this.emote, this.emoteStart] : st;
    }
    const falling = this.fallV != null;
    const moving = (i) => falling || (this.limbs[i].t < 1 && this.limbs[i].from);
    const style = (i) => (moving(i) ? 2 : 0);
    let bits = style(0) | (style(1) << 2);
    if (moving(2)) bits |= 1 << 10;
    if (moving(3)) bits |= 1 << 11;
    if (falling) bits |= 1 << 12;
    const cx = this.cx(t), tilt = Math.sin(t * 0.7 + this.x0) * 0.08;
    const s = [Date.now(), this.climber, round(cx), round(this.y), round(tilt, 1000), round(Math.sin(t * 0.35) * 1.2, 100), 0.5];
    for (let i = 0; i < 4; i++) {
      const p = this.limbAt(i);
      s.push(round(p.x), round(p.y));
    }
    s.push(bits, round((this.y - 100) / 100), round(t));
    return s;
  }
}

function bot(n) {
  const socket = io(url, { transports: ['websocket'], reconnection: false });
  const climb = new Climb(n);
  let timer = null;
  const name = `Bot ${n + 1}`;
  let you = null;
  climb.onTop = (secs) => {
    console.log(`${name}: topped out after ${Math.round(secs)} s`);
    socket.emit('topped', secs);
  };

  const go = (startsIn) =>
    setTimeout(() => {
      const t0 = Date.now();
      let last = t0;
      timer = setInterval(() => {
        const now = Date.now();
        climb.update((now - last) / 1000, (now - t0) / 1000);
        last = now;
        socket.emit('state', climb.state((now - t0) / 1000));
      }, 100);
    }, startsIn || 0);

  socket.on('connect', () => {
    socket.emit('join', { code, name, climber: climb.climber }, (r) => {
      if (r.error) {
        console.log(`${name}: ${r.error}`);
        socket.close();
        return;
      }
      you = r.you;
      climb.top = TOPS[r.room.route] ?? null;
      console.log(`${name} joined ${r.room.code} (${r.room.players.length}/${r.room.max})`);
    });
  });
  // from the start, the room says each player's lane and side: climb there
  socket.on('room', (room) => {
    const me = room.players.find((p) => p.id === you);
    if (!room.started || me?.lane == null || timer) return;
    climb.x0 = spawnX(me.lane, me.side);
    climb.reset();
    console.log(`${name}: lane ${me.lane + 1} ${me.side === 0 ? 'left' : 'right'} of ${room.lanes}`);
  });
  socket.on('started', ({ startsIn, round }) => {
    // a new climb (the first, or after Play again): from the ground again
    clearInterval(timer);
    timer = null;
    climb.topped = false;
    console.log(`${name}: climbing${round > 1 ? ` (climb ${round})` : ''}`);
    go(startsIn);
  });
  socket.on('connect_error', (e) => console.log(`${name}: cannot reach ${url} (${e.message})`));
  socket.on('disconnect', () => clearInterval(timer));
  return socket;
}

console.log(`${count} bot(s) joining ${code.toUpperCase()} on ${url}. Ctrl+C to stop.`);
const bots = [];
// one after another, so they come in in order
for (let n = 0; n < count; n++) setTimeout(() => bots.push(bot(n)), n * 150);
process.on('SIGINT', () => {
  for (const b of bots) b.close();
  process.exit(0);
});
