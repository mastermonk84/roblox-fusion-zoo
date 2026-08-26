# 融合动物园 Fusion Zoo — Roblox

Native Roblox rebuild of the Fusion Zoo Mandarin character game. Learning and
reward are separate systems: character quizzes mint coins, coins build a zoo of
fusable chimera beasts, beasts battle — NPC rungs, ghosts of real players, and
live matches. Content: the full 部编版 Grade-1 识字表, 700 characters, with a
two-mode/two-day mastery model behind every unlock.

- `PLAN.md` — architecture, module layout, milestone plan (the build followed it)
- `CURRICULUM_REVIEW.md` — the compiled 700 for the owner's textbook spot-check
- `STUDIO_CHECKLIST.md` — the in-Studio verification script (2-account tests)
- `LIVEOPS.md` — post-launch roadmap (documented, deliberately unbuilt)

## Commands

```bash
rokit install                        # rojo, lune, stylua, selene, darklua
lune run scripts/run-tests           # 129 headless tests (add -- --filter x)
lune run scripts/build-data          # data-src/*.json -> src/shared/Data/*.luau
lune run scripts/compile-curriculum  # rebuild the 700-char list + review file
lune run scripts/geometry-check      # every rig combo valid + silhouettes distinct
lune run scripts/coin-flow-sim       # economy targets (criterion 7)
lune run scripts/audio-manifest-check# audio/icon coverage by band
scripts/build-place.sh               # build/fusion-zoo.rbxl (darklua requires)
rojo serve                           # live-sync to Studio instead
selene src tests scripts && stylua --check src tests scripts
```

## Shape

`src/shared` — pure logic (quiz engine, mastery, battle, fusion, rigs, economy),
all headless-tested. `src/server` — thin services; the only writers of coins,
mastery, beasts, battles; every remote runs guard → rate limit → session auth.
`src/client` — renders server responses, computes nothing. Nothing is
hand-placed in Studio; the world builds itself at server start.

Content is data: `data-src/*.json` → generated `src/shared/Data/*` modules.
A new animal, real-word combo, colorway, or audio batch is a JSON edit plus
`lune run scripts/build-data` — no code changes (CI-checked).

## Before kids play (owner tasks)

1. Spot-check `CURRICULUM_REVIEW.md` against the textbook (low-confidence rows
   first); corrections are edits to `data-src/raw/*.json`.
2. Record + upload audio clips band by band; fill `data-src/audio_manifest.json`
   (until then, listen mode quietly serves only covered items — with no assets
   and pinyin off, the kiosk shows a friendly waiting card).
3. Upload picture decals for `needs_visual` items into `data-src/icon_manifest.json`.
4. Run `STUDIO_CHECKLIST.md` with two accounts.
