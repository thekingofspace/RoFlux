--!strict

local Components = require(script.Parent.Components)
local Entry = require(script.Parent.Entry)
local Theme = require(script.Parent.Theme)
local Vision = require(script.Parent.Parent.Vision)

local Confirm = {}

local Cap = 400

export type Gate = {
	frame: Frame,
	ask: (string, { Entry.Record }) -> boolean,
}

function Confirm.mount(parent: Instance): Gate
	local answer: boolean? = nil

	local frame = Vision.create({
		ClassName = "Frame",
		Name = "Confirm",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
		{
			ClassName = "Frame",
			Name = "Panel",
			Size = UDim2.fromScale(0.9, 0.78),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Theme.panel(),
			BorderSizePixel = 0,
			ZIndex = 21,
			Components.corner(0.045),
			Components.padding(0.05, 0.04),
			Components.stroke(Theme.border(), 1),
			Components.text(
				"Title",
				"Review changes",
				UDim2.fromScale(1, 0.07),
				UDim2.fromScale(0, 0),
				Theme.text(),
				"body",
				true
			),
			Components.text(
				"Message",
				"",
				UDim2.fromScale(1, 0.06),
				UDim2.fromScale(0, 0.09),
				Theme.subtext(),
				"small"
			),
			{
				ClassName = "ScrollingFrame",
				Name = "List",
				Size = UDim2.fromScale(1, 0.66),
				Position = UDim2.fromScale(0, 0.17),
				BackgroundColor3 = Theme.field(),
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
				CanvasSize = UDim2.fromScale(0, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 4,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ZIndex = 22,
				Components.corner(0.03),
				Components.padding(0.03, 0.015),
				{
					ClassName = "UIListLayout",
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, 2),
					SortOrder = Enum.SortOrder.LayoutOrder,
				},
			},
			Components.button(
				"Cancel",
				"Cancel",
				UDim2.fromScale(0.46, 0.1),
				UDim2.fromScale(0, 0.9),
				false,
				function()
					answer = false
				end
			),
			Components.button(
				"Apply",
				"Apply",
				UDim2.fromScale(0.46, 0.1),
				UDim2.fromScale(0.54, 0.9),
				true,
				function()
					answer = true
				end
			),
		},
	}) :: Frame

	frame.Parent = parent

	local panel = frame:FindFirstChild("Panel") :: Frame
	local message = panel:FindFirstChild("Message") :: TextLabel
	local list = panel:FindFirstChild("List") :: ScrollingFrame

	local function ask(text: string, lines: { Entry.Record }): boolean
		answer = nil
		message.Text = text

		for _, child in list:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end

		local shown = math.min(#lines, Cap)

		for index = 1, shown do
			local row = Vision.create(Entry.label(lines[index], index, 23))
			row.Parent = list
		end

		if #lines > shown then
			local more = Vision.create(Entry.label({
				kind = "batch",
				path = `and {#lines - shown} more`,
				detail = "",
			}, shown + 1, 23))

			more.Parent = list
		end

		Components.resize(frame, math.max(frame.AbsoluteSize.Y, 1))

		list.CanvasPosition = Vector2.zero
		frame.Visible = true

		while answer == nil do
			task.wait(0.05)
		end

		frame.Visible = false

		return answer == true
	end

	return {
		frame = frame,
		ask = ask,
	}
end

return Confirm
