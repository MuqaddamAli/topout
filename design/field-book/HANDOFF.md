# Field Book & Rack: the new look for Topout

This folder is a design handoff. It changes how Topout looks, not how it plays. Every rule, number and system in `lib/game/core.dart` and `lib/game/game.dart` stays as it is.

The idea in one line: **every piece of UI is something a climber would carry.** Field-book paper, typewritten log lines, pencil notes, orange webbing, chalk on the rock, a rope sling with gear on it, ink stamps.

Three rules sit under everything:

1. **The UI is gear.** Paper, webbing, chalk, rope. Nothing floats on screen that you couldn't pack.
2. **The mountain owns colour.** Sky and rock change with height and time of day. The kit never does.
3. **Read it mid-move.** Shape says it before colour does, so it works for colour-blind players too.

## What is in this folder

| Path | What it is |
| --- | --- |
| `design/field-book/HANDOFF.md` | This file |
| `design/field-book/mockups/*.dc.html` | The mockups, one file per screen (see "Reading the mockups") |
| `design/field-book/mockups/Main.dc.html` | The system sheet: colours, the 16 mountain palettes, type, components |
| `design/field-book/tokens.json` | Every colour, palette and size as data |
| `design/field-book/screens/` | PNG exports of the mockups, if the owner added them. Use them to compare. |
| `lib/game/field_book.dart` | Ready Dart: `Kit` colours, `Env` palettes, frost and night tables, `FbTxt` styles, the grip halo, tally marks and the bar-tack stitch. It has not been compiled yet: run `flutter analyze` first. |
| `assets/fonts/` | Archivo ExtraCondensed Black (a static cut at width 62, weight 900), Courier Prime Regular and Bold, Reenie Beanie, with their OFL licences |

## Before you start

- Follow `CLAUDE.md` in the repository root, above all the authorship rules: no AI credit anywhere, no trailers.
- Work on a branch, for example `ui-field-book`. Do not push or open a pull request unless the owner asks.
- Keep the rules in README.md, "Keeping it fast". **No blurs**, art that never changes is drawn once (`Baked`, `CachedPaint`), and particles stay in batches. The mockups use browser filters (noise, lighting, drop shadows) to look textured. In Flutter, every one of those becomes a baked image or a flat shape (see "Making it fast").
- Keep everything that turns off under reduced motion turned off.
- Keep every `Semantics` label. Keep touch targets at 44 px or more.
- After each phase: `flutter analyze`, `flutter test`, then look at the screenshots in `build/screens/` next to the mockups.

## Reading the mockups

