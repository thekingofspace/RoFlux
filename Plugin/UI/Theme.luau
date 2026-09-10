--!strict

local Theme = {}

local Studio = settings():GetService("Studio")

Theme.accent = Color3.fromRGB(60, 145, 245)
Theme.accentDeep = Color3.fromRGB(20, 90, 216)
Theme.accentLight = Color3.fromRGB(108, 188, 255)

Theme.states = {
	offline = Color3.fromRGB(130, 138, 150),
	connecting = Color3.fromRGB(235, 175, 60),
	syncing = Color3.fromRGB(108, 188, 255),
	connected = Color3.fromRGB(70, 195, 120),
	paused = Color3.fromRGB(235, 175, 60),
	error = Color3.fromRGB(225, 85, 85),
}

Theme.levels = {
	info = Color3.fromRGB(150, 158, 170),
	good = Color3.fromRGB(70, 195, 120),
	warn = Color3.fromRGB(235, 175, 60),
	error = Color3.fromRGB(225, 85, 85),
}

local function studio(name: Enum.StudioStyleGuideColor, modifier: Enum.StudioStyleGuideModifier?): Color3
	local ok, color = pcall(function()
		return Studio.Theme:GetColor(name, modifier)
	end)

	return if ok then color else Color3.fromRGB(46, 46, 46)
end

function Theme.background(): Color3
	return studio(Enum.StudioStyleGuideColor.MainBackground)
end

function Theme.panel(): Color3
	return studio(Enum.StudioStyleGuideColor.ViewPortBackground)
end

function Theme.field(): Color3
	return studio(Enum.StudioStyleGuideColor.InputFieldBackground)
end

function Theme.border(): Color3
	return studio(Enum.StudioStyleGuideColor.Border)
end

function Theme.text(): Color3
	return studio(Enum.StudioStyleGuideColor.MainText)
end

function Theme.subtext(): Color3
	return studio(Enum.StudioStyleGuideColor.SubText)
end

function Theme.changed(callback: () -> ()): RBXScriptConnection
	return Studio.ThemeChanged:Connect(callback)
end

return Theme
