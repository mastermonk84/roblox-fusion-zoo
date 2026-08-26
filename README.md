# 融合动物园 Fusion Zoo — Roblox

The Roblox build of Fusion Zoo, the Mandarin character game for Sienna, Luke & cousin Lele.
Same two-system design as the [web version](https://github.com/mastermonk84/fusion-zoo):
**missions teach, coins reward**. Recognising a character earns coins; coins buy animals,
fusions and battles. Nothing in the zoo ever teaches — it only pays out.

## Getting it running

```bash
rokit install                 # installs rojo, stylua, selene (https://github.com/rojo-rbx/rokit)
rojo serve                    # then in Studio: Plugins → Rojo → Connect
```

Or build a place file without Studio syncing:

```bash
rojo build -o build/fusion-zoo.rbxlx
```

In Studio, enable **Game Settings → Security → Enable Studio Access to API Services** if you
want saves to persist; without it the server logs a warning and runs in memory.

## Layout

| Path | Becomes | What it holds |
| --- | --- | --- |
| `src/shared/` | `ReplicatedStorage.Shared` | Data + rules both sides need |
| `src/server/` | `ServerScriptService.Server` | Every coin decision, DataStore saves |
| `src/client/` | `StarterPlayerScripts.Client` | The whole UI, built in code |

The client never computes a stat or a coin — it sends an action name, the server answers, and
the server pushes the full save back down. That keeps exploits to "spam a button".

## The loop

- **Missions** — a character appears with four English choices. First try pays 🪙2, second 🪙1,
  a second miss reveals the answer and pays nothing. Server-side `pending` state means an answer
  can't be replayed for coins.
- **Zoo** — rescue an animal (🪙5), feed +1 to 力💪 / 速⚡ / 智🧠 (🪙2, cap 10), fuse any two
  beasts (🪙10). Stats add; names concatenate, so 马 + 蛙 = 马蛙. A chimera can go six parts deep.
- **Real words** — 熊 + 猫 spells 熊猫 (panda 🐼), so it gets the celebration and a proper name.
  Ordered pairs only — 猫熊 is just a chimera. See `REAL_WORDS` in `src/shared/Fusion.luau`.
- **Battles** — best-of-3 against a monster ladder. Each round both sides reveal a random stat;
  the triangle 速⚡打败力💪 · 智🧠打败速⚡ · 力💪打败智🧠 doubles an advantaged stat, higher number
  wins, ties go to the kid. First win on a rung pays 🪙3 and unlocks the next monster.

## Tuning

Everything numeric lives in `src/shared/Config.luau` — costs, the stat cap, chimera depth, bounty,
autosave interval. The animal pool is `src/shared/Animals.luau` (each entry needs a character,
pinyin, an unambiguous emoji and three stats); the ladder is `src/shared/Monsters.luau`.

## Not built yet

- Missions only quiz character→English. The web version's listen→character mode is the one that
  matters most for these kids and needs audio assets.
- The zoo is a list in a GUI, not a place you walk around in. Beast models are the obvious next step.
- No per-kid mastery tracking (the web version's "3 clean solves = mastered") — saves are per Roblox
  account, so a shared iPad means a shared save.
