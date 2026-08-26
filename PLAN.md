# PLAN.md — 融合动物园 Fusion Zoo for Roblox (rev 3 build)

> Approved plan of record for this build. Milestones land as commits on `main`; every
> milestone's headless verification must be green before its commit.

## Context

Ground-up Roblox rebuild of Fusion Zoo per the rev-3 kickoff. The web version (`/home/user/fusion-zoo`) is the design reference: its **learning engine ports faithfully** (battle-tested quiz tuning = core IP, extracted from code below — not the stale README), while its **reward systems are redesigned**: slot-stat fusion, secret-pick battles with charge flashes, ghost battles, player plots, a 700-character 部编版 Grade-1 curriculum, and a two-mode/two-day mastery model backing the store-page claim.

**Settled decisions (user-confirmed):** this plan = PLAN.md · build straight through all milestones · push to `main`, one commit per milestone · **onboarding tutorial gifts the first two animals (猫, 鸟) exempt from the mastery gate** so a new player rescues → fuses → battles in session one; every other animal enforces MASTERED + tier cost.

**Environment constraints:** no Studio in the build container → every milestone verifies headless (Lune + TestEZ-style suites); multi-account/device checks go to `STUDIO_CHECKLIST.md`. Criterion 8b (screenshot pass) is reinterpreted as headless geometry validation + owner screenshot checklist. Chinese education portals are egress-blocked and no public JSON of the 识字表 exists → curriculum compiled from model knowledge anchored to the web repo's 236 poster chars (declared subset of 上册 300), with `CURRICULUM_REVIEW.md` (low-confidence entries first) for the owner's textbook spot-check; corrections are a data-only drop.

## Port reference — web-engine ground truth (from code, file:line into `/home/user/fusion-zoo`)

