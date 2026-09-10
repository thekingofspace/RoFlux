--!strict

local Changes = require(script.Parent.Parent.Runtime.Changes)
local Components = require(script.Parent.Components)
local Entry = require(script.Parent.Entry)
local Theme = require(script.Parent.Theme)
local Vision = require(script.Parent.Parent.Vision)

local Activity = {}

local Filters = { "all", "added", "updated", "removed", "failed" }

local Labels = {
	all = "All",
	added = "New",
	updated = "Edited",
	removed = "Gone",
	failed = "Failed",
}

local Blank = {
	all = "nothing has changed yet",
	added = "nothing has been created",
	updated = "nothing has been edited",
	removed = "nothing has been deleted",
	failed = "nothing has failed",
}

export type View = {
	frame: Frame,
	open: () -> (),
	release: () -> (),
}

function Activity.mount(parent: Instance): View
	local active = "all"
	local rows: { { record: Changes.Record, frame: Instance } } = {}

	local frame = Vision.create({
		ClassName = "Frame",
		Name = "Activity",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.background(),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 10,
		Components.padding(0.055, 0.04),
		{
			ClassName = "UIListLayout",
			FillDirection = Enum.FillDirection.Vertical,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0.018, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		},
		{
			ClassName = "Frame",
			Name = "Header",
			Size = UDim2.fromScale(1, 0.07),
			LayoutOrder = 1,
			BackgroundTransparency = 1,
			ZIndex = 11,
			Components.text(
				"Title",
				"Changes",
				UDim2.fromScale(0.42, 1),
				UDim2.fromScale(0, 0),
				Theme.text(),
				"body",
				true
			),
			Components.button("Clear", "Clear", UDim2.fromScale(0.26, 1), UDim2.fromScale(0.44, 0), false, function()
				Changes.clear()
			end),
			Components.button("Back", "Done", UDim2.fromScale(0.26, 1), UDim2.fromScale(0.74, 0), false, function() end),
		},
		{
			ClassName = "Frame",
			Name = "Filters",
			Size = UDim2.fromScale(1, 0.055),
			LayoutOrder = 2,
			BackgroundTransparency = 1,
			ZIndex = 11,
			{
				ClassName = "UIListLayout",
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0.014, 0),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
		},
		{
			ClassName = "Frame",
			Name = "Body",
			Size = UDim2.fromScale(1, 0.82),
			LayoutOrder = 3,
			BackgroundColor3 = Theme.field(),
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			ZIndex = 11,
			Components.corner(0.025),
			Components.text(
				"Empty",
				Blank.all,
				UDim2.fromScale(0.9, 0.08),
				UDim2.fromScale(0.05, 0.04),
				Theme.subtext(),
				"small"
			),
			{
				ClassName = "ScrollingFrame",
				Name = "List",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.fromScale(0, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 4,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ZIndex = 12,
				Components.padding(0.028, 0.014),
				{
					ClassName = "UIListLayout",
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, 2),
					SortOrder = Enum.SortOrder.LayoutOrder,
				},
			},
		},
	}) :: Frame

	frame.Parent = parent

	local body = frame:FindFirstChild("Body") :: Frame
	local list = body:FindFirstChild("List") :: ScrollingFrame
	local empty = body:FindFirstChild("Empty") :: TextLabel
	local filters = frame:FindFirstChild("Filters") :: Frame

	local function matches(record: Changes.Record): boolean
		if record.kind == "batch" then
			return active == "all"
		end

		return active == "all" or record.kind == active
	end

	local function refreshVisible()
		local shown = 0

		for _, row in rows do
			local ok = matches(row.record)
			;(row.frame :: any).Visible = ok

			if ok then
				shown += 1
			end
		end

		empty.Visible = shown == 0
		empty.Text = (Blank :: any)[active] or Blank.all
	end

	local order = 0

	local function add(record: Changes.Record)
		order += 1

		local made = Vision.create(Entry.label(record, order, 13))

		made.Parent = list
		table.insert(rows, { record = record, frame = made })
	end

	local function rebuild()
		for _, row in rows do
			row.frame:Destroy()
		end

		table.clear(rows)
		order = 0

		for _, record in Changes.all() do
			add(record)
		end

		refreshVisible()
		Components.resize(frame, math.max(frame.AbsoluteSize.Y, 1))
	end

	local function highlight()
		for _, chip in filters:GetChildren() do
			if not chip:IsA("TextButton") then
				continue
			end

			local chosen = chip.Name == active
			chip.BackgroundColor3 = if chosen then Theme.accent else Theme.field()
			chip.BackgroundTransparency = if chosen then 0 else 0.3
			chip.TextColor3 = if chosen then Color3.new(1, 1, 1) else Theme.text()
		end
	end

	for index, name in Filters do
		local chip = Vision.create(
			Components.button(
				name,
				(Labels :: any)[name],
				UDim2.fromScale(0.182, 1),
				UDim2.fromScale(0, 0),
				index == 1,
				function()
					active = name
					highlight()
					refreshVisible()
				end
			)
		)

		;(chip :: any).LayoutOrder = index
		;(chip :: any).ZIndex = 12
		chip.Parent = filters
	end

	local release = Changes.listen(function(record)
		if record.kind == "cleared" then
			rebuild()
			return
		end

		add(record)
		refreshVisible()
		Components.resize(frame, math.max(frame.AbsoluteSize.Y, 1))
	end)

	rebuild()
	highlight()

	return {
		frame = frame,
		release = release,
		open = function()
			frame.Visible = true
			rebuild()
			list.CanvasPosition = Vector2.new(0, math.huge)
		end,
	}
end

return Activity
