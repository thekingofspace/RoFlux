--!strict

local Theme = require(script.Parent.Theme)

local Entry = {}

export type Record = {
	kind: string,
	path: string,
	detail: string,
	clock: string?,
}

local Marks = {
	added = "+",
	updated = "~",
	removed = "-",
	failed = "!",
}

function Entry.hex(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

function Entry.shade(kind: string): Color3
	if kind == "added" then
		return Theme.states.connected
	end

	if kind == "removed" then
		return Theme.states.error
	end

	if kind == "updated" then
		return Theme.accentLight
	end

	if kind == "failed" then
		return Theme.states.connecting
	end

	return Theme.subtext()
end

function Entry.mark(kind: string): string
	return (Marks :: any)[kind] or "?"
end

function Entry.escape(text: string): string
	local out = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	return out
end

function Entry.markup(record: Record): string
	local dim = Entry.hex(Theme.subtext())

	if record.kind == "batch" then
		local clock = if record.clock then `  <font color="{dim}">{record.clock}</font>` else ""
		return `<b>{Entry.escape(record.path)}</b>{clock}`
	end

	local tail = if record.detail ~= ""
		then `  <font color="{dim}">{Entry.escape(record.detail)}</font>`
		else ""

	return `<font color="{Entry.hex(Entry.shade(record.kind))}">{Entry.mark(record.kind)}</font> {Entry.escape(record.path)}{tail}`
end

function Entry.label(record: Record, order: number, depth: number)
	return {
		ClassName = "TextLabel",
		Name = if record.kind == "batch" then "Batch" else "Row",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		RichText = true,
		Text = Entry.markup(record),
		Font = Enum.Font.Code,
		TextSize = 13,
		TextColor3 = Theme.text(),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		ZIndex = depth,
		attributes = { Role = "mono" },
	}
end

return Entry