| Mechanic | Web code truth | Ruling |
|---|---|---|
| Level-up streak | `cleanToAdvance = [3,4,6,8,8]` (`missions.ts:31`) — README's "5" is stale | Port code values; already implements spec's "accelerated placement" (3 at L1). Owner sign-off noted. |
| Level-down | 4 misses, min level 1; level-up resets both streaks, +8 unlocked | Port |
| Mode mix | L1 100% listen; L2 60/40 listen/char→pic; L3+ 50/20/30; pinyin-on (L4+) → 5/13, 2/13, 3/13, 3/13 | Port exactly; eligibility-gated by manifests (below) |
| Choices | 3 per question (target + 2 distractors) | Port |
| Distractors | rings same-category → same-band → any, from FULL deck; display-key uniqueness | Port |
| Homophone rule | listen distractors exclude exact tone-sensitive pinyin match (`missions.ts:196`) | Port — already satisfies spec's hard rule; 10k-draw property test |
| Picture confusables | 31-key `CONFLICTS` map | Port, extend across 700 as visuals land |
| Repeat avoidance | session ring of last ≤12, adapts to keep ≥3 candidates | Port |
| Sampling weights | mastered ×0.12, number-category ×0.25 (= spec's 4× under-sampling) | Port |
| Working set | prefix of seeded per-band shuffle (one mulberry32 stream, bands ascending); start 8; +8/level-up; +8 while fresh<16 | Port; mulberry32 + descending Fisher–Yates reproduced with exact uint32 arithmetic |
| Coin per solve | web: +1 clean AND retry; −1 floor 0 on 2nd wrong | New economy: clean +1 (warm-up doubles first 5/day), retry +0, miss −1 floor 0. Retry still resets clean streak, holds mastery streak |
| Counting pictures | number chars render visual × `value` | Port |
| Web mastery | streak ≥3 clean; drives expansion + 0.12 review | Becomes the "warm" tier; spec's two-mode/two-day rule defines MASTERED (resolution 1) |
| Battle keeps | best-of-3; triangle 速>力 智>速 力>智; ×2 math shown | Keep. Secret pick + charge replace random stats; spec's tie-replay supersedes web's ties-go-to-kid |
| Launch data | 18 animals, 8 opponents (exact stats extracted) | Converted verbatim from web JSON; 4 new NPCs fill rungs 9–12 |

Spec-over-web deltas: slot-stat fusion replaces `fuseStat`; rescue tiers 5/8/12/18/25 replace flat 5; flat 3🪙 rung bounty replaces 3+idx; real-word = any pair anywhere in build + 5🪙 once per combo (web: exact-2-set, cosmetic); daily warm-up double; ghost/live caps.

## 1. Architecture

**Split.** `src/shared` (→ `ReplicatedStorage/Shared`): types, one tunable `Config`, GENERATED data modules, and all pure logic (quiz, leveling, mastery, battle, fusion, feed, economy ledger, rig math, RNG, guards, day-key time) — no `game`, no `Instance`, fully headless-tested. `src/server` (→ `ServerScriptService/Server`): thin services; sole writers of coins/mastery/beasts/battles; every decision delegated to shared pure modules. `src/client` (→ `StarterPlayerScripts/Client`): controllers + UI; renders, plays audio, animates, requests — never computes an outcome; every displayed number (coin math, ×2 strings, reveals) arrives from the server. Nothing hand-placed in Studio: `WorldService` builds hub/plots/kiosk/lab/arena/board procedurally; `CreatureService` builds rigs from data.

**Toolchain.** rokit pins `rojo`, `lune`, `stylua`, `selene`, `darklua`. All modules use relative string requires (`require("./X")`): Lune resolves them natively so tests/scripts hit `src/shared` with zero shims; `scripts/build-place.sh` runs `rojo sourcemap → darklua convert_require → rojo build` for the Studio artifact. `--!strict` everywhere; shared types in `src/shared/Types.luau`; selene + stylua gate every milestone.

**Test harness.** `tests/testkit/` — a minimal TestEZ-API-compatible runner (describe/it/expect, beforeEach, focus/skip) run by `lune run scripts/run-tests`. Spec files are TestEZ-shaped, and a `TestBootstrap` server script is included so the same suites can run under stock TestEZ inside Studio. Every sampling spec takes an explicit seed (deterministic).

**Remote surface** (created by `src/server/Net.luau` under `ReplicatedStorage/Remotes`; RF = RemoteFunction request/response, RE = server-push RemoteEvent):

| Remote | Kind | Contract | Anti-exploit |
|---|---|---|---|
| `Quiz/RequestQuestion` | RF | → `{questionId, mode, prompt {soundId?/char?/visual?/pinyin?}, choices[3], warmupRemaining}` | One pending question per player, correct index server-only; re-request voids previous; 1/s rate limit |
| `Quiz/SubmitAnswer` | RF | `{questionId, choiceIndex}` → `{outcome clean/retryPending/retry/miss, correctIndex?, coinDelta, coinMath, newCoins, levelUp?/levelDown?, cleanStreak, masteredNow?}` | Must match pending record, <2 taps; all scoring server-side |
| `Quiz/SetPinyinMode` | RF | `{enabled}` | boolean guard |
| `Progress/GetSummary` | RF | → `{total, of=700, bands[14]{band, mastered, of}, deferred}` | read-only |
| `Zoo/Rescue` | RF | `{char}` | animal exists, unowned, char MASTERED (tutorial grants exempt), coins ≥ tier |
| `Zoo/Fuse` / `Zoo/Refuse` | RF | `{slots {head, body, legs?, tail?}}` / `+beastId` → `{beastId, stats, realWord?}` | ownership of every occupant, slot unlocks, funds; stats server-computed; real-word bonus once per combo |
| `Zoo/FeedSlot` | RF | `{beastId, slot}` → `{newFeedLevel, coinDelta, newStats}` | slot unlocked, cost = next level n, cap 10 |
| `Zoo/UnlockSlot` | RF | `{slot LEGS/TAIL}` | LEGS: rung ≥4 + 25🪙; TAIL: rung ≥8 + 60🪙 — rung from profile |
| `Zoo/NameBeast` | RF | `{beastId, chars[2]}` | both chars in player's MASTERED set (the no-free-text guarantee); 3🪙 |
| `Zoo/SetActiveBeast`, `Zoo/BuyDecoration`, `Zoo/BuyColorway` | RF | ids from data catalogs | ownership; prices server-side |
| `Battle/StartNpc` | RF | `{rung}` | rung ≤ ladder+1; one live session per player |
| `Battle/StartGhost` | RF | `{}` | server picks the ghost (prevents cooldown farming) |
| `Battle/Challenge`, `Battle/RespondChallenge` | RF | `{targetUserId}` / `{accept}` | pad-proximity checked server-side |
| `Battle/PickStat` | RF | `{battleId, round, stat}` | participant, one pick/round, stored secretly |
| `Battle/SubmitFlash` | RF | `{battleId, round, questionId, choiceIndex}` → `{charged}` | same validation path as missions; server 4s deadline; mints no coins, touches no leveling/mastery |
| `Battle/FlashPrompt`, `Battle/RoundResult`, `Battle/MatchResult` | RE | prompts, per-round math strings ("速 6 ×2 = 12"), match outcome + capNote | all math server-computed, simultaneous reveal |
| `Battle/Cheer` | RE | `{emoteId}` from fixed wheel catalog | rate limit, arena proximity |
| `Plot/PlaceDecoration` | RF | `{itemId, cframeIndex}` | owned item; fixed indexed placement grid |
| `Profile/Ready`, `Profile/Delta` | RE | initial state push + cross-system deltas | — |

**Global posture:** every RF runs `Util/Guard` schema validation → token-bucket rate limit → session-state auth (pending question / battle participant / ownership) → mutation through `EconomyService`, the **sole coin writer** (reason codes, floor 0, daily caps, analytics). No remote payload ever contains a coin amount, stat value, or battle result — the security suite asserts this by attempting exactly those forgeries against the service layer with a mocked Net (criterion 3).

## 2. Module layout

**[P]** pure, headless-tested · **[E]** engine-bound · **[G]** generated

```
rokit.toml  default.project.json  .luaurc  selene.toml  stylua.toml
PLAN.md  LIVEOPS.md  CURRICULUM_REVIEW.md [G]  STUDIO_CHECKLIST.md
data-src/                      -- the only hand/owner-edited data (JSON)
  curriculum_grade1.json       -- 700 items, word-shaped schema + category + confidence flags
  animals.json                 -- 18 launch animals + rig params + rescue tier (drip-extensible)
  opponents.json               -- 12 NPC rungs (8 web + 4 new)
  words.json  foods.json  decorations.json  colorways.json  cheers.json
  audio_manifest.json          -- item text → SoundId (owner fills in band batches)
  icon_manifest.json           -- item text → decal id (owner's pre-uploaded icon set)
src/shared/
  Types.luau [P]   Config.luau [P]  -- ALL tunables in Config: economy, caps, weights,
                                       cleanToAdvance, mastery, feed curve, charge probs
  Data/ [G]  -- emitted by scripts/build-data: Curriculum, Animals, Opponents, Words, Foods,
                AudioManifest, IconManifest, HomophoneIndex (pinyin→texts), Conflicts,
                Decorations, Colorways, Cheers
  Quiz/   Item [P] (eligibility: listenEligible/pictureEligible/pinyinOnly)
          Deck [P] (seeded per-band shuffle, prefix working set)   ModePicker [P] (mix table +
          eligibility filtering + renormalization — criterion 9 lives here)
          Sampler [P] (weights, repeat ring, deferral)   Distractors [P] (rings, homophone,
          conflicts, display-key)   Generator [P] (items in, questions out — shared by missions
          AND charge flashes)   Leveling [P]   Mastery [P] (two-tier, below)
  Battle/ Resolver [P] (eff = stat × (advantaged AND charged ? 2 : 1); best-of-3; tie replay
          + safety valve; math strings)   NpcBrain [P] (charge 0.3 + 0.5·(rung−1)/11)
          GhostBrain [P] (pick histogram weighting; charge = clamp(ownerAccuracy, .2, .9))
  Fusion/ SlotStats [P] (BODY→力 LEGS→速 HEAD→智 TAIL splash; innate + slot feed, cap 10;
          2-part defaults)   RealWords [P] (any pair anywhere, both orders)   FeedCurve [P]
  Economy/Ledger [P] (faucet/sink codes, warm-up doubling, caps, cooldowns)
  Rig/    RigData [P] (per-animal per-module primitive-part specs + socket contract:
          BODY owns NeckSocket/LegSockets[4]/TailSocket)   RigMath [P] (build+feed →
          sizes/CFrames; +6%/point, cap ×1.55, axis emphasis; silhouette footprint)
  Util/   Rng [P] (mulberry32/seededShuffle/weightedPick, verbatim port)   Guard [P]
          Time [P] (UTC dayKey)
src/server/
  main.server.luau [E]   Net.luau [E]   Vendor/ProfileStore.luau [E] (vendored loleris)
  Services/ [E]: ProfileService (wraps ProfileStore; schemaVersion + Migrations; injectable
    mock store for tests) · QuizService (pending tables: mission + flash namespaces) ·
    EconomyService (sole coin mutator) · ZooService · BattleService (one state machine, three
    opponent kinds behind one Brain interface) · GhostService (DataStore pool + MemoryStore
    index + starter-ghost fallback) · PlotService · CreatureService (rigs, wander, hover-card
    attributes) · WorldService (procedural hub) · AnalyticsService (buffer → DataStore)
src/client/
  main.client.luau [E]
  Controllers/ [E]: Quiz, Battle (pick UI, 4s flash bar, reveal), Zoo (lab/rescue/feed/naming),
    Plot (hover cards), Progress (识字进度 N/700), Audio (SoundId playback + band preload),
    Cheer, Anim (procedural idle/walk: sine bob + phase-offset leg swings)
  UI/ [E]: CoinCounter, MathFlash, ChoiceButton, ViewportModel, BandBar, SlotColumn,
    SilhouetteCard, Overlays
tests/
  testkit/ (runner) · content/ (700 unique, pinyin+band, needs_visual consistency, homophone
  index, ≥2 valid distractors per listen item) · quiz/ (mode mix ±5%/1000; numbers 4×;
  homophone 10k; determinism; degradation) · leveling/ · mastery/ · fusion/ · battle/ ·
  economy/ · rig/ · profile/ (migrations, round-trip, lock recovery vs mock store) ·
  security/ (mock-client forgeries — criterion 3)
scripts/ (Lune)
  compile-curriculum.luau  build-data.luau  run-tests.luau  audio-manifest-check.luau
  geometry-check.luau  coin-flow-sim.luau  build-place.sh
```

## 3. Data flows

**(a) Quiz round-trip.** Kiosk → `Quiz/RequestQuestion`. `QuizService`: deck view from `Curriculum` + player seed → `ModePicker` (level mix × per-item eligibility) → `Sampler` (weights, ring, deferral) → `Distractors` → store `{questionId, item, correctIndex, tapCount}` server-side → return render payload (listen prompts carry only a SoundId). `SubmitAnswer`: 1st tap correct → `Leveling.applyClean` + `Mastery.recordClean(item, modeClass, dayKey)` (+ working-set expansion while fresh<16) + `EconomyService:Faucet("clean_solve")` with warm-up doubling → coinMath string back. 1st wrong → free `retryPending`. 2nd correct → retry: +0🪙, clean streak resets, warm streak holds. 2nd wrong → miss: reveal, −1 floor 0, warm streak→0, missStreak≥4 → level down. Pending record deleted; duplicate submits rejected. One analytics event per outcome.

**(b) Battle round (all three opponent kinds).** A side is `{kind="player", userId}` or `{kind="brain", brain, stats}` (NpcBrain/GhostBrain) — downstream identical. Phase *picking*: players `PickStat` secretly, brains pick synchronously. Phase *flash*: each player side gets `QuizService:GenerateFlash` from their own band/mode mix (same Generator, flash namespace, server deadline now+4s) via `FlashPrompt`; `SubmitFlash` validates like a mission answer but sets only `charged` — no coins, no leveling, no mastery. Brains roll charge (NPC rung curve; ghost = owner's recorded accuracy). Phase *resolve*: `Resolver.resolveRound` — doubled only if advantaged AND charged — pushed with simultaneous reveal + math strings. Tie → replay with fresh picks/flashes (after 3 ties: higher total build stats, then challenger). First to 2 → `MatchResult`; Economy applies NPC first-clear 3🪙 flat + rung advance / ghost 2🪙 (6h per-ghost cooldown, 10🪙/day) / live 3🪙+1🪙 (9🪙/day), cap hits messaged via `capNote`.

**(c) Profile lifecycle.** `PlayerAdded` → ProfileStore `StartSessionAsync` (session lock; crashed-server locks stolen after timeout → crash-sim criterion) → `Migrations` chain from stored `schemaVersion` → reconcile template → lazy daily rollover → `Profile/Ready` push → ghost republish. Autosave ~30s + on release; `PlayerRemoving` flushes analytics then `EndSession`. Services access profiles only via `ProfileService:Get`; tests inject an in-memory mock store (same interface).

**(d) Ghost publish/fetch.** Publish (active-beast/stat change, 30s debounce, session end): snapshot `{ownerUserId, displayName, build, stats, pickHistogram, accuracy, publishedAt}` → DataStore `GhostPool_v1` + MemoryStore SortedMap `GhostIndex` (TTL 30d). Fetch: random window from index → filter self + cooldowns → weight toward ±30% total stats → load snapshot. Thin pool → seeded starter ghosts. Ghost owner's profile untouched; intro card shows "studying makes your beast stronger, even while you sleep" + charge rate as stars.

**(e) Content pipeline.** `scripts/compile-curriculum.luau` (rare): web 236 chars keep metadata + get 识字表 ordering; remainder from model knowledge with `confidence: "model" | "web-verified"` → `curriculum_grade1.json` + regenerated `CURRICULUM_REVIEW.md`. `scripts/build-data.luau` (every data change): validate (700 unique, pinyin+band on all, band sizes, needs_visual consistency, category coverage) → derive `HomophoneIndex` → emit `src/shared/Data/*.luau` as strict table literals with DO-NOT-EDIT headers. Owner corrections and monthly animal drips = JSON drop + rerun, zero code changes.

## 4. Design resolutions

1. **Two-tier mastery.** Web's streak mastery ports unchanged as **warm** (streak ≥3; drives 0.12 review weight and MIN_FRESH-16 expansion — the pacing IP). **MASTERED** (the credential: rescue gate, /700 progress, naming pool) = clean-solve evidence spanning ≥2 mode *classes* (listen · picture · pinyin; both picture directions = one class) AND ≥2 distinct UTC dayKeys, stored bounded as `{modeClass → earliestDayKey}`. **Single-mode items** (e.g. grammar words = pinyin-only by spec): MASTERED relaxes to ≥2 distinct days in that one mode — the two-*day* spacing is universal; two-*mode* applies wherever ≥2 modes exist. Content test asserts every item has ≥1 reachable mode class and correctly classifies which rule applies.
2. **Deferred items (dissolves the pinyin-off deadlock and the empty-manifest launch state).** An item with zero currently-eligible modes (no audio, no visual, pinyin toggle off) is **deferred**: skipped by the sampler, excluded from the "fresh" count so expansion flows past it, counted on the progress screen ("N 个字需要拼音模式/语音"), and listed by `audio-manifest-check` as blocked-by-asset vs blocked-by-toggle. A parent-panel nudge fires when deferred-by-toggle items accumulate. Consequence stated plainly: the full /700 claim requires audio coverage and (for grammar words) eventually enabling pinyin mode — inherent to the spec's own rules.
3. **Leveling constants** `{3,4,6,8,8}` from code, not README's "5" (owner sign-off below).
4. **Retry pays 0** under the new economy (web paid +1): accuracy is the income lever; warm-up doubling + uncapped clean solves carry the 70%-sim target. Retry keeps web's learning-kindness elsewhere (no penalty, warm streak held).
5. **Charge flash = mission generator behind the item interface.** `Generator` consumes `QuizItem` (text/components/…), never a bare char — month-2 word flashes become a data addition. Two pending namespaces (mission/flash), one validation path; flash skips Leveling/Mastery/Economy. Ghost-feeding **accuracy = rolling 200 mission answers only** (clamped 0.2–0.9 at publish).
6. **Feed & tail.** Feed level per beast-slot, survives `Refuse` swaps by construction; reaching level n costs n🪙. Curve reading: start 0, 0→10 = 55🪙 cumulative (~220 for four slots); the spec's "54/≈200" matches the 1→10 sub-span — recommend the clean 0-start curve (sign-off below). TAIL splash = `1 + floor(feedTAIL/3)` to the tail animal's naturally-highest innate stat (tie-break 力>速>智), final cap 10 — "+1 at rest" stays true, tail feeding stays meaningful. LEGS/TAIL feedable only post-unlock; pre-unlock 速 = body animal's innate. Foods: 肉→力(BODY) 果→速(LEGS) 鱼→智(HEAD) 蛋→TAIL, each with pinyin + audio keys.
7. **Rigs.** `RigData`: four modules of primitive parts + features (mane/shell/wings/whiskers), fixed socket contract. `RigMath` (pure): module scale = 1 + 0.06·max(0, slotStat − baseline), clamp ×1.55, axis emphasis (legs length-dominant, body bulk, head uniform, tail length), sockets re-solved so plugs always meet. `geometry-check` runs the full min/max matrix headless: caps, socket alignment, no NaN, pairwise occupancy-grid silhouette distinctness *including* A-head/B-body vs B-head/A-body swaps (criterion 8b). Sparkle at feed 10 engine-side; idle/walk client-side procedural.
8. **Curriculum resegmentation.** Primary order = 识字表 sequence, 14 bands × 50 (frequency tie-breaks only within compilation); web's 6 thematic bands discarded; `category` kept + extended across 700 solely for distractor ring 1. Deck/prefix/expansion mechanics port unchanged.
9. **Homophone at scale** via generated `HomophoneIndex` (O(1)); content test guarantees ≥2 valid distractors per listen-eligible item; 10k-draw property test proves zero violations.
10. **Audio/icon degradation (criterion 9, generalized).** `ModePicker` deletes ineligible modes per item/manifest coverage, renormalizes, never errors: empty audio manifest ⇒ zero listen questions silently; partial ⇒ listen only for covered items; same pattern for the icon manifest and picture modes. Tested with empty/partial/full manifests.
11. **Daily caps** on UTC dayKey (server clock), stored in `profile.daily`, lazy rollover; owner-facing rollover time documented.
12. **Analytics**: `{t, sessionId, userId, type faucet|sink|quiz|battle|session, code, amount, meta}` buffered, flushed 60s + on leave to `Analytics_v1` key `{dateKey}/{jobId}`; session summary carries per-code faucet/sink totals + accuracy.
13. **Persistence**: vendored **ProfileStore** (loleris) — session-locking, autosave — wrapped by `ProfileService` with our `schemaVersion` + `Migrations` chain and injectable store for headless tests.
14. **Ghost pool**: DataStore snapshots + MemoryStore recency index + starter-ghost data fallback.
15. **Onboarding (user-decided)**: scripted tutorial gifts 猫 and 鸟 exempt from the gate → first fusion inside 15 minutes; all other rescues enforce MASTERED + tier.
16. **Battle ties**: rev-3 replay-with-new-picks supersedes web's ties-go-to-kid; safety valve after 3 consecutive ties.

## 5. Milestones

Every milestone ends green on: `lune run scripts/run-tests` · `selene src tests scripts` · `stylua --check .` · `scripts/build-place.sh`; lands as one commit on `main`.

- **M1 — Scaffold, curriculum pipeline, persistence.** Configs, testkit, all scripts, `data-src/*` (700 compiled + `CURRICULUM_REVIEW.md`), generated `Data/*`, `Types`, `Config`, `Util/*`, vendored ProfileStore, `ProfileService` + migrations + mock store, `Net` shell, entry points. *Verify:* build-data validators; `content/` suite (criterion 2); `profile/` suite (criterion 6 basics); `audio-manifest-check` reports all-unfilled.
- **M2 — Quiz engine, mastery, Kiosk, Progress Board.** `Quiz/*`, `QuizService`, `EconomyService` (faucets + warm-up), `WorldService` (hub/kiosk/board), Quiz/Audio/Progress controllers + UI. *Verify:* criterion 1 quiz/leveling/mastery (mode mix ±5%/1000, numbers 4×, homophone 10k), criterion 9 degradation, criterion 8 band math.
- **M3 — Procedural animals, plots, rescue/feed, slot fusion.** `Rig/*`, `Fusion/*`, Zoo/Plot/Creature services, Anim/Zoo/Plot controllers, lab/rescue/feed/naming UI, `geometry-check`. *Verify:* fusion math suite (slot stats, tail splash, feed persistence across swaps, real-word any-pair both orders, curve), rescue gating, criterion 8b headless, zoo-remote exploit specs.
- **M4 — Battle v2, 12 NPC rungs.** `Battle/{Resolver,NpcBrain}`, `BattleService` NPC path + flash orchestration, arena, battle UI, 12-rung data (4 new NPCs in web style), slot gating at rungs 4/8. *Verify:* charge×triangle truth table, tie replay, NPC charge curve, scripted sim proving rung 1 beatable by a starter 2-part beast, forged-result/flash exploit specs.
- **M5 — Ghosts, live battles, social.** `GhostService`, `GhostBrain`, live path (challenge pad, simultaneous flashes), cheer wheel, hover cards, publish hooks. *Verify:* ghost specs (accuracy clamp, weighting, cooldowns/caps vs mocked stores), live state machine; draft `STUDIO_CHECKLIST.md` two-account script (criteria 4, 5).
- **M6 — Economy tuning, security pass, polish.** `coin-flow-sim`, `AnalyticsService`, full caps, decorations/colorways, celebrations, golden real-word variant, final `STUDIO_CHECKLIST.md` + `LIVEOPS.md`. *Verify:* criterion 7 sim (first fusion ≤15 min at 70%; mission share 65–75% over 10h; 40h sinks > faucets), complete criterion 3 suite, full run, final manifest report; owner runs Studio checklist (criteria 4, 5, device 汉字 rendering).

## 6. Owner sign-offs & risks

1. **Curriculum accuracy** beyond the web's 236 is model-compiled — the store claim rests on your `CURRICULUM_REVIEW.md` spot-check (low-confidence first). Corrections are data-only.
2. **Leveling constants** {3,4,6,8,8} over the stale "5". 3. **Feed curve** 0→10 = 55🪙 (spec's 54 = the 1→10 span). 4. **Tie replay** supersedes web's kid-favoring ties. — all recommended; adjust any in `Config` later.
5. **Audio is the long pole**: engine degrades gracefully, but listen mode (the dominant mode) exists only where clips exist — suggested cadence: one band batch per week, tracked by `audio-manifest-check`.
6. **Deferred-items consequence**: full /700 requires audio coverage and eventually the pinyin toggle for grammar words (spec's own rules); surfaced in-game, never an error.
7. **darklua require conversion** edge cases: contained to the build script; fallback is emitting engine-require stubs from `build-data`.

## Verification (end-to-end)

Headless, per milestone and at the end: `lune run scripts/run-tests` (all suites), `lune run scripts/build-data` (content integrity), `lune run scripts/geometry-check` (8b), `lune run scripts/coin-flow-sim` (7), `lune run scripts/audio-manifest-check` (2/9), `selene` + `stylua --check`, `scripts/build-place.sh` producing `build.rbxl`. Owner-side: sync via `rojo serve` or open `build.rbxl`, then `STUDIO_CHECKLIST.md` — two-account mission/rescue/fuse-both-orientations/slot-unlock/plot-visit/live-battle script (criterion 4), ghost-of-other-account with accuracy-reflecting charge (5), leave/rejoin + crash sim (6), progress screen (8), silhouette screenshots (8b), device CJK font check.
