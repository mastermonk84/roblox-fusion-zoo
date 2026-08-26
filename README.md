# 融合动物园 Fusion Zoo — Roblox

Native Roblox rebuild of the Fusion Zoo Mandarin character game. Learning and
reward are separate systems: character quizzes mint coins, coins build a zoo of
fusable chimera beasts, beasts battle. Content target: the full 部编版 Grade-1
识字表 — 700 characters.

**Read `PLAN.md` first** — architecture, module layout, milestones.
`CURRICULUM_REVIEW.md` is the owner's spot-check list for the compiled 700.

## Working on it

```bash
rokit install                      # rojo, lune, stylua, selene, darklua
lune run scripts/run-tests         # headless test suites
lune run scripts/build-data        # data-src/*.json -> src/shared/Data/*.luau
lune run scripts/audio-manifest-check
scripts/build-place.sh             # build/fusion-zoo.rbxl for Studio
rojo serve                         # live-sync to Studio instead
```

All logic is Luau under `src/` (string requires; darklua converts for the
Roblox build). Nothing is hand-placed in Studio. Content lives in `data-src/`
JSON and is generated into `src/shared/Data/` — content fixes never touch code.
