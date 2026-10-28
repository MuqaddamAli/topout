# Online play

Up to 8 players, each on their own device, climb the same wall at the same time and see each other live. Each player controls only their own climber; the others are drawn see-through with their names, and nobody can touch anybody.

The game talks to a small room server in `server/` (Node.js and Socket.io). This page shows how to try it on one PC, then with phones on the same Wi-Fi, and how to put the server online on Render's free plan.

The commands are for PowerShell on Windows. They work the same in other terminals.

## How it works

- **Joining.** One player taps **Play online**, enters a name, picks a route and a mode and taps **Create**. The game shows a 4-letter code (never I, L or O) with a **Copy** button. Others tap **Play online**, enter a name and the code, and join the lobby.
- **The lobby.** It shows everyone, their climber and the lane they will get ("Rio · Lane 2, left"), and how many lanes the wall will have. Everyone can pick a climber. Two players may pick the same one.
- **Starting.** Only the creator has **Start**. When they tap it, every lobby counts down from 3 and everyone starts the same route in the same mode. On the Daily Wall it is the wall of the creator's day, so players in other time zones get the same wall.
- **Errors.** A 9th player gets "Room is full (8/8)", a wrong code gets "Room not found", and a code for a room that already started gets "This climb has already started".
- **Leaving.** Anyone can leave at any time. If the creator leaves, the next player becomes the creator. A player whose connection drops keeps their place for 20 seconds and rejoins quietly.
- **While climbing.** Each game sends its climber 10 times a second (a small array of about 100 bytes). Your own climber never waits for the network. Others are shown 100 ms in the past and blended between states, so they move smoothly.
- **What you see.** A list in the corner shows everyone's height, highest first. Messages say who joined, left, fell or topped out. At the top, the card shows the finishing order and times.
- **What stays your own.** Your camera, grip, falls, undo and checkpoints are yours alone, and pausing only pauses you.
- **Records.** Online climbs are not saved in your records (best times, highest point, Daily best, the climbing log). The top card says so.

## Lanes

So that climbers do not stand on top of each other, the wall gets wider with the room: **one lane per two players**, at most four.

| Players | Lanes |
| --- | --- |
| 1-2 | 1 |
| 3-4 | 2 |
| 5-6 | 3 |
| 7-8 | 4 |

- **Every lane is the same route.** Each lane is a copy of the room's route (or of the day's Daily Wall), moved one wall width (3.6 m) to the side. Lanes 2 and 4 are mirrored left to right, so the lanes look different but are exactly as hard: the rules treat left and right the same. With one lane the wall is exactly the single-player wall.
- **Bridges.** Where two lanes meet there is a short flat row of holds every 2.6 to 3.4 m (two hand holds and two foot steps on each side), so you can cross over and meet. They are flat, so they give no height. Every lane has the same bridge holds on both edges, the outer lanes too, so no lane has more holds than another. The ground and the top run across all lanes: topping out anywhere on the top counts.
- **Where you start.** Each lane has two spawns, left and right of the start holds. You stand on the ground with one hand on the start jug of your side, about 60 cm from the other player of your lane. Climbing alone you start as before, hanging from both start jugs.
- **Who gets which lane.** When the creator taps **Start**, the server gives out lanes in the order players joined: the first player (the creator) gets lane 1 left, the next lane 1 right, then lane 2 left, and so on. If the creator left before the start, the next player is first. The server sends the number of lanes and everyone's lane and side with the room, and they stay fixed for the climb: if someone leaves, the wall does not change.
- **The same wall everywhere.** Every game builds the wall from the route, the mode, the Daily Wall's date and the number of lanes, so it is the same on every device.
- **On the wall.** Each lane's crash pad has its number on it; your own lane's is orange. The camera follows you across the whole wall, also over a bridge; **Look** shows the lane you are in now. Try again, Start again and the Daily Wall's new try bring you back to your own spawn.
- **For later.** Players do not touch each other yet (no catching, boosting or bumping). The wall knows its lanes and bridges (`ClimbRoute.lanes`, `ClimbRoute.bridges` in `lib/game/core.dart`) and every player's lane and side are kept (`Game.spawn`, `RoomPlayer.lane` and `side`), so that can be built on top.


