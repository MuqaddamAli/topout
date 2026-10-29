# Topout

A calm 2D climbing game for phones. You move one hand or foot at a time, watch your grip, rest on ledges and find your own way up the wall.

This is the Flutter version of the Topout web prototype (kept in `web_prototype/` for reference). The rules, routes and art are the same; the music and sounds were made anew (see Sounds and music).

## What is in the game

- Four climbers to pick from (see below). Each is good at something different, and nobody is best at everything.
- Three routes (easy, medium, hard) and a **Daily Wall**: a new endless wall every day, the same for everyone, that gets harder and snowier as you go up.
- Limb-by-limb climbing: drag a hand or foot to a hold. Big holds, small edges, round holds and foot steps all feel different.
- Grip: each hand gets tired on a hold and rests when you let go. Feet on the wall help your hands. Ledges let you rest and save your place (the lamp lights up).
- Jumps: a hand can jump to a hold that is a little too far, if a foot is on a hold. After the catch you must grab a second hold fast.
- Catch a fall: when you lose your hold, time slows for a moment and every hold within reach on the way down glows. Tap one (or press Space) and your hand snatches it, then the body swings under it and you have a second or two to get a foot or the other hand on. The longer you fell, the more grip the catch costs: green holds leave you plenty, yellow ones little, and red ones are too much for a tired hand (the fingers slip off). Each fall gets one chance, so a fall out of the hang after a catch is final. The moment lasts longest in Relaxed and is shortest in No saves.
- Three modes: Relaxed, Normal, and No saves.
- Online play: up to 8 players, each on their own device, climb the same wall at the same time and see each other live. The wall gets one lane per two players, with bridges between the lanes. Online you can walk along the ground, ledges and the top, wait for friends, cheer, taunt or lie back to show off, say a few set phrases, and watch the others once you are up; the room sees everyone's times at the end and can play again (see Online play).
- After a fall, a card explains why you fell and shows your hand strength before the fall.
- Records: best time per route, highest point, today's best on the Daily Wall, and a log of tops, metres, falls (and how many you caught) and time.
- A climber drawn in code (helmet, ponytail, harness, quickdraws and chalk bag that swing), sunset clouds, mountains, birds, lamps and snow.
- Calm music (electric piano, a soft pad, bass and kalimba, no drums) and soft sound effects in the same key, with wind that grows as you climb. Phones also buzz a little on grabs, slips and landings.
- Soft animations everywhere: cards and tips slide in, buttons press in, holds give a little when you grab them, lamps send out a ring of light, grass sways, dust floats in the evening light, the hand gauges pulse when a hand is about to slip, and the end-of-climb numbers count up. All of it turns off when the phone asks for less motion.

## Climbers

Pick a climber on the title screen. Each has four stats from 1 to 5 that always add up to 12, plus one perk. Stat 3 is the original game; each point moves one number a small step.

| Climber | Good at | Reach | Grip | Rest | Jump | Perk |
| --- | --- | --- | --- | --- | --- | --- |
| Ada | All-rounder | 3 | 3 | 3 | 3 | **Calm**: grip lasts longer while you aim |
| Rio | Long reach | 5 | 2 | 3 | 2 | **Strong arm**: hanging on one hand costs less grip |
| Mei | Small holds | 2 | 4 | 4 | 2 | **Strong fingers**: small edges tire the hands less |
| Kai | Jumper | 3 | 2 | 2 | 5 | **Free jump**: can jump with no feet on the wall, even right after a catch |

- **Reach**: arm and leg length (3 cm per point). Longer limbs are also drawn longer, and reach further for a hold when you fall.
- **Grip**: how slowly a hand tires on a hold (10% per point).
- **Rest**: how fast a hand gets its grip back (15% per point).
- **Jump**: how far a jump goes (10 cm per point), how long you have to grab a second hold after it, and how much grip a catch costs, after a jump or in a fall.

`test/balance_test.dart` checks that this stays fair: a small bot climbs every route with every climber using the real rules, and the test fails if one climber cannot reach the top or needs a lot more moves than the others. Best times remember who set them.

## Run it

You need Flutter 3.24 or newer.

```bash
flutter pub get
flutter run
```

The `android`, `ios` and `web` folders are included. If you ever need to rebuild one of them, run `flutter create . --platforms=android,ios,web --org com.mw --project-name topout`; it only adds missing files and does not change `lib/`.

The game is made for phones held upright (portrait). It also runs on the web and on desktop. On a desktop you can use the keyboard: **U** undo, **L** look, **Space** catch a hold while falling, **Esc** pause or back, **Enter** try again or go on. Online there is more: **A/D** or the arrows walk, **1 2 3** emote, **Q W E R** quick chat, **Tab** watch (see docs/MULTIPLAYER.md).

## Online play

