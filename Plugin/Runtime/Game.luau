--!strict

local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Bridge = require(script.Parent.Bridge)
local Encode = require(script.Parent.Encode)
local Relay = require(script.Parent.Relay)

local Game = {}

local Remote = "Relay"
local Wait = 30
local Retry = 2

local function level(kind: Enum.MessageType): string
	return string.lower((string.gsub(kind.Name, "^Message", "")))
end

local function fetch(url: string, cursor: number?): any?
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = if cursor then `{url}/api/game?cursor={cursor}` else `{url}/api/game`,
			Method = "GET",
		})
	end)

	if not ok or not (response :: any).Success then
		return nil
	end

	local decoded, parsed = pcall(function()
		return HttpService:JSONDecode((response :: any).Body)
	end)

	return if decoded and type(parsed) == "table" then parsed else nil
end

local function server(plugin: Plugin)
	local session = ServerStorage:GetAttribute(Bridge.SessionKey)
	local url = ServerStorage:GetAttribute(Bridge.ServerKey)

	if type(session) ~= "string" or type(url) ~= "string" then
		return
	end

	local gameSession = HttpService:GenerateGUID(false)
	local ended = false
	local started = false
	local early: { { [string]: any } } = {}

	local function send(entry: { [string]: any })
		if started then
			Relay.push(entry)
		else
			table.insert(early, entry)
		end
	end

	Relay.target(url)

	local event = Instance.new("BindableEvent")
	event.Name = Bridge.Name
	event.Archivable = false
	event:SetAttribute("Session", session)
	event:SetAttribute("GameSession", gameSession)

	local received = Instance.new("BindableEvent")
	received.Name = Bridge.Received
	received.Archivable = false
	received.Parent = event

	local remote = Instance.new("RemoteEvent")
	remote.Name = Remote
	remote.Archivable = false
	remote.Parent = event

	local function stamp(entry: { [string]: any }, context: string): { [string]: any }
		entry.session = session
		entry.gameSession = gameSession
		entry.context = context
		return entry
	end

	event.Event:Connect(function(...)
		send(stamp({ kind = "gameEvent", args = Encode.tuple(...) }, "server"))
	end)

	remote.OnServerEvent:Connect(function(_, batch)
		if type(batch) ~= "table" then
			return
		end

		for _, entry in batch do
			if type(entry) == "table" and (entry.kind == "gameEvent" or entry.kind == "log") then
				send(stamp(entry, "client"))
			end
		end
	end)

	LogService.MessageOut:Connect(function(message, kind)
		send(stamp({ kind = "log", message = message, level = level(kind) }, "server"))
	end)

	event.Parent = ReplicatedStorage

	local opening = fetch(url, nil)
	local cursor: number? = if opening then tonumber(opening.cursor) else nil

	task.spawn(function()
		while not ended do
			local batch = fetch(url, cursor)

			if ended then
				break
			end

			if not batch then
				task.wait(Retry)
				continue
			end

			local first = cursor == nil
			cursor = tonumber(batch.cursor) or cursor

			if first or type(batch.messages) ~= "table" then
				continue
			end

			for _, message in batch.messages do
				if type(message) == "table" and message.type == "message" then
					Bridge.fire(event, message.args)
					remote:FireAllClients("message", message.args)
				end
			end
		end
	end)

	Relay.push({ kind = "gameStart", session = session, gameSession = gameSession })
	started = true

	for _, entry in early do
		Relay.push(entry)
	end

	table.clear(early)

	local function finish()
		if ended then
			return
		end

		ended = true
		Relay.push({ kind = "gameEnd", session = session, gameSession = gameSession })
		Relay.flush(true)
	end

	pcall(function()
		game:BindToClose(finish)
	end)

	plugin.Unloading:Connect(finish)
end

local function client()
	local event = ReplicatedStorage:WaitForChild(Bridge.Name, Wait)

	if not event or not event:IsA("BindableEvent") then
		return
	end

	local remote = event:WaitForChild(Remote, Wait)

	if not remote or not remote:IsA("RemoteEvent") then
		return
	end

	Relay.via(function(batch)
		remote:FireServer(batch)
	end)

	remote.OnClientEvent:Connect(function(kind, args)
		if kind == "message" then
			Bridge.fire(event, args)
		end
	end)

	event.Event:Connect(function(...)
		Relay.push({ kind = "gameEvent", args = Encode.tuple(...) })
	end)

	LogService.MessageOut:Connect(function(message, kind)
		Relay.push({ kind = "log", message = message, level = level(kind) })
	end)
end

function Game.start(plugin: Plugin)
	if RunService:IsServer() then
		server(plugin)
	elseif RunService:IsClient() then
		client()
	end
end

return Game
