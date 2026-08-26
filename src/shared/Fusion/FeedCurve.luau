--!strict
-- Feed levels start at 0; raising a slot's feed level TO n costs n coins.
-- 0→10 on one slot = 55🪙 cumulative; a maxed four-slot beast ≈ 220🪙 —
-- the primary long-term sink (owner sign-off: spec's "54" read as the 1→10
-- span; the clean 0-start curve was recommended and adopted).

local Config = require("../Config")

local FeedCurve = {}

function FeedCurve.costToNext(currentLevel: number): number?
	if currentLevel >= Config.Fusion.FEED_CAP then
		return nil
	end
	return currentLevel + 1
end

function FeedCurve.cumulative(level: number): number
	return level * (level + 1) / 2
end

return FeedCurve
