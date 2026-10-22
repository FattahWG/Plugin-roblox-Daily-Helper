-- Neo-Brutalism with a simple palette: cream, white, black and one yellow. Thick black borders and
-- hard black shadows do the work that gradients and glows do in other styles.

local Theme = {}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local COLORS = {
	-- All text is black. Size and weight show the order of importance, not a grey tone.
	bg = hex("FFF4E0"), card = hex("FFFFFF"), ink = hex("111111"), body = hex("111111"), muted = hex("111111"),
	yellow = hex("FFD23F"), dot = hex("EADFC8"), white = hex("FFFFFF"), dim = hex("111111"),
	Error = hex("FF5C5C"), Warning = hex("FF9F1C"), Info = hex("4D96FF"), ok = hex("2EC4B6"),
}

-- Sizes of the style, in pixels.
Theme.BORDER = 2
Theme.SHADOW = 5
Theme.RADIUS = 10

Theme.Font = {
	-- Montserrat for all text. Body text uses Medium, because the thin strokes of Regular look faint
	-- at small sizes.
	Regular = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium),
	Medium = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold),
	Bold = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold),
	Title = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold),
	Display = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy),
	Mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular),
}

-- One palette for the Light and the Dark Studio theme. The cream panel is the brand.
function Theme.colors()
	return COLORS
end

return Theme
