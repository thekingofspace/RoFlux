--!strict

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local Encode = require(script.Parent.Encode)
local Relay = require(script.Parent.Relay)

local Bridge = {}

Bridge.Name = "RoFlux"
Bridge.Received = "Received"
Bridge.SessionKey = "RoFluxSession"
Bridge.ServerKey = "RoFluxServer"

local holder: BindableEvent? = nil
local connection: RBXScriptConnection? = nil
local current: string? = nil

function Bridge.is(instance: Instance): boolean
	return instance.Name == Bridge.Name and instance:IsA("BindableEvent") and not instance.Archivable
end

function Bridge.session(): string?
	return current
end

function Bridge.fire(event: Instance?, args: any)
	if not event then
		return
	end

	local received = event:FindFirstChild(Bridge.Received)

	if not received or not received:IsA("BindableEvent") then
		return
	end

	local count, values = Encode.unpack(args)
	received:Fire(table.unpack(values, 1, count))
end

function Bridge.receive(args: any)
	Bridge.fire(holder, args)
end

function Bridge.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end

	if holder then
		holder:Destroy()
		holder = nil
	end

	for _, child in ServerStorage:GetChildren() do
		if Bridge.is(child) then
			child:Destroy()
		end
	end

	if ServerStorage:GetAttribute(Bridge.SessionKey) ~= nil then
		ServerStorage:SetAttribute(Bridge.SessionKey, nil)
	end

	if ServerStorage:GetAttribute(Bridge.ServerKey) ~= nil then
		ServerStorage:SetAttribute(Bridge.ServerKey, nil)
	end

	current = nil
	Relay.clear()
	Relay.target(nil)
end

function Bridge.start(url: string): string
	Bridge.stop()

	local id = HttpService:GenerateGUID(false)

	current = id
	Relay.via(nil)
	Relay.target(url)

	local event = Instance.new("BindableEvent")
	event.Name = Bridge.Name
	event.Archivable = false
	event:SetAttribute("Session", id)

	connection = event.Event:Connect(function(...)
		Relay.push({ kind = "event", session = id, args = Encode.tuple(...) })
	end)

	local received = Instance.new("BindableEvent")
	received.Name = Bridge.Received
	received.Archivable = false
	received.Parent = event

	event.Parent = ServerStorage
	holder = event

	ServerStorage:SetAttribute(Bridge.SessionKey, id)
	ServerStorage:SetAttribute(Bridge.ServerKey, url)

	return id
end

return Bridge
