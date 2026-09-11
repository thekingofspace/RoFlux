--!strict

local RunService = game:GetService("RunService")

local Bridge = require(script.Runtime.Bridge)
local Game = require(script.Runtime.Game)
local Log = require(script.Runtime.Log)
local Session = require(script.Runtime.Session)
local Settings = require(script.Runtime.Settings)
local UI = require(script.UI)

if not RunService:IsStudio() then
	return
end

if RunService:IsRunning() then
	Game.start(plugin)
	return
end

if not RunService:IsEdit() then
	return
end

Settings.bind(plugin)
Bridge.stop()

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
