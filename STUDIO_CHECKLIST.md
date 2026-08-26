# STUDIO_CHECKLIST — owner verification (criteria 4, 5, 6, 8, 8b + device)

Everything below needs Roblox Studio (or a published test place) — the headless
suites cover all pure logic; this list is what only humans + real clients can
verify. Suggested setup: Studio → Test → Clients and Servers → 2 players.

## One-time setup
- [ ] Open the repo with `rojo serve` + the Rojo plugin (or open `build/fusion-zoo.rbxl` from `scripts/build-place.sh`).
- [ ] Game Settings → Security → **Enable Studio Access to API Services** (otherwise the server logs "mock store" and nothing persists).
- [ ] For a published place: enable **MemoryStore** + **DataStore** usage (default on).

## Criterion 4 — two accounts in one server
Start a 2-player local server. On **Player1**:
- [ ] Walk to the 任务亭 kiosk → complete a mission question (with the audio manifest still empty, expect the "content coming" card unless pinyin mode is on — toggle it via `Quiz/SetPinyinMode` or fill a few `data-src/audio_manifest.json` entries and rerun `lune run scripts/build-data`).
- [ ] Rescue: pen shows the 18 animals; tutorial gifts 猫+鸟 are already owned. Verify a locked animal shows 🔒 + its character.
- [ ] Fusion Lab: fuse 猫-head + 鸟-body (10🪙). Then fuse 鸟-head + 猫-body and stand the two beasts side by side on your plot: **visibly different chimeras** (cat ears vs beak, body colors swap).
- [ ] Feed a slot from the beast menu; watch the module grow on the plot creature after refresh.
- [ ] Beat NPC rungs 1–4 (parent panel/console can grant coins if grinding is slow: profile is server-side, use the mock console), then Unlock LEGS (25🪙) — verify the unlock REFUSES before rung 4.
- [ ] Re-fuse to add legs; feed level survives the swap (shown in the beast detail).
- [ ] Walk into **Player2's plot**: creatures visible, hover cards show name/build/stats when close.
- [ ] Live battle: both players stand on the glowing challenge pad → 挑战 → accept → both get simultaneous 4s flashes → reveal shows both cards with ×2 math where charged+advantaged.

## Criterion 5 — ghosts reflect the other account
- [ ] Player2: answer ~20 mission questions with deliberately mixed accuracy, set an active beast, leave the server (publishes the final ghost).
- [ ] Player1 (new session is fine): Arena → 幽灵兽 → verify the ghost is Player2's beast (name shown) and its ⚡ charge stars track Player2's real accuracy (try again after Player2 plays a perfect run — stars should rise on the next publish).
- [ ] Winning pays 2🪙 (up to 10🪙/day; the cap note appears after 5 wins).
- [ ] Verify Player2's coins/record did NOT change from losing as a ghost.

## Criterion 6 — persistence
- [ ] Player1: note coins/mastery/beasts. Leave, rejoin → identical.
- [ ] Crash sim: kill the server process mid-session (Studio stop button) → rejoin → state = last autosave (≤30s old).

## Criterion 8/8b — progress + silhouettes
- [ ] Progress Board shows 识字进度 N/700 with 14 band bars; screenshot-worthy on a phone.
- [ ] Screenshot pass: line up 马蛙 vs 蛙马 (and 2-3 other swaps) at min and max feed; silhouettes must read differently at plot distance. (The math side is already covered by `lune run scripts/geometry-check`.)

## Music (one-time, ~10 minutes)
The 4 Suno tracks live in `assets/music/`. Until their SoundIds are filled the game is silent — by design, never an error.
- [ ] Upload each of `assets/music/*.mp3` at create.roblox.com → Creations → **Audio** (they pass moderation as owner-created music).
- [ ] Paste each returned asset id into `data-src/music_manifest.json` as `rbxassetid://<id>` (hub = sunny_zoo_garden, kiosk = quiet_curiosity, battle = toy_monster_showdown, victory = victory_bell), then `lune run scripts/build-data`.
- [ ] In game: hub loop plays on spawn → kiosk track while the quiz is open → battle track during a match → ≤10s victory bell on a win, then back to the hub loop. Crossfades, no hard cuts.

## Device checks
- [ ] 汉字 render on iPhone/iPad + at least one Android device (SourceSans fallback) — kiosk, hover cards, progress board, coin math flashes.
- [ ] Audio: fill band-1 entries in `data-src/audio_manifest.json` with uploaded SoundIds, rebuild data, verify listen mode plays on device (iOS needs the first user tap).
- [ ] ProximityPrompts reachable on touch (they render as tap buttons).

## Compliance spot-checks
- [ ] No free-text input anywhere (naming = mastered-char picker only).
- [ ] Chat is Roblox default filtered chat; cheer wheel is fixed catalog.
- [ ] No purchase prompts of any kind.
