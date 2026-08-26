--!strict
-- Compiles the 700-item Grade-1 curriculum from raw sources:
--   data-src/raw/shangce_300.json + xiace_400.json  (识字表 reconstruction, by lesson)
--   data-src/raw/web_characters.json                (236 poster chars from the web game)
-- into data-src/curriculum_grade1.json (canonical item list, word-shaped schema)
-- and regenerates CURRICULUM_REVIEW.md for the owner's textbook spot-check.
--
-- Run rarely: lune run scripts/compile-curriculum

local fs = require("@lune/fs")
local serde = require("@lune/serde")

type RawChar = { string } -- [char, pinyin, english, confidence?]
type RawLesson = { unit: string, lesson: string, chars: { RawChar } }
type RawSemester = { semester: string, target: number, lessons: { RawLesson } }
type WebChar = {
	char: string,
	pinyin: string,
	english: string,
	emoji: string?,
	value: number?,
	band: number,
	category: string,
	quizzable: boolean,
	source: string,
}

local BAND_SIZE = 50

-- Pure function words: pinyin-mode only (spec hard rule — homophone density
-- makes listen mode miserable, and they have no picture).
local GRAMMAR = {
	["的"] = true,
	["了"] = true,
	["着"] = true,
	["么"] = true,
	["吗"] = true,
	["呢"] = true,
	["吧"] = true,
	["呀"] = true,
	["啦"] = true,
	["们"] = true,
	["之"] = true,
}

-- Coarse category heuristic for chars the web data doesn't cover; the owner can
-- correct any of these in the emitted JSON (they only steer distractor ring 1).
local CATEGORY_RULES: { { pattern: string, category: string } } = {
	{ pattern = "surname", category = "person" },
	{ pattern = "particle", category = "abstract" },
	{ pattern = "measure", category = "modifier" },
	{ pattern = "sound", category = "abstract" },
	{ pattern = "bird", category = "animal" },
	{ pattern = "frog", category = "animal" },
	{ pattern = "ant", category = "animal" },
	{ pattern = "spider", category = "animal" },
	{ pattern = "dragonfly", category = "animal" },
	{ pattern = "magpie", category = "animal" },
	{ pattern = "lion", category = "animal" },
	{ pattern = "deer", category = "animal" },
	{ pattern = "swallow", category = "animal" },
	{ pattern = "mosquito", category = "animal" },
	{ pattern = "aphid", category = "animal" },
	{ pattern = "monkey", category = "animal" },
	{ pattern = "eyebrow", category = "body" },
	{ pattern = "nose", category = "body" },
	{ pattern = "neck", category = "body" },
	{ pattern = "arm", category = "body" },
	{ pattern = "belly", category = "body" },
	{ pattern = "leg", category = "body" },
	{ pattern = "foot", category = "body" },
	{ pattern = "tongue", category = "body" },
	{ pattern = "face", category = "body" },
	{ pattern = "eye", category = "body" },
	{ pattern = "waist", category = "body" },
	{ pattern = "wing", category = "body" },
	{ pattern = "frost", category = "nature" },
	{ pattern = "thunder", category = "nature" },
	{ pattern = "ice", category = "nature" },
	{ pattern = "pond", category = "nature" },
	{ pattern = "lake", category = "nature" },
	{ pattern = "river", category = "nature" },
	{ pattern = "cloud", category = "nature" },
	{ pattern = "willow", category = "nature" },
	{ pattern = "poplar", category = "nature" },
	{ pattern = "lotus", category = "nature" },
	{ pattern = "dew", category = "nature" },
	{ pattern = "spring %(water", category = "nature" },
	{ pattern = "duckweed", category = "nature" },
	{ pattern = "sand", category = "nature" },
	{ pattern = "islet", category = "nature" },
	{ pattern = "firefly", category = "nature" },
	{ pattern = "rice", category = "food" },
	{ pattern = "bean", category = "food" },
	{ pattern = "meat", category = "food" },
	{ pattern = "soup", category = "food" },
	{ pattern = "melon", category = "food" },
	{ pattern = "dumpling", category = "food" },
	{ pattern = "cotton", category = "object" },
	{ pattern = "bed", category = "object" },
	{ pattern = "window", category = "object" },
	{ pattern = "mirror", category = "object" },
	{ pattern = "rope", category = "object" },
	{ pattern = "ball", category = "object" },
	{ pattern = "boat", category = "object" },
	{ pattern = "stick", category = "object" },
	{ pattern = "fan", category = "object" },
	{ pattern = "chair", category = "object" },
	{ pattern = "clock", category = "object" },
	{ pattern = "pencil", category = "object" },
	{ pattern = "skirt", category = "object" },
	{ pattern = "robe", category = "object" },
	{ pattern = "net", category = "object" },
	{ pattern = "well", category = "object" },
	{ pattern = "wall", category = "object" },
	{ pattern = "house", category = "object" },
	{ pattern = "toilet", category = "place" },
	{ pattern = "village", category = "place" },
	{ pattern = "capital", category = "place" },
	{ pattern = "field", category = "place" },
	{ pattern = "morning", category = "time" },
	{ pattern = "dusk", category = "time" },
	{ pattern = "night", category = "time" },
	{ pattern = "festival", category = "time" },
	{ pattern = "week", category = "time" },
	{ pattern = "period", category = "time" },
}

