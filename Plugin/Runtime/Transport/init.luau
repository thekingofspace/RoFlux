--!strict

local HttpService = game:GetService("HttpService")

local Log = require(script.Parent.Log)
local Poll = require(script.Poll)
local Socket = require(script.Socket)

local Transport = {}
Transport.__index = Transport

type Fields = {
	host: string,
	port: number,
	mode: string,
	socket: Socket.Socket?,
	poll: Poll.Poll?,
	alive: boolean,
	onMessage: ((any) -> ())?,
	onClosed: ((string?) -> ())?,
}

export type Transport = typeof(setmetatable({} :: Fields, Transport))

function Transport.new(host: string, port: number): Transport
	return setmetatable({
		host = host,
		port = port,
		mode = "idle",
		socket = nil,
		poll = nil,
		alive = false,
		onMessage = nil,
		onClosed = nil,
	} :: Fields, Transport)
end

function Transport.http(self: Transport): string
	return `http://{self.host}:{self.port}`
end

function Transport.websocket(self: Transport): string
	return `ws://{self.host}:{self.port}/roflux`
end

local function dispatch(self: Transport, payload: string)
	local ok, parsed = pcall(function()
		return HttpService:JSONDecode(payload)
	end)

	if not ok or type(parsed) ~= "table" then
		return
	end

	if self.onMessage then
		self.onMessage(parsed)
	end
end

local function finish(self: Transport, reason: string?)
	if not self.alive then
		return
	end

	self.alive = false

	if self.onClosed then
		self.onClosed(reason)
	end
end

function Transport.connect(self: Transport): (boolean, string?)
	Transport.close(self)

	local socket, problem = Socket.connect(Transport.websocket(self), function(payload)
		dispatch(self, payload)
	end, function(reason)
		finish(self, reason)
	end)

	if socket then
		self.socket = socket
		self.mode = "websocket"
		self.alive = true

		Log.good("connected over websocket")
		Socket.start(socket)

		return true, nil
	end

	if problem then
		Log.info(`websocket unavailable, falling back to http ({problem})`)
	end

	local poll, failure = Poll.connect(Transport.http(self))

	if not poll then
		return false, failure
	end

	self.poll = poll
	self.mode = "http"
	self.alive = true

	poll.onMessage = function(payload)
		dispatch(self, payload)
	end

	poll.onClosed = function(reason)
		finish(self, reason)
	end

	Poll.start(poll)
	Log.good("connected over http polling")

	return true, nil
end

function Transport.send(self: Transport, message: any)
	if not self.alive then
		return
	end

	local ok, payload = pcall(function()
		return HttpService:JSONEncode(message)
	end)

	if not ok then
		return
	end

	if self.socket then
		Socket.send(self.socket, payload)
	end
end

function Transport.close(self: Transport)
	self.alive = false

	if self.socket then
		Socket.close(self.socket)
		self.socket = nil
	end

	if self.poll then
		Poll.close(self.poll)
		self.poll = nil
	end

	self.mode = "idle"
end

return Transport
