--!strict
-- Fusion Zoo server. The client sends an action name, the server decides what
-- it costs and what happens, then pushes the whole (small) save back down.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Animals = require(Shared.Animals)
local Battle = require(Shared.Battle)
local Config = require(Shared.Config)
local Fusion = require(Shared.Fusion)
local Monsters = require(Shared.Monsters)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local PlayerData = require(script.PlayerData)

local action, state = Remotes.server()
local random = Random.new()

-- One open quiz question per player, so answers cannot be replayed for coins.
local pending: { [Player]: { char: string, choices: { string }, correct: number, attempts: number } } = {}

local function push(player: Player)
	local save = PlayerData.get(player)
	if not save then
		return
	end
	local monster, rung = Monsters.next(save.defeated)
	state:FireClient(player, {
		coins = save.coins,
		beasts = save.beasts,
		monster = monster,
		rung = rung,
		cleared = save.defeated[monster.name] == true,
	})
end

local function find(save: Types.Save, id: string): (Types.Beast?, number?)
	for index, beast in save.beasts do
		if beast.id == id then
			return beast, index
		end
	end
	return nil, nil
end

local function newId(save: Types.Save): string
	local id = `b{save.nextId}`
	save.nextId += 1
	return id
end

local function spend(save: Types.Save, cost: number): boolean
	if save.coins < cost then
		return false
	end
	save.coins -= cost
	return true
end

local handlers: { [string]: (Player, Types.Save, any) -> any } = {}

-- Missions: recognise the character, earn the coins. First try pays 2, second 1.
function handlers.quiz(player: Player, _save: Types.Save, _payload: any)
	local answer = Animals.roll(random)
	local choices = { answer.english }
	while #choices < 4 do
		local other = Animals.list[random:NextInteger(1, #Animals.list)]
		if not table.find(choices, other.english) then
			table.insert(choices, other.english)
		end
	end

	for index = #choices, 2, -1 do
		local swap = random:NextInteger(1, index)
		choices[index], choices[swap] = choices[swap], choices[index]
	end

	pending[player] = {
		char = answer.char,
		choices = choices,
		correct = table.find(choices, answer.english) :: number,
		attempts = 0,
	}

	return { ok = true, char = answer.char, choices = choices }
end

function handlers.answer(player: Player, save: Types.Save, payload: any)
	local question = pending[player]
	if not question then
		return { ok = false, error = "No open question" }
	end
	if typeof(payload) ~= "table" or typeof(payload.index) ~= "number" then
		return { ok = false, error = "Bad answer" }
	end

	question.attempts += 1
	if payload.index ~= question.correct then
		if question.attempts >= 2 then
			pending[player] = nil
			return { ok = true, correct = false, reveal = question.correct, coins = 0 }
		end
		return { ok = true, correct = false, again = true }
	end

	local reward = question.attempts == 1 and 2 or 1
	save.coins += reward
	pending[player] = nil
	push(player)
	return { ok = true, correct = true, coins = reward }
end

function handlers.rescue(player: Player, save: Types.Save, _payload: any)
	if not spend(save, Config.RESCUE_COST) then
		return { ok = false, error = "Not enough coins" }
	end

	local animal = Animals.roll(random)
	local beast: Types.Beast = {
		id = newId(save),
		name = animal.char,
		emoji = animal.emoji,
		parts = { animal.char },
		stats = table.clone(animal.stats),
	}
	table.insert(save.beasts, beast)

	push(player)
	return { ok = true, beast = beast, pinyin = animal.pinyin, english = animal.english }
end

function handlers.feed(player: Player, save: Types.Save, payload: any)
	if typeof(payload) ~= "table" or typeof(payload.id) ~= "string" then
		return { ok = false, error = "Pick a beast" }
	end
	local stat = payload.stat
	if typeof(stat) ~= "string" or not table.find(Config.STATS, stat) then
		return { ok = false, error = "Pick a stat" }
	end

	local beast = find(save, payload.id)
	if not beast then
		return { ok = false, error = "No such beast" }
	end
	local statsByName = beast.stats :: { [string]: number }
	if statsByName[stat] >= Config.STAT_CAP then
		return { ok = false, error = `{Config.STAT_LABELS[stat]} is already maxed` }
	end
	if not spend(save, Config.FEED_COST) then
		return { ok = false, error = "Not enough coins" }
	end

	statsByName[stat] += 1
	push(player)
	return { ok = true, beast = beast }
end

function handlers.fuse(player: Player, save: Types.Save, payload: any)
	if typeof(payload) ~= "table" or typeof(payload.a) ~= "string" or typeof(payload.b) ~= "string" then
		return { ok = false, error = "Pick two beasts" }
	end

	local a, aIndex = find(save, payload.a)
	local b, bIndex = find(save, payload.b)
	if not a or not b or not aIndex or not bIndex then
		return { ok = false, error = "No such beast" }
	end

	local allowed, reason = Fusion.canFuse(a, b)
	if not allowed then
		return { ok = false, error = reason }
	end
	if not spend(save, Config.FUSE_COST) then
		return { ok = false, error = "Not enough coins" }
	end

	local word = Fusion.realWord(a, b)
	local fused = Fusion.fuse(a, b, newId(save))

	-- Remove the higher index first so the lower one stays valid.
	local first, second = math.max(aIndex, bIndex), math.min(aIndex, bIndex)
	table.remove(save.beasts, first)
	table.remove(save.beasts, second)
	table.insert(save.beasts, fused)

	push(player)
	return { ok = true, beast = fused, realWord = word }
end

function handlers.battle(player: Player, save: Types.Save, payload: any)
	if typeof(payload) ~= "table" or typeof(payload.id) ~= "string" then
		return { ok = false, error = "Pick a beast" }
	end
	local beast = find(save, payload.id)
	if not beast then
		return { ok = false, error = "No such beast" }
	end

	local monster, rung = Monsters.next(save.defeated)
	local result = Battle.resolve(beast.stats, monster.stats, random)

	local bounty = 0
	if result.youWon and not save.defeated[monster.name] then
		save.defeated[monster.name] = true
		bounty = Config.BOUNTY
		save.coins += bounty
	end

	push(player)
	return {
		ok = true,
		monster = monster,
		rung = rung,
		rounds = result.rounds,
		youWon = result.youWon,
		bounty = bounty,
	}
end

action.OnServerInvoke = function(player: Player, kind: any, payload: any)
	local save = PlayerData.get(player)
	if not save then
		return { ok = false, error = "Still loading" }
	end
	if typeof(kind) ~= "string" then
		return { ok = false, error = "Bad action" }
	end

	local handler = handlers[kind]
	if not handler then
		return { ok = false, error = `Unknown action: {kind}` }
	end

	return handler(player, save, payload)
end

local function onJoin(player: Player)
	PlayerData.load(player)
	push(player)
end

for _, player in Players:GetPlayers() do
	task.spawn(onJoin, player)
end
Players.PlayerAdded:Connect(onJoin)

Players.PlayerRemoving:Connect(function(player)
	pending[player] = nil
	PlayerData.release(player)
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		PlayerData.save(player)
	end
end)

PlayerData.startAutosave()

print("[FusionZoo] server ready")