| File | What it does |
| --- | --- |
| `server/index.js` | The server: `GET /health`, Socket.io events, which sites may connect (CORS) |
| `server/rooms.js` | Rooms and players, the error messages, the creator hand-over, the grace period, the lanes given out at the start |
| `server/bots.js` | Fake players for testing, and the climber state format |
| `lib/game/online.dart` | The connection, the room and the lobby state in the game |
| `lib/game/core.dart` | `laneWall`: the wall with lanes, bridges and spawns |
| `lib/game/remote.dart` | The climber state (encode and decode), playing others back smoothly |
| `lib/ui/online.dart` | The Play online screen and the lobby |

## a) Test on your PC

You need Node.js 20 or newer (`node --version`) and Flutter.

**1. Start the server** (terminal 1):

```powershell
cd server
npm install        # the first time only
npm start
```

It prints `Topout server on port 3000`. Open http://localhost:3000/health in a browser: it says `ok`.

**2. Run the game in Chrome** (terminal 2, in the project folder):

```powershell
flutter run -d chrome --web-port 8080
```

The game picks its server from where it runs: on `localhost` or a local network address it uses port 3000 of that same machine, and on the live site it uses `https://topout.onrender.com`. A build can set another one with `--dart-define=MP_SERVER=...`.

**3. Open more players.** Open http://localhost:8080 in more Chrome windows; each window is one player. Put two side by side, make a room in one (**Play online**, **Create**) and join it from the other with the code.

**4. Fill the room with bots** (terminal 3), using your room code:

```powershell
cd server
npm run bots -- ABCD 6
```

That makes 6 fake players. With your 2 windows the room is full (8/8), and a third window gets "Room is full (8/8)". Bots wait for the creator's Start, then climb up and down in their own lane and sometimes fall (each one prints its lane, for example "Bot 3: lane 2 right of 4"). On First Wall, Granite Steps and Crimp Ladder they stop on the top, so you can see the top-out messages and the finishing order; on the Daily Wall they keep going. Press Ctrl+C to remove them.

**Try the lanes.** With your 2 windows in the room, the number of bots sets the number of lanes:

| Players | Bots | What you see |
| --- | --- | --- |
| 2 | none | 1 lane: the creator on the left, the other window on the right |
| 4 | `npm run bots -- ABCD 2` | 2 lanes: your windows in lane 1, the bots in lane 2 |
| 6 | `npm run bots -- ABCD 4` | 3 lanes (lane 2 is mirrored) |
| 8 | `npm run bots -- ABCD 6` | 4 lanes |

The lobby shows each player's lane before you tap Start. In the climb, find the bridges at the lane edges (the first is at about 2.3 m) and cross into the bots' lane; Look shows the lane you are in.

To see a wide wall without the server, open the game with `?lanes=N` (1 to 4), for example http://localhost:8080/?lanes=4: climbs alone then use a wall with N lanes (not saved in the records). This is for development: it works in `flutter run` (debug) and `--profile` builds; the live site ignores it.

**5. Measure the speed of a full room.** Frame times are only real in a release build:

```powershell
flutter run -d chrome --release --web-port 8080
```

Open http://localhost:8080/?perf=online and press F12 for the console (a room with 8 climbers has 4 lanes). It makes a room and prints the bot command (`npm run bots -- XXXX 7`). Run it in `server`; when 8 climbers are in, the climb starts by itself. After about 18 seconds it switches to Look, so everyone is on screen. The `perf fps … build … raster …` lines come every 2 seconds.

**6. Run the tests:**

```powershell
cd server
npm test           # the server: rooms, errors, creator leaving, reconnecting, lanes
cd ..
flutter test       # the game, online screens, climbing together and the lanes included
```

## b) Test with phones on the same Wi-Fi

The phones and the PC must be on the same Wi-Fi network.

**1. Find your PC's address on the Wi-Fi:**

```powershell
ipconfig
```

Under **Wireless LAN adapter Wi-Fi**, read the **IPv4 Address**, for example `192.168.18.23`. Use your own address in place of `192.168.18.23` below.

**2. Let the phones in through the Windows firewall.** The phones connect to two ports on your PC: 3000 (the server) and 8080 (the game).

- Your Wi-Fi must be a **private** network: Settings > Network & internet > Wi-Fi > your network > Network profile type > **Private**.
- The first time Node.js and Dart listen, Windows may ask whether to allow them. Tick **Private networks** and choose **Allow**.
- If no prompt comes, or the phones still cannot connect, open PowerShell **as administrator** and allow both ports:

  ```powershell
  New-NetFirewallRule -DisplayName "Topout LAN test" -Direction Inbound -Protocol TCP -LocalPort 3000,8080 -Action Allow -Profile Private
  ```

  To remove the rule later: `Remove-NetFirewallRule -DisplayName "Topout LAN test"`.

