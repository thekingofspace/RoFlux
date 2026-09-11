--!strict

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local Memory = {}

local Name = "RoFluxState"

type Node = {
	id: string,
	ownership: string,
	children: { Node }?,
}

local function read(): { [string]: any }
	local stored = ServerStorage:GetAttribute(Name)

	if type(stored) ~= "string" then
		return {}
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(stored)
	end)

	return if ok and type(decoded) == "table" then decoded else {}
end

local function inside(path: string, root: string): boolean
	return path == root or string.sub(path, 1, #root + 1) == root .. "/"
end

function Memory.load(project: string): { string }
	local projects = read().projects

	if type(projects) ~= "table" then
		return {}
	end

	local list = projects[project]
	local out = {}

	if type(list) == "table" then
		for _, path in list do
			if type(path) == "string" then
				table.insert(out, path)
			end
		end
	end

	return out
end

function Memory.save(project: string, list: { string })
	local state = read()
	local projects = if type(state.projects) == "table" then state.projects else {}

	table.sort(list)

	local current = Memory.load(project)

	if HttpService:JSONEncode(current) == HttpService:JSONEncode(list) and ServerStorage:GetAttribute(Name) ~= nil then
		return
	end

	projects[project] = list
	state.version = 1
	state.projects = projects

	ServerStorage:SetAttribute(Name, HttpService:JSONEncode(state))
end

function Memory.roots(node: Node, into: { string }): { string }
	for _, child in node.children or {} do
		if child.ownership == "managed" then
			table.insert(into, child.id)
		elseif child.ownership == "passthrough" then
			Memory.roots(child, into)
		end
	end

	return into
end

function Memory.stale(project: string, root: Node): { string }
	local present: { [string]: string } = {}

	local function index(node: Node)
		for _, child in node.children or {} do
			present[child.id] = child.ownership
			index(child)
		end
	end

	index(root)

	local out = {}

	for _, path in Memory.load(project) do
		if present[path] then
			continue
		end

		local covered = false
		local trail = ""

		for part in string.gmatch(path, "[^/]+") do
			trail = if trail == "" then part else `{trail}/{part}`

			if trail ~= path and present[trail] == "managed" then
				covered = true
				break
			end
		end

		if not covered then
			table.insert(out, path)
		end
	end

	return out
end

function Memory.track(project: string, ops: { any })
	local list = Memory.load(project)
	local changed = false

	for _, op in ops do
		if op.op == "add" and op.node then
			local parent = op.parent or ""
			local owned = false

			for _, root in list do
				if inside(parent, root) then
					owned = true
					break
				end
			end

			if owned then
				continue
			end

			local found = if op.node.ownership == "managed" then { op.node.id } else Memory.roots(op.node, {})

			for _, path in found do
				if not table.find(list, path) then
					table.insert(list, path)
					changed = true
				end
			end
		elseif op.op == "remove" and op.id then
			for index = #list, 1, -1 do
				if inside(list[index], op.id) then
					table.remove(list, index)
					changed = true
				end
			end
		end
	end

	if changed then
		Memory.save(project, list)
	end
end

return Memory