Tap **Play online**, make a room and send its 4-letter code to friends; up to 8 players climb the same route together, each on their own device. The wall has one lane per two players (up to 4 lanes side by side, each a copy of the route, every other one mirrored, with bridges to cross between them); each player starts standing at their own spot in their lane and can walk before climbing. Reaching the top stops your time but not the climb: you stand on the top, and the room's results show when everyone is up or the creator ends it, with Play again. Emotes, quick chat bubbles, arrows to friends out of view, Watch after the top and a Ready check in the lobby make it social. Online climbs are not saved in the records. The game talks to a small Node.js server in `server/`. The live site uses the server at `https://topout.onrender.com`; a page opened on `localhost` or the local network uses port 3000 of the same machine, and a build can set another address with `--dart-define=MP_SERVER=...`.

[docs/MULTIPLAYER.md](docs/MULTIPLAYER.md) has the exact steps: trying it on one PC with bots, with phones on the same Wi-Fi, and putting the server on Render's free plan.

## Tests

```bash
flutter test
```

- `test/core_test.dart` checks that the Dart rules build exactly the same walls as the web prototype and that the body moves the same way. The data comes from `tool/make_fixtures.js` (run it with Node.js).
- `test/balance_test.dart` climbs every route with every climber (see Climbers).
- `test/game_flow_test.dart` plays a full climb with real touch drags (moves, undo, look, a fall, the top, the Daily Wall, pause), catches falls (a tap, the Space key, a hang that runs out, a hand too tired to hold on), picks each climber and climbs with them, and saves screenshots to `build/screens/`.
- `test/widget_test.dart` is a quick start-up check.
- `test/lanes_test.dart` checks the wall with lanes: one lane is the route itself, every lane has the same holds, the spawns and bridges, the same wall every time, and the balance bot climbs every lane (from both spawns) as well as the route on its own.
- `test/wide_wall_test.dart` climbs alone on a wall with lanes: the camera across the lanes and over a bridge, Look, and screenshots (`build/screens/4x_*`).
- `test/walk_test.dart` stands and walks online (alone on a wall with lanes): keys and a finger, the wall's edges, ledges and their ends, the first grab, undo and falls; `test/emote_test.dart` the emotes, their cooldown and poses; `test/social_test.dart` quick chat, name tags and bubbles, friend arrows, Watch, the ready check and coming back after a dropped connection.
- `test/online_test.dart` tries the Play online screen and the lobby against a fake server, and `test/remote_test.dart` the climber states sent over the network, playing other climbers back smoothly, the heights list, the messages and a whole online climb.
- `cd server` and `npm test` checks the room server: making and joining rooms, the errors, the creator leaving and reconnecting, the lanes given out at the start, Ready, top-outs, results and Play again, and the emote and chat limit.

Every push runs `.github/workflows/build.yml` on GitHub Actions. It analyzes the code, runs the tests, builds the web version and an Android APK, and uploads the APK (`topout-apk`), the web build (`topout-web`) and the test screenshots (`screenshots`) as downloads at the bottom of the run page, under **Actions**.

## Web version on Vercel

