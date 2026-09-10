--!strict

local Vision = require(script.Parent.Parent.Vision)
local Theme = require(script.Parent.Theme)

local Components = {}

local Font = Enum.Font.GothamMedium
local Bold = Enum.Font.GothamBold

Components.roles = {
	display = 0.052,
	body = 0.036,
	small = 0.030,
	button = 0.032,
	mono = 0.027,
}

Components.limits = { low = 11, high = 26 }

function Components.corner(scale: number)
	return {
		ClassName = "UICorner",
		CornerRadius = UDim.new(scale, 0),
	}
end

function Components.stroke(color: Color3, thickness: number)
	return {
		ClassName = "UIStroke",
		Color = color,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}
end

function Components.square()
	return {
		ClassName = "UIAspectRatioConstraint",
		AspectRatio = 1,
		DominantAxis = Enum.DominantAxis.Height,
	}
end

function Components.padding(x: number, y: number)
	return {
		ClassName = "UIPadding",
		PaddingTop = UDim.new(y, 0),
		PaddingBottom = UDim.new(y, 0),
		PaddingLeft = UDim.new(x, 0),
		PaddingRight = UDim.new(x, 0),
	}
end

function Components.list(padding: number, direction: Enum.FillDirection?)
	return {
		ClassName = "UIListLayout",
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(padding, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}
end

function Components.text(
	name: string,
	value: string,
	size: UDim2,
	position: UDim2,
	color: Color3,
	role: string,
	bold: boolean?
)
	return {
		ClassName = "TextLabel",
		Name = name,
		Size = size,
		Position = position,
		BackgroundTransparency = 1,
		Text = value,
		Font = if bold then Bold else Font,
		TextSize = 14,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		attributes = { Role = role },
	}
end

function Components.dot(size: UDim2, position: UDim2, color: Color3)
	return {
		ClassName = "Frame",
		Name = "Dot",
		Size = size,
		Position = position,
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Components.square(),
		Components.corner(0.5),
	}
end

function Components.button(
	name: string,
	label: string,
	size: UDim2,
	position: UDim2,
	primary: boolean,
	activated: () -> (),
	order: number?
)
	return {
		ClassName = "TextButton",
		Name = name,
		Size = size,
		Position = position,
		LayoutOrder = order or 0,
		BackgroundColor3 = if primary then Theme.accent else Theme.field(),
		BackgroundTransparency = if primary then 0 else 0.3,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = label,
		Font = Bold,
		TextSize = 14,
		TextColor3 = if primary then Color3.new(1, 1, 1) else Theme.text(),
		attributes = { Role = "button" },
		Activated = function()
			activated()
		end,
		Components.corner(0.24),
		Components.stroke(if primary then Theme.accent else Theme.border(), 1),
	}
end

function Components.input(
	name: string,
	value: string,
	size: UDim2,
	position: UDim2,
	right: boolean,
	changed: (string) -> ()
)
	return {
		ClassName = "TextBox",
		Name = name,
		Size = size,
		Position = position,
		BackgroundTransparency = 1,
		Text = value,
		PlaceholderText = name,
		PlaceholderColor3 = Theme.subtext(),
		Font = Font,
		TextSize = 14,
		TextColor3 = Theme.text(),
		TextXAlignment = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ClearTextOnFocus = false,
		attributes = { Role = "body" },
		FocusLost = function(self: Instance)
			changed((self :: TextBox).Text)
		end,
	}
end

function Components.toggle(name: string, label: string, value: boolean, order: number, changed: (boolean) -> ())
	local state = value

	return {
		ClassName = "TextButton",
		Name = name,
		Size = UDim2.fromScale(1, 0.42),
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Activated = function(self: Instance)
			state = not state

			local box = (self :: Instance):FindFirstChild("Box") :: Frame
			box.BackgroundColor3 = if state then Theme.accent else Theme.field()
			box.BackgroundTransparency = if state then 0 else 0.3

			local mark = box:FindFirstChild("Mark") :: TextLabel
			mark.TextTransparency = if state then 0 else 1

			changed(state)
		end,
		{
			ClassName = "Frame",
			Name = "Box",
			Size = UDim2.fromScale(0.62, 0.62),
			Position = UDim2.fromScale(0, 0.5),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = if value then Theme.accent else Theme.field(),
			BackgroundTransparency = if value then 0 else 0.3,
			BorderSizePixel = 0,
			Components.square(),
			Components.corner(0.28),
			Components.stroke(Theme.border(), 1),
			{
				ClassName = "TextLabel",
				Name = "Mark",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "✓",
				Font = Bold,
				TextScaled = true,
				TextTransparency = if value then 0 else 1,
				TextColor3 = Color3.new(1, 1, 1),
			},
		},
		Components.text("Name", label, UDim2.fromScale(0.85, 1), UDim2.fromScale(0.07, 0), Theme.subtext(), "small"),
	}
end

function Components.resize(root: Instance, height: number)
	local roles = Components.roles
	local limits = Components.limits

	for _, item in root:GetDescendants() do
		local role = item:GetAttribute("Role")

		if type(role) ~= "string" then
			continue
		end

		local factor = (roles :: any)[role]

		if not factor then
			continue
		end

		local size = math.clamp(math.round(height * factor), limits.low, limits.high)

		pcall(function()
			(item :: any).TextSize = size
		end)
	end
end

function Components.create(declaration: any): Instance
	return Vision.create(declaration)
end

Components.font = Font
Components.bold = Bold

return Components
