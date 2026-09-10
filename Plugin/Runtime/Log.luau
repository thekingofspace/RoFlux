--!strict

local Log = {}

local Prefix = "[RoFlux]"
local History: { { level: string, text: string, clock: number } } = {}
local Listeners: { (level: string, text: string) -> () } = {}
local Limit = 200

local function push(level: string, text: string)
	table.insert(History, { level = level, text = text, clock = os.clock() })

	if #History > Limit then
		table.remove(History, 1)
	end

	for _, listener in Listeners do
		task.spawn(listener, level, text)
	end
end

function Log.info(text: string)
	push("info", text)
end

function Log.good(text: string)
	push("good", text)
end

function Log.warn(text: string)
	push("warn", text)
	warn(`{Prefix} {text}`)
end

function Log.fail(text: string)
	push("error", text)
	warn(`{Prefix} {text}`)
end

function Log.listen(callback: (level: string, text: string) -> ()): () -> ()
	table.insert(Listeners, callback)

	return function()
		local index = table.find(Listeners, callback)

		if index then
			table.remove(Listeners, index)
		end
	end
end

function Log.history()
	return History
end

function Log.clear()
	table.clear(History)
end

return Log