local function guessCategory(english: string): string
	local lower = string.lower(english)
	for _, rule in CATEGORY_RULES do
		if string.find(lower, rule.pattern) then
			return rule.category
		end
	end
	-- verbs and everything else: action-ish glosses are hard to detect reliably;
	-- default to abstract (ring 1 then rarely fires; ring 2 band carries it).
	return "abstract"
end

local function readJson(path: string): any
	return serde.decode("json", fs.readFile(path))
end

local shang = readJson("data-src/raw/shangce_300.json") :: RawSemester
local xia = readJson("data-src/raw/xiace_400.json") :: RawSemester
local web = readJson("data-src/raw/web_characters.json") :: { WebChar }

local webByChar: { [string]: WebChar } = {}
for _, w in web do
	webByChar[w.char] = w
end

type Item = {
	text: string,
	components: { string },
	pinyin: string,
	english: string,
	band: number,
	seq: number,
	source: string,
	category: string,
	needs_visual: boolean,
	grammar: boolean,
	value: number?,
	confidence: string,
	bonus: boolean?,
}

local items: { Item } = {}
local seen: { [string]: boolean } = {}
local pinyinMismatches: { string } = {}

local function addSemester(sem: RawSemester)
	for _, lesson in sem.lessons do
		for _, raw in lesson.chars do
			local char, pinyin, english, flag = raw[1], raw[2], raw[3], raw[4]
			assert(not seen[char], `duplicate char {char}`)
			seen[char] = true
			local seq = #items + 1
			local w = webByChar[char]
			local confidence = if w then "web" elseif flag == "low" then "low" else "model"
			if w then
				if w.pinyin ~= pinyin then
					table.insert(pinyinMismatches, `{char}: raw "{pinyin}" -> web "{w.pinyin}"`)
				end
				pinyin = w.pinyin -- the web values shipped to real kids; trust them
				english = w.english
			end
			table.insert(items, {
				text = char,
				components = { char },
				pinyin = pinyin,
				english = english,
				band = math.ceil(seq / BAND_SIZE),
				seq = seq,
				source = `{sem.semester} {lesson.lesson}`,
				category = if w then w.category else guessCategory(english),
				needs_visual = if w then w.quizzable else false,
				grammar = GRAMMAR[char] == true,
				value = if w then w.value else nil,
				confidence = confidence,
			})
		end
	end
end

addSemester(shang)
addSemester(xia)