**3. Start the server** as in a) (`cd server`, `npm start`). On a phone, open `http://192.168.18.23:3000/health`: it should say `ok`. If it does not load, it is the firewall or the network (see step 2).

**4. Run the game for the network** (in the project folder):

```powershell
flutter run -d web-server --release --web-hostname 0.0.0.0 --web-port 8080
```

Opened at your PC's address, the game uses the server on port 3000 of the same address by itself.

**5. Open the game on the phones** at `http://192.168.18.23:8080`, and on the PC at the same address (not `localhost`). Make a room on one device and join from the others.

On the phones, **Copy** may do nothing: browsers only allow copying on `https` pages or on `localhost`. Read the code out instead. This works normally on the real site.

## c) Put the server online on Render (free)

Do this once everything works on your PC. The game's web version stays on Vercel; only the room server goes to Render.

**1. Make the web service.**

1. Sign in at https://render.com with GitHub.
2. Click **New** > **Web Service** and pick the `topout` repository.
3. Fill in:

   | Setting | Value |
   | --- | --- |
   | Name | `topout-server` (the address becomes `https://topout-server.onrender.com`; Render adds a few letters if the name is taken) |
   | Branch | the branch with the server: `feature/online-multiplayer` now, `main` after it is merged |
   | Region | **Singapore** (the closest to Pakistan), or **Frankfurt** |
   | Root Directory | `server` |
   | Runtime | Node |
   | Build Command | `npm install` |
   | Start Command | `npm start` |
   | Instance Type | **Free** |

   The region cannot be changed later. A different region means a new service.

4. Under **Advanced**, set **Health Check Path** to `/health`.
5. Click **Create Web Service**.

Render sets `PORT` itself, and the server listens on it.

**2. Check it.** When the deploy says **Live**, open `https://topout-server.onrender.com/health` (your service's address). It says `ok`.

**3. Know the free plan.**

- The free server goes to sleep after about 15 minutes with nobody connected. The first player after that waits up to a minute while it wakes: the game shows "Connecting to server…" and that the server may be waking up. After a minute it shows **Retry**.
- Rooms live in the server's memory. A redeploy or a restart ends all rooms: players are told they lost their place in the room, and someone makes a new one.

**4. The Vercel site finds it by itself.** The game on the live site connects to `https://topout.onrender.com` (set as `onlineServer` in `lib/game/online.dart`), so nothing has to be set in Vercel.

If the server ever gets another address, either change `onlineServer` and push, or set it in Vercel without a code change:

1. In Vercel, open the project and go to **Settings** > **Environment Variables**.
2. Add **Key** `MP_SERVER` with the server's address (no `/` at the end) for **Production** and **Preview**, and **Save**.
3. The address is built into the game, so it only takes effect in a new build: in **Deployments**, open the menu (**…**) of the latest Production deployment and click **Redeploy**. The build log says `Online play uses the server at https://…`.

**5. Try it.** Open the Vercel site on two devices, make a room on one and join from the other.

The server lets in pages from any `https://….vercel.app` address, `localhost` and local network addresses (`192.168.x.x`, `10.x.x.x`). If the site gets its own domain, add it in Render under **Environment** as `ALLOWED_ORIGINS`, for example `https://topout.example.com` (several separated by commas). Then the server restarts by itself.

## Going live: the order

Vercel builds the live site from `main`, and Render builds the server from `main` too. A push to `main` updates both: the game in a few minutes, the server in about a minute (which ends the rooms open at that moment).

Single-player works the same whether the server is up or not; only Play online needs it.

The lanes need the server and the game from the same version. After merging the lanes, check that Render has deployed it (the deploy's commit in Render's **Events**). A game on a server from before the lanes still gives every player the same lane and side, by the order they joined.

## When something does not work

- **"Can't reach the server."**
  - Is the server running? Does `/health` load in the same browser?
  - The game shows the server address it tries under the message.
  - On the live site it should show `https://topout.onrender.com`. Open https://topout.onrender.com/health: it says `ok` once the server is awake.
- **The other phones cannot connect, but the PC can.**
  - It is the firewall or the Wi-Fi profile (see b, step 2).
  - Use the PC's IP address everywhere, never `localhost`: on a phone, `localhost` is the phone itself.
- **"Room not found" for a code that worked before.** The server restarted (a redeploy, or Ctrl+C), and rooms do not survive that. Make a new room.
- **The browser console shows a CORS error.** The page's address is not on the server's list. Add it with `ALLOWED_ORIGINS` (see c).
