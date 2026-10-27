# Topout

A calm 2D climbing game for phones. You move one hand or foot at a time, watch your grip, rest on ledges and find your own way up the wall.

This is the Flutter version of the Topout web prototype (kept in `web_prototype/` for reference). The rules, routes, art, music and sounds are the same.

## What is in the game

- Three routes (easy, medium, hard) and a **Daily Wall**: a new endless wall every day, the same for everyone, that gets harder and snowier as you go up.
- Limb-by-limb climbing: drag a hand or foot to a hold. Big holds, small edges, round holds and foot steps all feel different.
- Grip: each hand gets tired on a hold and rests when you let go. Feet on the wall help your hands. Ledges let you rest and save your place (the lamp lights up).
- Jumps: a hand can jump to a hold that is a little too far, if a foot is on a hold. After the catch you must grab a second hold fast.
- Three modes: Relaxed, Normal, and No saves.
- After a fall, a card explains why you fell and shows your hand strength before the fall.
- Records: best time per route, highest point, today's best on the Daily Wall, and a log of tops, metres, falls and time.
- A climber drawn in code (helmet, ponytail, harness, quickdraws and chalk bag that swing), sunset clouds, mountains, birds, lamps and snow.
- Lofi music and sound effects, with wind that grows as you climb. Phones also buzz a little on grabs, slips and landings.

## Run it

You need Flutter 3.24 or newer.

```bash
flutter pub get
flutter run
```

The `android`, `ios` and `web` folders are included. If you ever need to rebuild one of them, run `flutter create . --platforms=android,ios,web --org com.muqaddamali --project-name topout`; it only adds missing files and does not change `lib/`.

The game is made for phones held upright (portrait). It also runs on the web and on desktop. On a desktop you can use the keyboard: **U** undo, **L** look, **Esc** pause.

## Tests

```bash
flutter test
```

- `test/core_test.dart` checks that the Dart rules build exactly the same walls as the web prototype and that the body moves the same way. The data comes from `tool/make_fixtures.js` (run it with Node.js).
- `test/game_flow_test.dart` plays a full climb with real touch drags (moves, undo, look, a fall, the top, the Daily Wall, pause) and saves screenshots to `build/screens/`.
- `test/widget_test.dart` is a quick start-up check.

Every push runs `.github/workflows/build.yml` on GitHub Actions. It analyzes the code, runs the tests, builds the web version and an Android APK, and uploads the APK (`topout-apk`), the web build (`topout-web`) and the test screenshots (`screenshots`) as downloads at the bottom of the run page, under **Actions**.

## How the code is laid out

| Path | What it does |
| --- | --- |
| `lib/game/core.dart` | Rules with no Flutter code: holds, the body solver, grip, jumps, route and Daily Wall builders, random numbers |
| `lib/game/game.dart` | Game state, the 60 Hz simulation, touch input, falls, saves, records, the climber's pose and swinging gear |
| `lib/game/scene.dart` | Paints the world: sky, clouds, mountains, rock, holds, ledges, lamps, aiming markers, particles |
| `lib/game/climber.dart` | Paints the climber (cel shading, seen from behind) |
| `lib/game/art.dart` | Art made once at start: rock texture, cloud sprites, stars, grass, rock facets |
| `lib/game/audio.dart` | Music, wind and sound effects (`audioplayers`), plus phone buzzes |
| `lib/game/store.dart` | Saves settings and records (`shared_preferences`) |
| `lib/ui/` | Flutter widgets: title screen, HUD, fall, top and pause cards |
| `assets/audio/` | Music and sounds (MP3) |
| `assets/fonts/` | Big Shoulders Display, Atkinson Hyperlegible, IBM Plex Mono (SIL Open Font License, see `assets/fonts/licenses`) |
| `web_prototype/` | The original web version (one HTML file) and its rules (`core.js`) |
| `tool/` | Scripts that make the test data and the sound files |

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
