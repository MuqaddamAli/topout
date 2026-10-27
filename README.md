# Topout

A calm 2D climbing game for phones. You move one hand or foot at a time, watch your grip, rest on ledges and find your own way up the wall.

This is the Flutter version of the Topout web prototype (kept in `web_prototype/` for reference). The rules, routes, art, music and sounds are the same.

## What is in the game

- Four climbers to pick from (see below). Each is good at something different, and nobody is best at everything.
- Three routes (easy, medium, hard) and a **Daily Wall**: a new endless wall every day, the same for everyone, that gets harder and snowier as you go up.
- Limb-by-limb climbing: drag a hand or foot to a hold. Big holds, small edges, round holds and foot steps all feel different.
- Grip: each hand gets tired on a hold and rests when you let go. Feet on the wall help your hands. Ledges let you rest and save your place (the lamp lights up).
- Jumps: a hand can jump to a hold that is a little too far, if a foot is on a hold. After the catch you must grab a second hold fast.
- Three modes: Relaxed, Normal, and No saves.
- After a fall, a card explains why you fell and shows your hand strength before the fall.
- Records: best time per route, highest point, today's best on the Daily Wall, and a log of tops, metres, falls and time.
- A climber drawn in code (helmet, ponytail, harness, quickdraws and chalk bag that swing), sunset clouds, mountains, birds, lamps and snow.
- Lofi music and sound effects, with wind that grows as you climb. Phones also buzz a little on grabs, slips and landings.
- Soft animations everywhere: cards and tips slide in, buttons press in, holds give a little when you grab them, lamps send out a ring of light, grass sways, dust floats in the evening light, the hand gauges pulse when a hand is about to slip, and the end-of-climb numbers count up. All of it turns off when the phone asks for less motion.

## Climbers

Pick a climber on the title screen. Each has four stats from 1 to 5 that always add up to 12, plus one perk. Stat 3 is the original game; each point moves one number a small step.

| Climber | Good at | Reach | Grip | Rest | Jump | Perk |
| --- | --- | --- | --- | --- | --- | --- |
| Ada | All-rounder | 3 | 3 | 3 | 3 | **Calm**: grip lasts longer while you aim |
| Rio | Long reach | 5 | 2 | 3 | 2 | **Strong arm**: hanging on one hand costs less grip |
| Mei | Small holds | 2 | 4 | 4 | 2 | **Strong fingers**: small edges tire the hands less |
| Kai | Jumper | 3 | 2 | 2 | 5 | **Free jump**: can jump with no feet on the wall, even right after a catch |

- **Reach**: arm and leg length (3 cm per point). Longer limbs are also drawn longer.
- **Grip**: how slowly a hand tires on a hold (10% per point).
- **Rest**: how fast a hand gets its grip back (15% per point).
- **Jump**: how far a jump goes (10 cm per point), how long you have to grab a second hold after it, and how much grip the catch costs.

`test/balance_test.dart` checks that this stays fair: a small bot climbs every route with every climber using the real rules, and the test fails if one climber cannot reach the top or needs a lot more moves than the others. Best times remember who set them.

## Run it

You need Flutter 3.24 or newer.

```bash
flutter pub get
flutter run
```

The `android`, `ios` and `web` folders are included. If you ever need to rebuild one of them, run `flutter create . --platforms=android,ios,web --org com.muqaddamali --project-name topout`; it only adds missing files and does not change `lib/`.

The game is made for phones held upright (portrait). It also runs on the web and on desktop. On a desktop you can use the keyboard: **U** undo, **L** look, **Esc** pause or back, **Enter** try again or go on.

## Tests

```bash
flutter test
```

- `test/core_test.dart` checks that the Dart rules build exactly the same walls as the web prototype and that the body moves the same way. The data comes from `tool/make_fixtures.js` (run it with Node.js).
- `test/balance_test.dart` climbs every route with every climber (see Climbers).
- `test/game_flow_test.dart` plays a full climb with real touch drags (moves, undo, look, a fall, the top, the Daily Wall, pause), picks each climber and climbs with them, and saves screenshots to `build/screens/`.
- `test/widget_test.dart` is a quick start-up check.

