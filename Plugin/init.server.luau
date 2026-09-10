--!strict

local RunService = game:GetService("RunService")

local Log = require(script.Runtime.Log)
local Session = require(script.Runtime.Session)
local Settings = require(script.Runtime.Settings)
local UI = require(script.UI)

if not RunService:IsStudio() or not RunService:IsEdit() then
	return
end

Settings.bind(plugin)

local session = Session.new()
local toolbar = plugin:CreateToolbar("RoFlux")

local toggle = toolbar:CreateButton("RoFlux", "Open the RoFlux sync panel", "rbxassetid://109643083513969")
toggle.ClickableWhenViewportHidden = true

local widget, closeUI = UI.open(plugin, session)

toggle:SetActive(widget.Enabled)

toggle.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggle:SetActive(widget.Enabled)
end)

plugin.Unloading:Connect(function()
	Session.destroy(session)
	closeUI()
end)

if Settings.get("autoConnect") then
	task.spawn(Session.connect, session)
end

Log.info("plugin ready")