assert(#items == 700, `expected 700 items, got {#items}`)

-- Bonus items: off-curriculum chars the game needs — zoo animals outside the
-- 识字表, plus web-poster chars whose lesson could not be confirmed by source
-- verification. Quizzable and masterable, excluded from the /700 claim. Poster
-- chars take their metadata from the web data; the rest are animals.
type BonusChar = { char: string, pinyin: string, english: string, band: number }
local bonus = readJson("data-src/raw/bonus_chars.json") :: { note: string, chars: { BonusChar } }
for _, b in bonus.chars do
	assert(not seen[b.char], `bonus char {b.char} already in curriculum`)
	seen[b.char] = true
	local w = webByChar[b.char]
	table.insert(items, {
		text = b.char,
		components = { b.char },
		pinyin = if w then w.pinyin else b.pinyin,
		english = if w then w.english else b.english,
		band = b.band,
		seq = #items + 1,
		source = if w then "bonus (poster char pending textbook check)" else "bonus (zoo animal)",
		category = if w then w.category else "animal",
		needs_visual = if w then w.quizzable else true,
		grammar = GRAMMAR[b.char] == true,
		value = if w then w.value else nil,
		confidence = "web",
		bonus = true,
	})
end

-- Mechanical invariant: every web poster char must exist somewhere in the game
-- (curriculum or bonus) — the web game's content never silently disappears.
local missingPoster: { string } = {}
for _, w in web do
	if not seen[w.char] then
		table.insert(missingPoster, w.char)
	end
end
assert(
	#missingPoster == 0,
	`poster chars missing from curriculum+bonus: {table.concat(missingPoster, " ")}`
)

-- Emit canonical curriculum
fs.writeFile("data-src/curriculum_grade1.json", serde.encode("json", items, true))

-- ── CURRICULUM_REVIEW.md ────────────────────────────────────────────────────
local counts = { web = 0, model = 0, low = 0 }
for _, item in items do
	if not item.bonus then
		counts[item.confidence] += 1
	end
end

local lines: { string } = {}
local function push(line: string)
	table.insert(lines, line)
end

push("# CURRICULUM_REVIEW — 部编版一年级识字表 (700 characters)")
push("")
push(
	"**Generated by `lune run scripts/compile-curriculum` — do not edit; correct the raw JSONs instead.**"
)
push("")
push("This file exists for the owner's spot-check against the physical textbook before the")
push('store-page claim ("all 700 Grade 1 characters") ships. The compilation is model-knowledge')
push("anchored to the web game's 236 poster characters; the sections below surface the least")
push("certain entries first. To correct anything: edit `data-src/raw/shangce_300.json` /")
push("`xiace_400.json` (move, add, remove, or re-spell entries), rerun the compile script, then")
push("`lune run scripts/build-data`. No code changes are ever needed for content fixes.")
push("")
push("## Verification status")
push("")
push("- **Pinyin axis: owner-verified 2026-08-26** — the owner reviewed the full list and")
push('  confirmed "everything aligns with standard Mandarin pronunciation."')
push("- **Lesson membership: independently re-verified against web sources 2026-08-26.**")
push("  ~20 lessons/stations were confirmed character-by-character; the errata (below) were")
push("  applied to the raw JSONs. Remaining open items for the physical textbook:")
push("  the demoted poster chars (next section), the trimmed 13th char of 小壁虎借尾巴")
push("  (难 or 转), and the lessons not individually confirmed (marked `·` in the band list).")
push("")
push("### Errata applied 2026-08-26 (source-verified)")
push("")
push(
	"- Removed (not in the verified lesson lists): 沙 洲 面 (吃水不忘挖井人) · 偷 (小公鸡和小鸭子)"
)
push(
	"  · 鹊 (树和喜鹊) · 剥 (端午粽) · 荡 眨 (彩虹) · 苞 刨 (园地五) · 撑 艇 (古诗二首)"
)
push(
	"  · 哈 欠 悔 (一分钟) · 狮 (动物王国开大会) · 蚜 盼 (棉花姑娘) · 湖 (咕咚) · 厕 (园地八) · 难 (小壁虎借尾巴, trimmed)"
)
push(
	"- Added (recovered from verified lists): 暑 (古对今) · 她 (文具的家) · 背 刚 汽 (一分钟)"
)
push("  · 辆 匹 册 支 棵 架 (园地二, measure words) · 饭 能 茶 轻 鞭 (园地五)")
push("  · 吵 胖 岁 现 票 交 弓 甘 (园地七) · 刷 梳 巾 擦 皂 澡 盆 (园地八)")
push(
	"  · 遥 (我多想去看看) · 河 (小公鸡和小鸭子) · 梦 (一个接一个) · 挖 (吃水不忘挖井人 — round-1 removal reversed)"
)
push("- Moved: 铅 (文具的家 → 园地二) · 夜 (夜色 → 静夜思)")
push("")
push("### Official re-listings (multi-reading characters)")
push("")
push("The official 识字表 re-lists a character when a new reading is taught: at least")
push(
	"觉 (jué 上册 / jiào 一个接一个) · 只 (zhī 上册 / zhǐ 树和喜鹊) · 种 (zhǒng 一个接一个 / zhòng 树和喜鹊)"
)
push(
	"· 得 (dé 上册 / děi 怎么都快乐) · 数 (shù 拼音 ai-ei-ui / shǔ 雨点儿 — both 上册)."
)
push("The game holds one item per character, so a re-listed entry is covered by its first")
push('appearance — the official "300+400" counts a few more ENTRIES than there are unique')
push("characters. Each known re-list slot is filled by an explicitly-marked extension char")
push(
	"(扩展位: 读 fills the 数 slot in 上册). Owner: while checking the textbook, please note"
)
push("every re-listed entry so remaining slots are filled deliberately, not by leftover padding.")
push("")
push("### ⚠ Demoted chars — need a textbook ruling")
push("")
push(
	"8 web-poster chars found **no** home in any source-verified lesson: 柳 名 班 级 菜 内 先 件"
)
push("(读 was promoted back as the 扩展位 extension char). 4 more were demoted after round-2")
push(
	"verification: 主 叫 (listed as 会写字 for 吃水不忘挖井人, absent from its 会认 enumeration)"
)
push(
	"· 闷 (要下雨了 sources disagree) · 期 (上册园地五 verified as exactly 午晚昨今年)."
)
push("All live as bonus items (quizzable, masterable, excluded from the /700 claim).")
push("If the textbook shows a 识字表 home for any of them, move it back into the raw JSON")
push("(and rebalance that semester to its exact count) — a data-only edit.")
push("")
push(`| confidence | count | meaning |`)
push(`|---|---|---|`)
push(`| web | {counts.web} | also in the battle-tested web game's poster data |`)
push(`| model | {counts.model} | reconstructed from model knowledge of the 识字表 |`)
push(`| low | {counts.low} | best-effort fill — CHECK THESE FIRST |`)
push("")
push(
	"**Known caveat:** the kickoff spec assumed the 236 poster chars were a subset of the 上册 300."
)
push(
	"They are not quite: some belong to 下册 lessons (姓氏歌, 文具的家, 夜色 …) and 9 found no"
)
push(
	"verified 识字表 home at all (demoted to bonus, above). The mechanically enforced invariant"
)
push("is: all 236 poster chars ∈ curriculum ∪ bonus. ✓")
push("")

push("## ⚠ Low-confidence entries — verify against the textbook first")
push("")
push("| # | 字 | pinyin | band | placed in |")
push("|---|---|---|---|---|")
for _, item in items do
	if item.confidence == "low" then
		push(`| {item.seq} | {item.text} | {item.pinyin} | {item.band} | {item.source} |`)
	end
end
push("")

if #pinyinMismatches > 0 then
	push("## Pinyin corrections applied (web data won over the reconstruction)")
	push("")
	for _, m in pinyinMismatches do
		push(`- {m}`)
	end
	push("")
end

push("## Full list by band (识字表 order, 50 per band)")
push("")
for band = 1, 14 do
	local chunk: { string } = {}
	local from, to = "", ""
	for _, item in items do
		if item.band == band and not item.bonus then
			if from == "" then
				from = item.source
			end
			to = item.source
			local marker = if item.confidence == "low"
				then "?"
				elseif item.confidence == "model" then "·"
				else ""
			table.insert(chunk, item.text .. marker)
		end
	end
	push(`### Band {band}  ({from} → {to})`)
	push("")
	push(table.concat(chunk, " "))
	push("")
end
push("Markers: `?` = low confidence, `·` = model-reconstructed (unmarked = web-verified).")
push("")

fs.writeFile("CURRICULUM_REVIEW.md", table.concat(lines, "\n"))

print(
	`curriculum_grade1.json: {#items} items = 700 curriculum ({counts.web} web / {counts.model} model / {counts.low} low) + {#bonus.chars} bonus`
)
print(`CURRICULUM_REVIEW.md regenerated`)
if #pinyinMismatches > 0 then
	print(`pinyin corrections from web data: {#pinyinMismatches}`)
end
