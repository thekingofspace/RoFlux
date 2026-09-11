--!strict

local HttpService = game:GetService("HttpService")

local Relay = {}

local Limit = 1000
local Delay = 0.2
local Patience = 3

local queue: { any } = {}
local scheduled = false
local sending = false
local base: string? = nil
local sender: ((batch: { any }) -> ())? = nil

function Relay.target(url: string?)
	base = url
end

function Relay.via(send: ((batch: { any }) -> ())?)
	sender = send
end

local function post(batch: { any })
	local url = base

	if not url then
		return
	end

	pcall(function()
		HttpService:RequestAsync({
			Url = `{url}/api/relay`,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode({ events = batch }),
		})
	end)
end

local function schedule()
	if scheduled then
		return
	end

	scheduled = true

	task.delay(Delay, function()
		Relay.flush()
	end)
end

function Relay.flush(wait: boolean?)
	scheduled = false

	if sending then
		if not wait then
			schedule()
			return
		end

		local deadline = os.clock() + Patience

		while sending and os.clock() < deadline do
			task.wait()
		end
	end

	if #queue == 0 then
		return
	end

	local batch = queue
	queue = {}
	sending = true

	local send = sender

	if send then
		pcall(send, batch)
	else
		post(batch)
	end

	sending = false

	if #queue > 0 then
		schedule()
	end
end

function Relay.push(entry: { [string]: any })
	if #queue >= Limit then
		return
	end

	table.insert(queue, entry)
	schedule()
end

function Relay.clear()
	table.clear(queue)
end

return Relay