Every push runs `.github/workflows/build.yml` on GitHub Actions. It analyzes the code, runs the tests, builds the web version and an Android APK, and uploads the APK (`topout-apk`), the web build (`topout-web`) and the test screenshots (`screenshots`) as downloads at the bottom of the run page, under **Actions**.

## Web version on Vercel

The web build runs on [Vercel](https://vercel.com). `vercel.json` tells Vercel to run `tool/vercel_build.sh`, which fetches a pinned Flutter release (Vercel has none), builds `build/web` with WebAssembly (and a JavaScript fallback for older browsers), and drops the engine's debug symbols. Every push to the connected GitHub repository makes a new deployment.

The site is served cross-origin isolated (the `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers in `vercel.json`), so the WebAssembly renderer can draw on a separate thread. The engine files are served with the game for the same reason. While the game loads, `web/index.html` shows a small splash, and `web/flutter_bootstrap.js` fades it out on the first frame.

To build the same thing on your own machine: `bash tool/vercel_build.sh` (set `FLUTTER_ROOT` to use a Flutter you already have), then serve `build/web` with the same two headers.

## How the code is laid out

| Path | What it does |
| --- | --- |
| `lib/game/core.dart` | Rules with no Flutter code: holds, the body solver, grip, jumps, the climbers and their stats, route and Daily Wall builders, random numbers |
| `lib/game/game.dart` | Game state, the 60 Hz simulation, touch input, falls, saves, records |
| `lib/game/body.dart` | The climber's body: pose, arms and legs (two-bone IK, scaled to each climber's reach), and the gear that swings |
| `lib/game/scene.dart` | Paints the world: sky, clouds, mountains, rock, holds, ledges, lamps, aiming markers, particles, dust |
| `lib/game/climber.dart` | Paints a climber (cel shading, seen from behind) in their colours and hair style |
| `lib/game/art.dart` | Art made once: rock texture, cloud sprites, stars, grass, and per route the rock facets (merged into a few paths) and a height index of the holds |
| `lib/game/audio.dart` | Music, wind and sound effects (`audioplayers`), plus phone buzzes |
| `lib/game/store.dart` | Saves settings and records (`shared_preferences`) |
| `lib/ui/` | Flutter widgets: title screen and climber picker, HUD, fall, top and pause cards |
| `assets/audio/` | Music and sounds (MP3) |
| `assets/fonts/` | Big Shoulders Display, Atkinson Hyperlegible, IBM Plex Mono (SIL Open Font License, see `assets/fonts/licenses`) |
| `web_prototype/` | The original web version (one HTML file) and its rules (`core.js`) |
| `tool/` | Scripts that make the test data and the sound files, and the Vercel build script |

### Keeping it fast

- The HUD is not rebuilt every frame. Each number on it (height, time, grip) rebuilds only when the shown value changes (`FrameSelect` in `lib/ui/hud.dart`).
- The rock facets of a route are merged into a few paths per band of rows, each hold is drawn once into a picture and then stamped, and only holds in view are looked at.
- Gradients that only depend on the screen size or the route are made once.

### Units

World units are centimetres with y pointing up. The ground is at y = 0, and 100 units are one metre. The painter flips y when it draws.

## Sounds and music

All sounds are made by a small synth (Web Audio) in `web_prototype/topout.html`. `tool/render_audio.py` plays that synth in headless Chromium and saves the result as MP3, so the app plays exactly the same sounds:

```bash
pip install playwright numpy && playwright install chromium   # ffmpeg is also needed
python tool/render_audio.py          # sound effects and wind
python tool/render_audio.py music    # the 32-bar music loop (takes a few minutes)
```

## Before you publish to the stores

- The app id is `com.muqaddamali.topout`. Change it if you want a different one before your first upload.
- Make an app icon and a splash screen.
- Set up release signing for Android (`android/key.properties`) and a team for iOS.
