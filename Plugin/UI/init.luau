--!strict

local App = require(script.App)
local Session = require(script.Parent.Runtime.Session)

local UI = {}

local Info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 320, 460, 260, 380)

function UI.open(plugin: Plugin, session: Session.Session)
	local widget = plugin:CreateDockWidgetPluginGui("RoFluxMain", Info)
	widget.Title = "RoFlux"
	widget.Name = "RoFlux"
	widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local teardown: (() -> ())? = nil

	local function refresh()
		if teardown then
			(teardown :: () -> ())()
			teardown = nil
		end

		if widget.Enabled then
			teardown = App.mount(widget, session)
		end
	end

	widget:GetPropertyChangedSignal("Enabled"):Connect(refresh)
	refresh()

	return widget, function()
		if teardown then
			(teardown :: () -> ())()
		end

		widget:Destroy()
	end
end

return UI
