--!strict
-- Reports audio manifest coverage by band so recording order can track band
-- order (spec requirement). Also reports icon coverage and items currently
-- blocked from every mode. Run: lune run scripts/audio-manifest-check

local fs = require("@lune/fs")
local serde = require("@lune/serde")

type Item = {
	text: string,
	pinyin: string,
	band: number,
	needs_visual: boolean,
	grammar: boolean,
	bonus: boolean?,
}

local curriculum = serde.decode("json", fs.readFile("data-src/curriculum_grade1.json")) :: { Item }
local audio =
	serde.decode("json", fs.readFile("data-src/audio_manifest.json")) :: { [string]: string }
local icons =
	serde.decode("json", fs.readFile("data-src/icon_manifest.json")) :: { [string]: string }

local byBand: { [number]: { total: number, audio: number, icons: number, missingAudio: { string } } } =
	{}
local blockedByAsset: { string } = {}
local pinyinOnly: { string } = {}

for _, item in curriculum do
	local band = byBand[item.band]
	if not band then
		band = { total = 0, audio = 0, icons = 0, missingAudio = {} }
		byBand[item.band] = band
	end
	band.total += 1
	if audio[item.text] then
		band.audio += 1
	elseif not item.grammar then
		table.insert(band.missingAudio, item.text)
	end
	if icons[item.text] then
		band.icons += 1
	end
	if item.grammar then
		table.insert(pinyinOnly, item.text)
	elseif not audio[item.text] and not (item.needs_visual and icons[item.text]) then
		table.insert(blockedByAsset, item.text)
	end
end

print("band | items | audio | icons | unfilled audio (record these in band order)")
print("-----|-------|-------|-------|-------")
for band = 1, 14 do
	local b = byBand[band]
	if b then
		local missing = table.concat(b.missingAudio, "")
		if #b.missingAudio > 20 then
			missing = `{string.sub(missing, 1, 60)}… ({#b.missingAudio} chars)`
		end
		print(`{band} | {b.total} | {b.audio} | {b.icons} | {missing}`)
	end
end
print("")
print(`listen-eligible items still without audio: {#blockedByAsset}`)
print(
	`pinyin-only grammar words (need the per-player toggle): {#pinyinOnly} — {table.concat(
		pinyinOnly,
		" "
	)}`
)
print("")
print("Until an item has audio it is served through picture/pinyin modes only;")
print("with no eligible mode at all it is deferred (skipped, shown on the progress")
print("screen as waiting) — never an error.")
