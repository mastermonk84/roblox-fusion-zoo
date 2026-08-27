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

-- darken a colour toward black by `amount` (0..1) — for tactile press-edges.
function Ui.darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.fromRGB(0, 0, 0), amount)
end

-- stat type-colours, shared across battle/fusion so 力/速/智 read the same.
Ui.STAT_COLOR = {
	li = Color3.fromRGB(255, 107, 61),
	su = Color3.fromRGB(38, 198, 245),
	zhi = Color3.fromRGB(178, 107, 255),
}

local TACTILE_EDGE = 5

-- A tactile press-depth button: a face that sinks onto a darker edge. Size /
-- Position / Parent apply to the holder; Text / TextSize / BackgroundColor3 /
-- TextColor3 to the face. Optional `edge` colour, `radius`. Returns the face
-- TextButton (use .Activated). Children are parented into the face.
function Ui.tactile(props: { [string]: any }, children: { Instance }?): TextButton
	local faceColor = props.BackgroundColor3 or Ui.COLORS.accent
	local edgeColor = props.edge or Ui.darken(faceColor, 0.28)
	local radius = props.radius or 14
	local holder = Ui.new("Frame", {
		Name = props.Name or "Tactile",
		Size = props.Size or UDim2.new(1, 0, 0, 60),
		Position = props.Position or UDim2.new(),
		BackgroundTransparency = 1,
		Visible = if props.Visible == nil then true else props.Visible,
		Parent = props.Parent,
	})
	Ui.new("Frame", {
		Size = UDim2.new(1, 0, 1, -TACTILE_EDGE),
		Position = UDim2.new(0, 0, 0, TACTILE_EDGE),
		BackgroundColor3 = edgeColor,
		BorderSizePixel = 0,
		Parent = holder,
	}, { Ui.corner(radius) })
	local face = Ui.new("TextButton", {
		Size = UDim2.new(1, 0, 1, -TACTILE_EDGE),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = faceColor,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = Ui.FONT,
		Text = props.Text or "",
		TextSize = props.TextSize or 24,
		TextColor3 = props.TextColor3 or Ui.COLORS.ink,
		TextWrapped = true,
		Parent = holder,
	}, { Ui.corner(radius) })
	for _, child in children or {} do
		child.Parent = face
	end
	face.MouseButton1Down:Connect(function()
		face.Position = UDim2.new(0, 0, 0, TACTILE_EDGE)
	end)
	local function lift()
		face.Position = UDim2.new(0, 0, 0, 0)
	end
	face.MouseButton1Up:Connect(lift)
	face.MouseLeave:Connect(lift)
	return face
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
