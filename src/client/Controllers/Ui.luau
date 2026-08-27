--!strict
-- Tiny UI construction helpers shared by every controller. One place decides
-- fonts and palette so the whole game reads as one system. CJK note: Roblox
-- text falls back for 汉字 glyphs on device; SourceSans keeps that fallback
-- clean — verify on device per STUDIO_CHECKLIST.

local Ui = {}

Ui.COLORS = {
	card = Color3.fromRGB(255, 252, 245),
	cardDim = Color3.fromRGB(240, 236, 228),
	ink = Color3.fromRGB(45, 41, 56),
	inkSoft = Color3.fromRGB(120, 114, 134),
	accent = Color3.fromRGB(255, 176, 59),
	good = Color3.fromRGB(126, 217, 163),
	bad = Color3.fromRGB(238, 130, 130),
	scrim = Color3.fromRGB(20, 18, 28),
	coin = Color3.fromRGB(250, 204, 78),
	-- press-depth edges + accents for the tactile kiosk redesign (additive)
	accentEdge = Color3.fromRGB(216, 137, 34),
	goodEdge = Color3.fromRGB(79, 183, 126),
	badEdge = Color3.fromRGB(214, 92, 92),
	teal = Color3.fromRGB(30, 122, 114),
	grid = Color3.fromRGB(231, 211, 174),
	tileEdge = Color3.fromRGB(230, 211, 171),
}

Ui.FONT = Enum.Font.SourceSansBold
Ui.FONT_SOFT = Enum.Font.SourceSans

function Ui.new(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	return instance
end

function Ui.corner(radius: number): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function Ui.padding(pixels: number): UIPadding
	return Ui.new("UIPadding", {
		PaddingTop = UDim.new(0, pixels),
		PaddingBottom = UDim.new(0, pixels),
		PaddingLeft = UDim.new(0, pixels),
		PaddingRight = UDim.new(0, pixels),
	})
end

function Ui.text(props: { [string]: any }, children: { Instance }?): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Ui.FONT,
		TextColor3 = Ui.COLORS.ink,
		TextWrapped = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	return Ui.new("TextLabel", defaults, children)
end

function Ui.button(props: { [string]: any }, children: { Instance }?): TextButton
	local defaults: { [string]: any } = {
		Font = Ui.FONT,
		TextColor3 = Ui.COLORS.ink,
		BackgroundColor3 = Ui.COLORS.accent,
		AutoButtonColor = true,
		BorderSizePixel = 0,
		TextWrapped = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	local list = children or {}
	table.insert(list, Ui.corner(12))
	return Ui.new("TextButton", defaults, list)
end

return Ui
