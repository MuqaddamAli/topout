// Rooms and players, with no networking: index.js calls these and sends
// what they return. A room has a 4-letter code, up to 8 players, and a host
// (the creator, or the next player when the host leaves).
const crypto = require('crypto');

const MAX_PLAYERS = 8;
// one lane per two players (lib/game/core.dart builds the same wall from this)
const MAX_LANES = 4;
const lanesFor = (players) => Math.max(1, Math.min(MAX_LANES, Math.ceil(players / 2)));
// no I, L or O: they are easy to mix up with 1 and 0
const CODE_LETTERS = 'ABCDEFGHJKMNPQRSTUVWXYZ';
const ROUTES = ['first', 'steps', 'crimps', 'daily'];
const MODES = ['casual', 'normal', 'solo'];
const CLIMBERS = ['ada', 'rio', 'mei', 'kai'];

const Err = {
  notFound: 'Room not found',
  full: `Room is full (${MAX_PLAYERS}/${MAX_PLAYERS})`,
  started: 'This climb has already started',
  noName: 'Enter a name',
  notHost: 'Only the creator can start',
  bad: 'Something went wrong. Try again.',
};

/// Trims a name to at most 16 characters, with single spaces.
function cleanName(name) {
  if (typeof name !== 'string') return '';
  return name.replace(/\s+/g, ' ').trim().slice(0, 16);
}

/// Upper case, with spaces and dashes gone, so "ab cd" finds "ABCD".
function cleanCode(code) {
  return typeof code === 'string' ? code.toUpperCase().replace(/[^A-Z]/g, '') : '';
}

const randomId = (bytes) => crypto.randomBytes(bytes).toString('hex');

class Rooms {
  /// [graceMs]: how long a dropped player keeps their slot.
  /// [countdownMs]: time from Start to the climb, so everyone starts together.
  constructor({ graceMs = 20000, countdownMs = 3000 } = {}) {
    this.graceMs = graceMs;
    this.countdownMs = countdownMs;
    this.rooms = new Map();
  }

  newCode() {
    for (;;) {
      let code = '';
      for (let k = 0; k < 4; k++) code += CODE_LETTERS[crypto.randomInt(CODE_LETTERS.length)];
      if (!this.rooms.has(code)) return code;
    }
  }

  _player(room, name, climber) {
    const p = {
      id: randomId(4),
      token: randomId(16),
      name,
      climber: CLIMBERS.includes(climber) ? climber : 'ada',
      connected: true,
      // set at the start: the lane (0 is the first) and the side in it (0 left, 1 right)
      lane: null,
      side: null,
      code: room.code,
      timer: null,
    };
    room.players.set(p.id, p);
    return p;
  }

  /// Returns { room, player } or { error }.
  create({ name, route, mode, dateKey, climber } = {}) {
    name = cleanName(name);
    if (!name) return { error: Err.noName };
    if (!ROUTES.includes(route) || !MODES.includes(mode)) return { error: Err.bad };
    // the creator's day decides the Daily Wall for everyone in the room
    if (typeof dateKey !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) return { error: Err.bad };
    const room = { code: this.newCode(), route, mode, dateKey, host: null, started: false, players: new Map() };
    this.rooms.set(room.code, room);
    const player = this._player(room, name, climber);
    room.host = player.id;
    return { room, player };
  }

  join(code, { name, climber } = {}) {
    name = cleanName(name);
    if (!name) return { error: Err.noName };
    const room = this.rooms.get(cleanCode(code));
    if (!room) return { error: Err.notFound };
    if (room.started) return { error: Err.started };
    if (room.players.size >= MAX_PLAYERS) return { error: Err.full };
    return { room, player: this._player(room, name, climber) };
  }

  /// Takes a dropped slot back with the token given at create or join.
  /// Works after the start too.
  rejoin(code, token) {
    const room = this.rooms.get(cleanCode(code));
    if (!room) return { error: Err.notFound };
    for (const p of room.players.values()) {
      if (p.token === token) {
        clearTimeout(p.timer);
        p.timer = null;
        p.connected = true;
        return { room, player: p };
      }
    }
    return { error: Err.notFound };
  }

  roomOf(player) {
    return player ? this.rooms.get(player.code) : undefined;
  }

  pick(player, climber) {
    const room = this.roomOf(player);
    if (!room || room.started || !CLIMBERS.includes(climber)) return null;
    player.climber = climber;
    return room;
  }

  /// Returns { room } or { error }.
  start(player) {
    const room = this.roomOf(player);
    if (!room) return { error: Err.notFound };
    if (room.host !== player.id) return { error: Err.notHost };
    if (room.started) return { error: Err.started };
    room.started = true;
    room.startAt = Date.now() + this.countdownMs;
    // in the order they joined: the first gets lane 1 left, the next lane 1
    // right, then lane 2 left, and so on. The wall keeps this many lanes
    // even if someone leaves during the climb.
    room.lanes = lanesFor(room.players.size);
    let k = 0;
    for (const p of room.players.values()) {
      p.lane = Math.floor(k / 2);
      p.side = k % 2;
      k++;
    }
    return { room };
  }

  /// Takes the player out. Returns the room if it still has players.
  leave(player) {
    const room = this.roomOf(player);
    if (!room || !room.players.has(player.id)) return undefined;
    clearTimeout(player.timer);
    room.players.delete(player.id);
    if (room.players.size === 0) {
      this.rooms.delete(room.code);
      return undefined;
    }
    // the next player (in the order they joined) becomes the host
    if (room.host === player.id) room.host = room.players.keys().next().value;
    return room;
  }

  /// The connection dropped: keep the slot for a while, then call [onGone]
  /// with what [leave] returned.
  drop(player, onGone) {
    const room = this.roomOf(player);
    if (!room || !room.players.has(player.id)) return undefined;
    player.connected = false;
    clearTimeout(player.timer);
    player.timer = setTimeout(() => onGone(this.leave(player)), this.graceMs);
    player.timer.unref?.();
    return room;
  }

  /// What every player in the room is sent.
  view(room) {
    return {
      code: room.code,
      route: room.route,
      mode: room.mode,
      dateKey: room.dateKey,
      host: room.host,
      started: room.started,
      lanes: room.lanes ?? null,
      max: MAX_PLAYERS,
      players: [...room.players.values()].map((p) => ({
        id: p.id,
        name: p.name,
        climber: p.climber,
        connected: p.connected,
        lane: p.lane,
        side: p.side,
      })),
    };
  }
}

module.exports = { Rooms, Err, MAX_PLAYERS, MAX_LANES, lanesFor, CODE_LETTERS, ROUTES, MODES, CLIMBERS, cleanCode, cleanName };