The web build runs on [Vercel](https://vercel.com). `vercel.json` tells Vercel to run `tool/vercel_build.sh`, which fetches a pinned Flutter release (Vercel has none), builds `build/web` with WebAssembly (and a JavaScript fallback for older browsers), and drops the engine's debug symbols. Every push to the connected GitHub repository makes a new deployment.

The site is served cross-origin isolated (the `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers in `vercel.json`), so the WebAssembly renderer can draw on a separate thread. The engine files are served with the game for the same reason. While the game loads, `web/index.html` shows a small splash, and `web/flutter_bootstrap.js` fades it out on the first frame.

To build the same thing on your own machine: `bash tool/vercel_build.sh` (set `FLUTTER_ROOT` to use a Flutter you already have), then serve `build/web` with the same two headers.

## How the code is laid out

| Path | What it does |
| --- | --- |
| `lib/game/core.dart` | Rules with no Flutter code: holds, the body solver, grip, jumps, the climbers and their stats, route and Daily Wall builders, the wall with lanes for online rooms, random numbers |
| `lib/game/game.dart` | Game state, the 60 Hz simulation, touch input, falls and saves |
| `lib/game/records.dart` | Best heights and times per route and mode, and the climbing log |
| `lib/game/effects.dart` | Things that move by themselves, only for show: particles, dust in the light, birds |
| `lib/game/body.dart` | The climber's body: pose, arms and legs (two-bone IK, scaled to each climber's reach), and the gear that swings |
| `lib/game/scene.dart` | Paints the world: sky, clouds, mountains, rock, holds, ledges, lamps, aiming markers, particles, dust |
| `lib/game/climber.dart` | Paints a climber (cel shading, seen from behind) in their colours and hair style |
| `lib/game/art.dart` | Art made once: the rock texture (with its facets), cloud sprites, stars, grass |
| `lib/game/baked.dart` | `Baked`: a drawing turned into an image once, so drawing it again is cheap (see Keeping it fast) |
| `lib/game/audio.dart` | Music, wind and sound effects: when and how loud, plus phone buzzes |
| `lib/game/audio_engine*.dart` | Plays the files: one Web Audio graph in browsers, `audioplayers` on phones and desktops |
| `lib/game/store.dart` | Saves settings and records (`shared_preferences`) |
| `lib/game/online.dart` | Online play: the connection to the room server, the room and the lobby |
| `lib/game/remote.dart` | Other players' climbers: the state sent over the network, played back smoothly |
| `lib/game/walk.dart` | Online: standing and walking on flat holds, the emotes, the quick chat phrases |
| `lib/ui/` | Flutter widgets: title screen and climber picker, Play online and the lobby, HUD, fall, top, pause and room results cards |
| `server/` | The room server for online play (Node.js and Socket.io), with bots for testing |
| `docs/MULTIPLAYER.md` | How to test online play and put the server online |
| `assets/audio/` | Music and sounds (MP3) |
| `assets/fonts/` | Big Shoulders Display, Atkinson Hyperlegible, IBM Plex Mono (SIL Open Font License, see `assets/fonts/licenses`) |
| `web_prototype/` | The original web version (one HTML file) and its rules (`core.js`) |
| `tool/` | Scripts that make the test data and the sound files, and the Vercel build script |

### Keeping it fast

On the web every layer is drawn again each frame (there is no raster cache), so the game avoids work that costs per pixel or per draw call:

- Art that never changes is drawn once into an image and then stamped: the rock texture (one textured rectangle covers the wall), the clouds, every kind of hold (all holds in view are one `drawRawAtlas` call), the climber's torso, shoes and bag, and the portraits and route maps on the title screen (`CachedPaint` in `lib/ui/widgets.dart`). On the web, the image `toImageSync` gives would be drawn again from its picture every time, so `Baked` (`lib/game/baked.dart`) reads its pixels back once and keeps a plain image. The web engine reads back on the same surface it draws frames on, so `Baked` packs the waiting images into one read-back exactly the size of the frame (then the surface is never resized under a frame), and checks a marker pixel to know nothing was clipped.
- No blurs: shadows and glows are flat or soft strokes. The mountains are one fill each and stop just under the summit (big anti-aliased paths are slow). The climber is recorded once and drawn twice, as the shadow (a layer only as big as the climber) and for real.
- Particles and dust are drawn in a few batches (`drawRawPoints`), and only holds near the view are looked at (`ClimbRoute.byY`).
- The web build draws at most 2 pixels per CSS pixel (`web/index.html`), and nothing behind a card that covers the screen is updated.
- The HUD is not rebuilt every frame. Each number on it (height, time, grip) rebuilds only when the shown value changes (`FrameSelect` in `lib/ui/hud.dart`).
- On the web, the sound effects are decoded once and played from memory through a single `AudioContext`.

- A wall with lanes costs the same per frame as one lane: ledges and the long top are only drawn near the view, like the holds.
- Other players' climbers are drawn the cheap way (flat colours, no cel bands, no small gear), and the ones far outside the view are skipped. Their walking is played back from how the body moves (no extra data), name tags, bubbles and arrow labels are laid out once per text and kept, and a full room of 8 walking, emoting and chatting measured about 140 fps (build 2–3 ms, raster 6–7 ms) on a laptop.

To measure, open the web build with `?perf` (frame times in the browser console every 2 s) or `?perf=steps` to also start that route (`first`, `steps`, `crimps`, `daily`). `?perf=online` makes a room and prints the command that fills it with bots; it starts by itself when 8 climbers are in (see docs/MULTIPLAYER.md). In a profile build (`flutter run -d chrome --profile`), `?perf=steps&lanes=4` measures a route on a wall with 4 lanes (`?lanes` works in debug and profile builds only).

### Units

World units are centimetres with y pointing up. The ground is at y = 0, and 100 units are one metre. The painter flips y when it draws.

## Sounds and music

`tool/make_audio.py` makes every file in `assets/audio/`. It is all synthesis in numpy, with no samples and no noise floor, so every sound fades to true silence. Sounds with a pitch use notes from the music's key (D major), so they sit well with it. The online emotes have their own soft cues (`emote_cheer`, `emote_taunt`, `emote_aura`): a little rising leap, a playful "ha-ha-ha" and a slow, relaxed swell. The music is a 24-bar loop at 66 bpm: electric-piano chords, a soft pad, a gentle bass and a few kalimba notes. Its reverb tail wraps around to the start, so it loops without a seam.

```bash
pip install numpy          # ffmpeg (with MP3 support) is also needed
python tool/make_audio.py              # everything (about a minute)
python tool/make_audio.py grab foot    # only the files whose names start so
```

The files are balanced against each other; `GameAudio` in `lib/game/audio.dart` sets the music and wind under them and gives each effect its own level (`Sfx`).