Each `.dc.html` file is one screen from a design tool. Open it in a text editor, not a browser (it needs the tool's runtime to draw). The parts that matter:

- The markup inside `<x-dc>` is plain HTML and SVG at a fixed size: 390×844 for phone, 1440×900 for desktop. Every position, size, colour and font size is written inline in `style="…"` or as SVG attributes. Those numbers are the source of truth.
- `{{name}}` is a value filled in by `renderVals()` in the `<script>` at the bottom. That script holds the palette tables, the halo maths, the limb positions and the tally maths.
- `data-props` lists the switches the designer used (zone, time of day, stamina, outcome). They tell you which states a screen has.
- `<sc-for>` repeats, `<sc-if>` shows one branch. `onClick` handlers only fake the interactions (picking a limb, picking a route).

### Sample content: do not copy it

The mockups were drawn before the design was checked against this codebase, so they show things Topout does not have. Use them for **looks only**. Leave out:

- food and water, rations, pitons, chalk counts, the backpack, temperatures, "day 2", bivouac days;
- heights in thousands of metres (Topout walls are measured in metres climbed);
- the route names, grades per pitch, route notes, water and rockfall symbols, "[mountain name]", "summit register book 3", and the made-up log lines.

Put the game's real data in the same places (see each screen). `[Game title]` is **TOPOUT**.

## Tokens and type

### Colours

`lib/game/field_book.dart` has the `Kit` class (colours that never change) next to the existing `Pal`. Move widgets from `Pal` to `Kit` as you restyle them. Leave the climbers' own colours (`Look`, `Body`) alone.

| Today (`Pal`) | Becomes (`Kit`) | Where |
| --- | --- | --- |
| `signal` #ff7a2f | `webbing` #FF5B1F | the main action, selected things, the active limb |
| `chalk` #f2ede4 (text on dark) | `ink` #1B2230 on paper, `blazeWhite` #F4F1E8 on rock | text |
| `ink`, `ink2`, `ink3` (dark panels) | `paper`, `card`, `register` | cards and panels become paper |
| `good` / `weak` / `bad` | chalk shapes first: ring, broken ring, cross. Colour tint second. | aiming, catch-a-fall |
| `bad` | `blaze` #C42A1C on paper, `low` #E0412F on rock | falls, a weak hand |
| `lamp` | keep | lamps and saves |

Contrast: ink on paper 12.8:1, ink on webbing 5.1:1, graphite on paper 5.5:1, chalk or blazeWhite on every rock colour 6.7:1 or more.

### Fonts

1. The files are already in `assets/fonts/`. Add them to `pubspec.yaml`:

   ```yaml
   - family: ArchivoXC
     fonts:
       - asset: assets/fonts/Archivo-ExtraCondensedBlack.ttf
         weight: 900
   - family: CourierPrime
     fonts:
       - asset: assets/fonts/CourierPrime-Regular.ttf
       - asset: assets/fonts/CourierPrime-Bold.ttf
         weight: 700
   - family: Reenie
     fonts:
       - asset: assets/fonts/ReenieBeanie-Regular.ttf
   ```

2. Add the same three to `test/fonts.dart`, or test labels turn into squares and stop fitting.
3. Keep the `Txt` API so call sites keep working, and change what is inside it:
   - `Txt.display` → ArchivoXC, weight 900, height 0.9, always uppercase;
   - `Txt.mono` → CourierPrime;
   - `Txt.eyebrow` → CourierPrime bold, tracked 0.08 to 0.14, uppercase.
4. `Txt.body` stays **Atkinson Hyperlegible** for sentences: tips, how-to, the fall card's "why" and "fix". Reenie Beanie is for one to four words only, never below 30 px, and never the only place a piece of information appears.
5. When nothing else uses Big Shoulders and Plex Mono any more, remove them.

`FbTxt` in `field_book.dart` has the three styles ready.

## The mountain: colour by height and hour

`Env.of(zone, time)` gives six colours: sky top, sky low, far ridge, near ridge, rock, holds. There are 4 zones × 4 hours; `Main.dc.html` §2 shows all 16.

- **Zone** comes from progress up the route: `zoneAt(climberHeight / progSpan)`. 0–25% valley, 25–50% cliff band, 50–75% icefall, 75–100% summit ridge. Blend across about 5% on each side of a boundary with `Env.lerp`, so the sky never jumps. For the Daily Wall, use the snow line: icefall from `snowY`, summit ridge a fixed distance above it.
- **Time of day** does not exist in Topout yet. Put it behind one function so the owner can change it in one place. Until the owner decides, use: easy route at day, medium at dusk, hard at night, and the Daily Wall at dawn.
- **What changes in `scene.dart`:** `_sky` uses `Env` instead of the fixed sunset colours. The sun and moon use `skyLights(t)`. Star brightness is multiplied by `skyLights(t).stars`. The mountain ranges use `far` and `near`. The rock texture from `art.dart` is tinted with `rock` (see "Making it fast"). Hold highlights use `hold`.
- **Mist:** one soft band between the far and near ridges, the colour of `skyLow` at 0 → 0.6 → 0 alpha, drifting about 50 px over 20 s.
- **Snow:** the falling particles already used on the Daily Wall also fall in the icefall and summit ridge zones.
- **Frost:** one rectangle with a radial gradient, clear in the middle and `Kit.frost` → `Kit.frostEdge` at the edges. Its opacity is `frostAt(zone, time)`.
- **Headlamp at night:** one rectangle with a radial gradient over the scene. It is clear for 80 px around a point between the climber's head and the hold being aimed at, then fades to `Kit.darkness` at 250 px (at phone scale). A second gradient adds a warm `lampWarm` glow at 22% in the middle. Opacity is `nightAt(time)`. The HUD sits above both layers.
- **Trail blazes:** a red-white-red painted mark (three bars, 24×7 each at phone scale) on the rock now and then, like route paint.

## Components

`Main.dc.html` §4 shows each one. The sizes are also in `tokens.json` → `components`.

### Webbing strap: the one thing to do next

Replaces `GameButton(primary: true)`. Use one per screen.

- Fill `Kit.webbing`, with a weave of 1 px lines every 3 px (`Kit.weave`) and darker 5 px rails along the top and bottom edges (`Kit.webbingEdge`).
- Square corners. The right end is cut on a slant: 12 px on phone, 14–16 px on desktop.
- On the left end, a bar-tack stitch: `bartackPath`, 24×40, 1.7 px, `Kit.bartack`.
- The label is `FbTxt.label` at 34–46 px in ink. Small extra text sits on the right in `FbTxt.typed(13–15, bold)`.
- The shadow is a flat darker copy offset 0, 6–8 px, with no blur.
- Pressed: fill `webbingDown`, and it moves down 4 px (keep `PressScale`).
- Height 64 px on phone, 70 px on desktop.

### Index line: everything else in a menu

Replaces `GameButton` (not primary) on paper. A two-digit number (`02`, `03`) in typed bold 14, then the label in `FbTxt.label` 30–34 px. Minimum height 48 px. No box; an underline appears on hover or focus.

### Paper scrap

Replaces `GamePanel` and the dark cards on the scene.

- Field-book paper with a 11–12 px grid (`Kit.gridScrap`).
- Rotated −2.5° to 2°.
- A torn bottom edge: a zigzag clip about 4% high.
- A strip of tape (`Kit.tape`, 64–90×20, rotated about 3°) over the top edge.
- Flat shadow.
- At night it gets a little darker (multiply about 0.82), because it is real paper in the dark.

### Luggage tag: Pause

A paper tag hanging on a string from the top edge. 56×72 on phone, 64×92 on desktop. The corners are cut (24% × 20%), there is a 14 px eyelet, and two 4.5 px pause bars. It sways 2–5° over 5 s; no sway under reduced motion. On desktop it says `ESC`.

### Chalk marks: aiming and catch-a-fall

These replace the aiming markers in `scene.dart` and the glowing holds when you catch a fall.

- **Shape by `Quality`:** `chalkMarkFor`. Good is a full ring (rx 24, ry 20, 4 px). Weak is a broken ring (dashes 11 on 8). No is a cross (two 34 px strokes).
- **Colour:** `Kit.chalk`. A light tint of good, weak or bad is fine on top, but the shape is what carries the meaning.
- **Word:** `chalkWord(holdType)` in `FbTxt.hand(36, color: Kit.chalk)`, rotated −7°, placed away from the climber. It uses climbing words: "jug!", "crimp", "sloper?", "foot", "ledge", "top!". For a hold that is too far, use a cross and the word "too far".
- **Drag line:** the path from the limb to the hold is chalk dots (2 on 8, 3.5 px), slowly moving along it.
- **Limbs:** the selected limb gets a webbing-orange ring (21 px, 4 px) and a thin second ring at 27 px. Idle limbs get a faint dotted chalk ring (17 px, dots 2 on 6, 60% opacity).
- **Old chalk:** chalked holds can carry short chalk tick marks underneath them, the way real climbers mark holds. `g.chalked` already exists.
- **Grain:** the chalk is grainy in the mockups. Bake each mark and each word once, with a noise mask, then stamp them.

### Grip halo: per-hand strength above the helmet

Replaces the two `_Gauge` circles as the main gauge. The mockups show one stamina ring; Topout has a grip value for each hand, so the ring is split:

- `Halo.hand(head, radius, hand: 0 or 1, grip: g.grip[hand])`.
- Ten segments from −160° to −20° with 3° gaps. The five on the left are the left hand, the five on the right are the right hand. Radius 34 at phone scale, 5.5 px stroke.
- Lit segments are `Kit.webbing`, dim ones are chalk at 32%. It follows the head in screen space, so the eyes never leave the climber.
- When a hand is below 30 and holding on (the existing `_low` rule), its half turns `Kit.low` and pulses over 0.8 s (no pulse under reduced motion).
- Keep the numbers too: they move to small paper tags at the two ends of the rack ("L 72", "R 64"), and the `Semantics` labels stay as they are.

### Altimeter tape: height and progress

Replaces the height number, the time line and `_Progress` in the top bar.

- A strip down the left edge, 46 px wide on phone and 62 px on desktop, filled with `Kit.shade`.
- Ticks every metre, a label every 5 metres, about 12 px per metre. Pick the scale so the whole visible part of the climb fits.
- The current height sits in a webbing tag with an arrow tip, at the middle of the strip, with one decimal, as now.
- The best height (`bestHeight`) is a short blaze-red mark. Lit lamps or saves (`g.lit`, `g.ticks`) are small lamp marks on the strip.
- The tape moves under a fixed pointer.

### Gear rack: Undo and Look

Replaces the bottom bar.

- A rope sling (`Kit.rope`, 6–7 px, with `ropeTwist` dashes 3 on 7) hangs across the bottom of the screen in a shallow curve.
- Things hang from it on teal carabiners (16×26, 3 px), each with a paper count tag (typed bold 15, rotated ±4°):
  - **Undo**: an "unclip" drawing, a carabiner with its gate open and a back arrow.
  - **Look**: a small monocular.
  - the two hand-strength tags, one at each end;
  - the status pill (`_Pill`) as a paper tag in the middle, typed bold, blaze red when `danger`.
- Each item's hit area is the whole hanging shape, at least 56×96.
- **Back** (recenter) becomes an index line written in chalk: "back to me".

### Field book page: Pause, fall, log

A page of `Kit.paper` with:

- ruled lines every 26 px (30 px on desktop) in `Kit.rule`;
- a red margin line at 66 px (`Kit.margin`);
- on phone, a spiral binding drawn along the top edge; on desktop, the page is an open spread with the rings down the middle.

Entries are `FbTxt.typed(15–18)`: a bold `HH:MM` or label column, then the text. The last line ends with a blinking block cursor (no blink under reduced motion).

### Index card: routes and climbers

`Kit.card`, a red line under the title, blue rules below it. Tabs on top for choosing; the picked tab is the card's colour and the others are `manila`, 4 px lower. Stats are typed rows with dotted leaders (`LENGTH ........ 38 m`).

### Ink stamp: things that are final

A circle or a box in blaze red (or ink), 5 px outline plus a 2 px inner line, rotated 8–16°. Archivo for the word, typed for the number. The rough edges and missing ink in the mockups come from a noise filter: bake each stamp once with a noise mask. Use it for: TOP and the height, FELL and the height, the route grade, Daily.

### Tally marks

`tallyPath(n)`, 2.6 px with round caps, every fifth stroke crossing the four before it. Use it for counts the player cares about: falls this climb, catches, and climber stats from 1 to 5 instead of `Pips` and `StatPips`.

## Screens

The mockups have five screens on phone and desktop. Below is where each part goes in the existing code. Do not add new screens or change the flow unless the owner asks.

### Menu (`lib/ui/menu.dart`, `climbers.dart`): the title poster plus the field book

The menu stays one scrolling page, as now. The scene shows at the top and fades into paper lower down.

- **Top: the poster** (`Title-Mobile`, `Title-Desktop`).
  - `_Brand` becomes TOPOUT in huge ArchivoXC: 136 px on phone in two lines, 290 px on desktop.
  - It is drawn *between* the sky and the mountain, so the peak covers the bottom of the letters. That needs the mountain drawn as a separate layer above the brand.
  - The title is ink by day and paper at dusk and night (`titleInk`).
  - A small height scale sits on the right edge.
  - A dotted chalk route climbs the peak, with a tiny orange climber on it. At night the climber has a headlamp glow.
- **Below: the field book.** Section labels look like the mockup headings: typed `§1`-style numbers and ArchivoXC titles.
  - **Climbers:** `ClimberPicker` cards become index cards. The name is in ArchivoXC, "Good at" is typed, the four stats are tally marks (1–5) and the perk is a short pencil note. The picked card has a webbing ribbon on its left edge (as in `Map-Desktop`).
  - **Routes:** `_RouteCard` grid becomes the topo (`Map-Mobile`, `Map-Desktop`), with tabs A, B, C for easy, medium, hard and D for the Daily Wall. Draw the topo from the real route: restyle `TopoPainter`.
    - The outline of the wall, coloured washes for the four zones, pencil hatching, and the line the route takes.
    - Ledges or lamps become numbered belay circles.
    - The route's grade is an ink stamp (I / II / III, D for Daily).
    - The card below shows real numbers: height, ledges, best time, best height.
    - The webbing strap says **Rope up · route A**.
    - Leave out pitch grades, water and rockfall unless the owner adds them.
  - **Mode:** `_ModePanel` becomes index lines with a pencil circle around the picked one.
  - **How to play:** `_HowToPanel` becomes a typed page, with Atkinson for the sentences.
  - **Your log:** `_LogPanel` becomes a log page: the records written as log lines, and the counts as tally marks.
  - **Play online** is an index line.
- On wide screens, follow the desktop mockups' spacing and the existing `_Grid` breakpoints.

### HUD (`lib/ui/hud.dart`): on the wall

Remove the dark gradient bars at the top and bottom; everything becomes an object.

| Today | Becomes |
| --- | --- |
| Pause `GameButton` | Luggage tag, top right |
| Route name, `Pips`, mode and climber | Paper scrap, top left: route name in ArchivoXC 20, `NORMAL · ADA` typed, the time typed, and tally marks for falls and catches this climb |
| Height, time and `_Progress` | Altimeter tape (the time moves to the scrap) |
| `_GaugeFor` × 2 | Grip halo, plus the "L / R" tags on the rack |
| `_Pill` | Paper tag hanging in the middle of the rack |
| Undo, Look | Items hanging on the rack |
| `GameToast` | A scrap that slides down under the top edge, typed bold; blaze red for bad news |
| `_TipCard` | A taped scrap above the rack, Atkinson for the text |
| Back (recenter) | Chalk index line "back to me" |
| Online: `_Heights` | A scrap on the left: typed list, you in bold |
| Online: Chat, quick chat, Watch, End climb | Luggage tags on the right, under Pause |
| Online: emotes | Small paper tags with a drawing each |

On desktop, show key hints (boxed typed letters, 2 px ink border) only for a mouse and keyboard. Use the real keys: **Esc** pause, **U** undo, **L** look, **Space** catch, **Enter** go on. Online also uses **A/D**, **1 2 3**, **Q W E R** and **Tab**. The desktop mockups show TAB, 1, 2 and 3 on rack items: those keys are wrong for Topout.

### Pause (`PauseCard`): the log

Phone: a page slides up from the bottom over the darkened scene, rotated −1°, with spiral rings along the top. Desktop: an open spread in the middle of the screen. Both are in the mockups.

- **Heading:** the route name in ArchivoXC, with the mode and climber typed next to it.
- **Lines:** what the game already knows, written as log lines: start time, moves, falls and catches, saves at lamps, height now. The last line ends with the cursor.
- **New tracking:** if the game does not keep the times of these events yet, write the totals as lines. A real event log is new tracking, so ask the owner first.
- **Buttons:** Resume is the webbing strap ("Back on the wall"). Start over, End climb (online creator) and Back are index lines.

### Fall (`FallCard`): the torn page

- The log page is torn diagonally across the bottom, rotated −3°, over the dark rock.
- The heading is FELL with the height as an ink stamp. `d.why` is the last log line (Atkinson is fine if Courier is hard to read at that length).
- **Hand strength:** `TracePainter` becomes a graphite pencil line on the ruled paper, turning blaze red where the hand ran out.
- `d.fix` goes on a taped scrap with the lamp icon. `d.note` is a pencil note (Reenie only if it is a few words; otherwise typed).
- Below the tear, on the rock: retry (`d.retryLabel`) is the webbing strap; Start over and Back are index lines in `blazeWhite`.
- A pencil streak that runs off the page plays once (not under reduced motion).

### Top (`TopCard`): the summit register

- A register page: columns DATE · CLIMBER · ROUTE · TIME.
- The player's row is written in Reenie. Faded scribbles above it stand for older entries; mark them `ExcludeSemantics` and do not make up names or times.
- Moves, falls and time become typed rows with dotted leaders. Keep the count-up.
- A red TOP stamp with the height lands on the page (a short scale-down when it appears; skip it under reduced motion).
- Next route (when there is one) is the webbing strap; Again and Back are index lines.

### Room results (`ResultsCard`, online)

The same register, with one real row per player in finish order, using `_FinishOrder`'s data. No made-up rows.

### Play online and the lobby (`lib/ui/online.dart`)

There is no mockup. Build it from the same parts:

- a field book page;
- the 4-letter room code as a big luggage tag;
- the players as register rows, with a pencil tick for Ready;
- Create, Join and Start as the webbing strap;
- the route and mode as index cards and index lines.

## Making it fast

| Mockup effect | In Flutter |
| --- | --- |
| Lit rock texture (SVG noise + lighting) | Keep `art.dart`'s baked rock texture. Tint it by `Env.rock` (modulate), or bake one copy per zone once and cross-fade at a boundary. Nothing per frame. |
| Chalk grain, ink stamps, torn edges | Bake each once with a noise mask (`Baked`), then stamp them. |
| Paper grid and grain | Bake one tile that repeats (`ImageShader`, `TileMode.repeated`). |
| Grain over the whole screen | Optional. One tiled image with multiply. Measure on the web build and drop it if frame time goes up. |
| Drop shadows (blurred) | Flat darker copies, offset. No `MaskFilter.blur`. |
| Climber shadow on the rock | Already done this way in Topout: keep it. |
| Headlamp, frost, mist | One rectangle each with a gradient shader. |
| Snow | The existing particle batches. |
| Moving things (mist, snow, sway, cursor, pulse, ink streak) | Off under reduced motion. |

## Order of work

Each phase ends with `flutter analyze`, `flutter test`, and a look at `build/screens/` beside the mockups.

1. **Fonts and tokens.** Add the fonts to `pubspec.yaml` and `test/fonts.dart`. Add `field_book.dart` and fix anything `flutter analyze` finds. Change what is inside `Txt`.
2. **Shared parts** in `widgets.dart`:
   - `WebbingButton` and `IndexLine`; `GameButton` picks one by `primary`, and keeps its API;
   - `PaperScrap`, `LuggageTag`, `InkStamp`, `ChalkMark`, `TallyMarks`;
   - `GameChoice` gets a pencil circle, `GameToggle` a pencil box;
   - `Pips` and `StatPips` become tallies, and `DailyBadge` a stamp.
3. **Scene:** `Env` colours, mist, frost, headlamp, blazes; chalk aiming marks and catch rings.
4. **HUD.**
5. **Cards:** Pause, Fall, Top, Results.
6. **Menu, climbers, topo, online.**
7. **Clean up:** remove fonts and `Pal` colours nothing uses, update the README sections about the look ("A climber drawn in code…", the fonts row, "Keeping it fast" if anything changed).

## Done when

- [ ] Every screen in the mockups exists in the game with real data, on phone and desktop.
- [ ] Nothing from "Sample content: do not copy it" appears in the game.
- [ ] The palette follows height and time of day, and frost, snow and the headlamp work.
- [ ] Shape alone tells good, weak and no holds apart. Check with the colour switched off.
- [ ] Reduced motion stops every movement listed above.
- [ ] `flutter analyze` is clean, `flutter test` passes, and the web build stays as smooth as before.
- [ ] Commits follow `CLAUDE.md`.
