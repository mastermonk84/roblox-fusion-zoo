--!strict

export type Stats = {
	power: number,
	speed: number,
	smarts: number,
}

export type Animal = {
	char: string,
	pinyin: string,
	english: string,
	emoji: string,
	stats: Stats,
}

-- A beast in a player's zoo. `parts` is the ordered list of source characters,
-- so 马 + 蛙 = 马蛙 and fusing that with 熊 gives 马蛙熊.
export type Beast = {
	id: string,
	name: string,
	emoji: string,
	parts: { string },
	stats: Stats,
}

export type Monster = {
	name: string,
	emoji: string,
	stats: Stats,
}

export type Save = {
	coins: number,
	beasts: { Beast },
	defeated: { [string]: boolean },
	nextId: number,
}

return {}
