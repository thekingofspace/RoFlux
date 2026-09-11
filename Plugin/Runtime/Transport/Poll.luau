--!strict

local HttpService = game:GetService("HttpService")

local Poll = {}
Poll.__index = Poll

type Fields = {
	base: string,
	info: any,
	cursor: number,
	alive: boolean,
	onMessage: ((string) -> ())?,
	onClosed: ((string?) -> ())?,
}

export type Poll = typeof(setmetatable({} :: Fields, Poll))

local function request(url: string): (boolean, string)
	local ok, result = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = { Accept = "application/json" },
		})
	end)

	if not ok then
		return false, tostring(result)
	end

	local response = result :: any

	if not response.Success then
		return false, `{response.StatusCode} {response.StatusMessage}`
	end

	return true, response.Body
end

local function decode(body: string): any?
	local ok, parsed = pcall(function()
		return HttpService:JSONDecode(body)
	end)

	return if ok then parsed else nil
end

function Poll.connect(base: string): (Poll?, string?)
	local ok, body = request(`{base}/api/info`)

	if not ok then
		return nil, body
	end

	local self: Poll = setmetatable({
		base = base,
		info = decode(body),
		cursor = 0,
		alive = true,
		onMessage = nil,
		onClosed = nil,
	} :: Fields, Poll)

	return self, nil
end

local function deliver(self: Poll, payload: any)
	if type(payload) ~= "table" then
		return
	end

	local encoded = HttpService:JSONEncode(payload)

	if self.onMessage then
		self.onMessage(encoded)
	end
end

function Poll.start(self: Poll)
	task.spawn(function()
		local info = self.info

		if type(info) == "table" then
			deliver(self, {
				type = "hello",
				protocol = info.protocol,
				project = info.project,
				id = info.id,
				server = info.server,
			})
		end

		local ok, body = request(`{self.base}/api/snapshot`)

		if ok and self.alive then
			local parsed = decode(body)

			if parsed then
				self.cursor = (parsed :: any).cursor or 0
				deliver(self, parsed)
			end
		end

		while self.alive do
			local success, payload = request(`{self.base}/api/poll?cursor={self.cursor}`)

			if not self.alive then
				break
			end

			if not success then
				self.alive = false

				if self.onClosed then
					self.onClosed(payload)
				end

				break
			end

			local parsed = decode(payload)

			if parsed then
				local batch = (parsed :: any).messages

				if type(batch) == "table" then
					for _, message in batch do
						deliver(self, message)
					end
				end

				self.cursor = (parsed :: any).cursor or self.cursor
			end

			task.wait(0.05)
		end
	end)
end

function Poll.send(_: Poll, _: string) end

function Poll.close(self: Poll)
	self.alive = false
end

return Poll
