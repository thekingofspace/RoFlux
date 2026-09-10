--!strict

local Activity = require(script.Parent.Activity)
local Components = require(script.Parent.Components)
local Confirm = require(script.Parent.Confirm)
local Log = require(script.Parent.Parent.Runtime.Log)
local Session = require(script.Parent.Parent.Runtime.Session)
local Settings = require(script.Parent.Parent.Runtime.Settings)
local Theme = require(script.Parent.Theme)
local Vision = require(script.Parent.Parent.Vision)

local App = {}

local Version = "0.0.1"
local Wordmark = "rbxassetid://98759728108909"
local WordmarkOffset = Vector2.new(70, 61)
local WordmarkSize = Vector2.new(676, 168)
local WordmarkRatio = 676 / 168
local Rows = 120

local function line(level: string, text: string, order: number)
	return {
		ClassName = "TextLabel",
		Name = "Entry",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.Code,
		TextSize = 13,
		TextColor3 = (Theme.levels :: any)[level] or Theme.subtext(),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		attributes = { Role = "mono" },
	}
end

function App.mount(parent: Instance, session: Session.Session)
	local bindings: { RBXScriptConnection } = {}
	local releases: { () -> () } = {}

	local root = Vision.create({
		ClassName = "Frame",
		Name = "RoFlux",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.background(),
		BorderSizePixel = 0,
		{
			ClassName = "Frame",
			Name = "Main",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Components.padding(0.06, 0.05),
			{
				ClassName = "UIListLayout",
				FillDirection = Enum.FillDirection.Vertical,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				Padding = UDim.new(0.022, 0),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			{
				ClassName = "Frame",
				Name = "Brand",
				Size = UDim2.fromScale(1, 0.075),
				LayoutOrder = 1,
				BackgroundTransparency = 1,
				{
					ClassName = "UIListLayout",
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					HorizontalAlignment = Enum.HorizontalAlignment.Left,
					Padding = UDim.new(0.035, 0),
					SortOrder = Enum.SortOrder.LayoutOrder,
				},
				{
					ClassName = "ImageLabel",
					Name = "Word",
					Size = UDim2.fromScale(1, 1),
					LayoutOrder = 1,
					BackgroundTransparency = 1,
					Image = Wordmark,
					ImageRectOffset = WordmarkOffset,
					ImageRectSize = WordmarkSize,
					ScaleType = Enum.ScaleType.Fit,
					{
						ClassName = "UIAspectRatioConstraint",
						AspectRatio = WordmarkRatio,
						DominantAxis = Enum.DominantAxis.Height,
					},
				},
				{
					ClassName = "TextLabel",
					Name = "Version",
					Size = UDim2.fromScale(0.22, 0.7),
					LayoutOrder = 2,
					BackgroundTransparency = 1,
					Text = Version,
					Font = Components.font,
					TextSize = 14,
					TextColor3 = Theme.subtext(),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Bottom,
					attributes = { Role = "small" },
				},
			},
			{
				ClassName = "Frame",
				Name = "Address",
				Size = UDim2.fromScale(1, 0.085),
				LayoutOrder = 2,
				BackgroundColor3 = Theme.field(),
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
				Components.corner(0.22),
				Components.stroke(Theme.border(), 1),
				Components.input(
					"host",
					tostring(Settings.get("host")),
					UDim2.fromScale(0.56, 1),
					UDim2.fromScale(0.05, 0),
					false,
					function(value)
						Settings.set("host", value)
					end
				),
				Components.input(
					"port",
					tostring(Settings.get("port")),
					UDim2.fromScale(0.28, 1),
					UDim2.fromScale(0.67, 0),
					true,
					function(value)
						local parsed = tonumber(value)

						if parsed then
							Settings.set("port", math.floor(parsed))
						end
					end
				),
			},
			{
				ClassName = "Frame",
				Name = "Actions",
				Size = UDim2.fromScale(1, 0.08),
				LayoutOrder = 3,
				BackgroundTransparency = 1,
				{
					ClassName = "UIListLayout",
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					HorizontalAlignment = Enum.HorizontalAlignment.Left,
					Padding = UDim.new(0.025, 0),
					SortOrder = Enum.SortOrder.LayoutOrder,
				},
				Components.button(
					"Changes",
					"Changes",
					UDim2.fromScale(0.28, 1),
					UDim2.fromScale(0, 0),
					false,
					function() end,
					1
				),
				Components.button(
					"Settings",
					"Settings",
					UDim2.fromScale(0.28, 1),
					UDim2.fromScale(0, 0),
					false,
					function() end,
					2
				),
				Components.button(
					"Connect",
					"Connect",
					UDim2.fromScale(0.3, 1),
					UDim2.fromScale(0, 0),
					true,
					function()
						if Session.connected(session) then
							Session.disconnect(session)
						else
							task.spawn(Session.connect, session)
						end
					end,
					3
				),
			},
			{
				ClassName = "Frame",
				Name = "Status",
				Size = UDim2.fromScale(1, 0.05),
				LayoutOrder = 4,
				BackgroundTransparency = 1,
				Components.dot(UDim2.fromScale(0.02, 0.32), UDim2.fromScale(0.01, 0.5), Theme.states.offline),
				Components.text(
					"Detail",
					"not connected",
					UDim2.fromScale(0.92, 1),
					UDim2.fromScale(0.055, 0),
					Theme.subtext(),
					"small"
				),
			},
		},
		{
			ClassName = "Frame",
			Name = "Panel",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.background(),
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 5,
			Components.padding(0.055, 0.04),
			Components.text("Title", "Settings", UDim2.fromScale(0.6, 0.06), UDim2.fromScale(0, 0), Theme.text(), "body", true),
			Components.button("Back", "Done", UDim2.fromScale(0.24, 0.06), UDim2.fromScale(0.76, 0), false, function() end),
			{
				ClassName = "Frame",
				Name = "Options",
				Size = UDim2.fromScale(1, 0.12),
				Position = UDim2.fromScale(0, 0.1),
				BackgroundTransparency = 1,
				ZIndex = 6,
				Components.list(0.1),
				Components.toggle("Auto", "connect when Studio opens", Settings.get("autoConnect") == true, 1, function(value)
					Settings.set("autoConnect", value)
				end),
				Components.toggle("Ask", "review changes when connecting", Settings.get("confirmChanges") == true, 2, function(value)
					Settings.set("confirmChanges", value)
				end),
			},
			{
				ClassName = "Frame",
				Name = "Console",
				Size = UDim2.fromScale(1, 0.72),
				Position = UDim2.fromScale(0, 0.26),
				BackgroundColor3 = Theme.field(),
				BackgroundTransparency = 0.55,
				BorderSizePixel = 0,
				ZIndex = 6,
				Components.corner(0.025),
				{
					ClassName = "ScrollingFrame",
					Name = "Feed",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					CanvasSize = UDim2.fromScale(0, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					ScrollBarThickness = 3,
					ScrollingDirection = Enum.ScrollingDirection.Y,
					ZIndex = 7,
					Components.padding(0.025, 0.012),
					{
						ClassName = "UIListLayout",
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 3),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
				},
			},
		},
	})

	local main = root:FindFirstChild("Main") :: Frame
	local panel = root:FindFirstChild("Panel") :: Frame
	local actions = main:FindFirstChild("Actions") :: Frame
	local statusRow = main:FindFirstChild("Status") :: Frame
	local dot = statusRow:FindFirstChild("Dot") :: Frame
	local detail = statusRow:FindFirstChild("Detail") :: TextLabel
	local connect = actions:FindFirstChild("Connect") :: TextButton
	local settings = actions:FindFirstChild("Settings") :: TextButton
	local changes = actions:FindFirstChild("Changes") :: TextButton
	local back = panel:FindFirstChild("Back") :: TextButton
	local feed = (panel:FindFirstChild("Console") :: Frame):FindFirstChild("Feed") :: ScrollingFrame

	local activity = Activity.mount(root)
	local activityHeader = activity.frame:FindFirstChild("Header") :: Frame
	local activityBack = activityHeader:FindFirstChild("Back") :: TextButton

	table.insert(releases, activity.release)

	local function resize()
		Components.resize(root, math.max(root.AbsoluteSize.Y, 1))
	end

	table.insert(bindings, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize))
	table.insert(bindings, settings.Activated:Connect(function()
		panel.Visible = true
	end))
	table.insert(bindings, back.Activated:Connect(function()
		panel.Visible = false
	end))
	table.insert(bindings, changes.Activated:Connect(function()
		activity.open()
	end))
	table.insert(bindings, activityBack.Activated:Connect(function()
		activity.frame.Visible = false
	end))

	local gate = Confirm.mount(root)
	Session.onConfirm(session, gate.ask)

	local order = 0

	local function append(level: string, text: string)
		order += 1

		local made = Vision.create(line(level, text, order))
		made.Parent = feed

		if #feed:GetChildren() > Rows + 2 then
			for _, child in feed:GetChildren() do
				if child:IsA("TextLabel") and child.LayoutOrder <= order - Rows then
					child:Destroy()
				end
			end
		end

		resize()
	end

	for _, record in Log.history() do
		append(record.level, record.text)
	end

	table.insert(releases, Log.listen(append))

	table.insert(
		releases,
		Session.listen(session, function(state: string, text: string)
			dot.BackgroundColor3 = (Theme.states :: any)[state] or Theme.states.offline
			detail.Text = text
			connect.Text = if Session.connected(session) then "Disconnect" else "Connect"
		end)
	)

	table.insert(
		bindings,
		Theme.changed(function()
			root.BackgroundColor3 = Theme.background()
			panel.BackgroundColor3 = Theme.background()
			activity.frame.BackgroundColor3 = Theme.background()
			detail.TextColor3 = Theme.subtext()
		end)
	)

	root.Parent = parent
	resize()

	return function()
		Session.onConfirm(session, nil)

		for _, binding in bindings do
			binding:Disconnect()
		end

		for _, release in releases do
			release()
		end

		root:Destroy()
	end
end

return App
