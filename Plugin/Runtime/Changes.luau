--!strict

local Changes = {}

export type Record = {
	kind: string,
	path: string,
	detail: string,
	clock: string,
}

local Marks = {
	added = "+",
	updated = "~",
	removed = "-",
	failed = "!",
}

local History: { Record } = {}
local Listeners: { (Record) -> () } = {}
local Limit = 500

local function push(record: Record)
	table.insert(History, record)

	while #History > Limit do
		table.remove(History, 1)
	end

	for _, listener in Listeners do
		task.spawn(listener, record)
	end
end

function Changes.begin(summary: string)
	push({
		kind = "batch",
		path = summary,
		detail = os.date("%H:%M:%S"),
		clock = os.date("%H:%M:%S"),
	})
end

function Changes.record(kind: string, path: string, detail: string)
	push({
		kind = kind,
		path = path,
		detail = detail,
		clock = os.date("%H:%M:%S"),
	})
end

function Changes.feed(entries: { { kind: string, path: string, detail: string } })
	for _, entry in entries do
		Changes.record(entry.kind, entry.path, entry.detail)
	end
end

function Changes.describe(record: { kind: string, path: string, detail: string }): string
	local mark = (Marks :: any)[record.kind] or "?"

	if record.detail ~= "" then
		return `{mark} {record.path}  ({record.detail})`
	end

	return `{mark} {record.path}`
end

function Changes.all(): { Record }
	return History
end

function Changes.counts(): { [string]: number }
	local totals = { added = 0, updated = 0, removed = 0, failed = 0 }

	for _, record in History do
		if totals[record.kind] then
			totals[record.kind] += 1
		end
	end

	return totals
end

function Changes.listen(callback: (Record) -> ()): () -> ()
	table.insert(Listeners, callback)

	return function()
		local index = table.find(Listeners, callback)

		if index then
			table.remove(Listeners, index)
		end
	end
end

function Changes.clear()
	table.clear(History)

	for _, listener in Listeners do
		task.spawn(listener, {
			kind = "cleared",
			path = "",
			detail = "",
			clock = os.date("%H:%M:%S"),
		})
	end
end

return Changes
