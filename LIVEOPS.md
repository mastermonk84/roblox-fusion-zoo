# LIVEOPS — post-launch roadmap (documented now, built later)

Launch content carries ~2 months of real kid time; the 700-character journey is
6–12. Retention comes from update cadence. v1's architecture leaves a clean,
named extension point for each item below — every one is either a data drop or
reuses a module that already exists. **Nothing in this file ships in v1.**

## Monthly — animal drips (no-code-change content drops)
New species land in the band-gated rescue pool at roughly one per month
(launch 18 → ~35 over year one). The entire drop is data:
1. `data-src/animals.json`: one entry (char, pinyin, english, stats, tier, rig key).
2. `data-src/rigs.json`: one procedural build (colors, proportions, features).
3. If the char is outside the 700: one `data-src/raw/bonus_chars.json` entry
   (band placement) — the pipeline already treats bonus items as quizzable but
   excluded from the /700 claim.
4. `lune run scripts/build-data` → commit. The rescue pen, fusion lab, rigs,
   and quiz engine pick it up with zero code edits (this is CI-verified today:
   build-data validates every animal has a rig and a quiz item).
Optional same-drop extras: a `words.json` combo if the newcomer spells
something real (each new animal should ideally land one), plus its
`audio_manifest.json` clip.

## Month 2 — word charge flashes
From ~band 8, battle flashes may serve two-character words composed of the
player's MASTERED characters. The extension point is already load-bearing:
- The item schema is word-shaped (`text: "朋友"`, `components: ["朋","友"]`),
  and `Quiz/Generator` + `BattleService` consume the QuizItem interface only —
  `submitFlash` never sees a char field.
- Work: a `words_quiz.json` source compiled into extra items (band = max
  component band), a Generator pool filter for flash context (`components`
  all mastered, band ≥ 8), audio manifest entries per word. Missions stay
  single-character; only the flash pool widens.

## Month 3 — weekly server boss
A hub world boss with shared HP, damaged by own-level charge flashes from
every kid in the server; participation bounty on the weekly clear.
- Reuses `QuizService.generateFlash`/`submitFlash` UNCHANGED (the spec's hard
  requirement) — a `BossService` orchestrates: flash correct → damage tick =
  f(player level), pushed via the existing `Battle/Events` RemoteEvent channel.
- New: boss rig (one `rigs.json` entry at huge scale), shared-HP MemoryStore
  key, weekly reset cron keyed on `Time.dayKey`, participation faucet code
  (`boss_bounty`) added to `Economy/Ledger` + its cap test.

## Month 4 — word dex 词语图鉴
A collection book of real words discovered through fusion combos, silhouetted
empty slots for the undiscovered.
- `profile.realWordsFound` already records discovery (once-per-combo payout
  depends on it), and `data-src/words.json` is the catalog. Work is one screen
  (client) + a `Zoo/GetWordDex` RF returning found/total per word.
- Grows alongside animal drips: every new combo lands a silhouette first.

## Ongoing paint (name it as paint — none of it mints coins)
- **Zone expansions** as bands clear: `WorldService.ANCHORS` is the single
  layout table; a new zone is a build function + anchor.
- **Seasonal ghost leagues** with trophy resets: `GhostService` snapshots
  already carry `publishedAt`; a league is an index-name rotation
  (`GhostIndex_s2`) + a trophy row on the hover card.
- **Titles/badges on hover cards**: `CreatureService` attributes are the
  surface; titles are a data catalog + one attribute.
- **Rotating daily quests**: read-only goals over analytics counters the
  Ledger already tracks ("win 2 ghost battles", "5 clean solves in listen
  mode"); pay from existing faucet codes under existing caps.
- **Colorway drops**: `data-src/colorways.json` append + build-data. Zero code.

## Explicitly still out of scope (v2+ decisions, not drift)
Trading, live tournaments, slot abilities (rerolls, peek-then-pick), custom
meshes/animations, monetization of any kind, leaderboards beyond the ladder
rung display, mainland China distribution, writing/stroke practice.
