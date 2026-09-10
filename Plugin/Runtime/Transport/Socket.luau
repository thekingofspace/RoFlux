--!strict

local HttpService = game:GetService("HttpService")

local Socket = {}
Socket.__index = Socket

type Fields = {
	client: WebStreamClient,
	alive: boolean,
	onMessage: ((string) -> ())?,
	onClosed: ((string?) -> ())?,
	bindings: { RBXScriptConnection },
	backlog: { string },
	started: boolean,
}

export type Socket = typeof(setmetatable({} :: Fields, Socket))

local Timeout = 8

function Socket.available(): boolean
	local ok = false

	pcall(function()
		ok = type((HttpService :: any).CreateWebStreamClient) == "function"
			and (Enum :: any).WebStreamClientType ~= nil
			and (Enum :: any).WebStreamClientType.WebSocket ~= nil
	end)

	return ok
end

function Socket.connect(
	url: string,
	onMessage: (string) -> (),
	onClosed: (string?) -> ()
): (Socket?, string?)
	if not Socket.available() then
		return nil, "this Studio build has no WebSocket stream client"
	end

	local client: WebStreamClient? = nil

	local made, problem = pcall(function()
		client = HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
			Url = url,
		})
	end)

	if not made then
		return nil, tostring(problem)
	end

	if not client then
		return nil, "CreateWebStreamClient returned nothing"
	end

	local stream = client :: WebStreamClient

	local self: Socket = setmetatable({
		client = stream,
		alive = false,
		onMessage = onMessage,
		onClosed = onClosed,
		bindings = {},
		backlog = {},
		started = false,
	} :: Fields, Socket)


	local settled = false
	local failure: string? = nil

	table.insert(
		self.bindings,
		stream.Opened:Connect(function()
			self.alive = true
			settled = true
		end)
	)

	table.insert(
		self.bindings,
		stream.Error:Connect(function(status: number, message: string)
			failure = if status ~= 0 then `{status} {message}` else message
			settled = true

			if self.alive then
				self.alive = false

				local closed = self.onClosed

				if closed then
					closed(failure)
				end
			end
		end)
	)

	table.insert(
		self.bindings,
		stream.Closed:Connect(function()
			settled = true

			if not self.alive then
				return
			end

			self.alive = false

			local closed = self.onClosed

			if closed then
				closed(nil)
			end
		end)
	)

	table.insert(
		self.bindings,
		stream.MessageReceived:Connect(function(message: string)
			if not self.started then
				table.insert(self.backlog, message)
				return
			end

			local received = self.onMessage

			if received then
				received(message)
			end
		end)
	)

	local deadline = os.clock() + Timeout

	while not settled and os.clock() < deadline do
		task.wait(0.05)
	end

	if self.alive then
		return self, nil
	end

	Socket.close(self)

	if failure then
		return nil, failure
	end

	if not settled then
		return nil, `no response from {url} within {Timeout}s`
	end

	return nil, "the server closed the connection"
end

function Socket.start(self: Socket)
	if self.started then
		return
	end

	self.started = true

	for _, held in self.backlog do
		local received = self.onMessage

		if received then
			received(held)
		end
	end

	table.clear(self.backlog)
end

function Socket.state(self: Socket): string
	local label = "Unknown"

	pcall(function()
		label = self.client.ConnectionState.Name
	end)

	return label
end

function Socket.send(self: Socket, payload: string)
	if not self.alive then
		return
	end

	pcall(function()
		self.client:Send(payload)
	end)
end

function Socket.close(self: Socket)
	self.alive = false

	for _, binding in self.bindings do
		binding:Disconnect()
	end

	table.clear(self.bindings)

	pcall(function()
		self.client:Close()
	end)
end

return Socket
