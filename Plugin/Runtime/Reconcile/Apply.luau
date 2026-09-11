--!strict

local Bridge = require(script.Parent.Parent.Bridge)
local Decode = require(script.Parent.Parent.Decode)
local Log = require(script.Parent.Parent.Log)
local Resolve = require(script.Parent.Resolve)

local Apply = {}

export type Node = {
	id: string,
	name: string,
	className: string,
	ownership: string,
	properties: { [string]: any }?,
	attributes: { [string]: any }?,
	tags: { string }?,
	children: { Node }?,
	filePaths: { string }?,
}

export type Entry = {
	kind: string,
	path: string,
	detail: string,
}

export type Report = {
	added: number,
	updated: number,
	removed: number,
	failed: number,
	preview: boolean,
	deletions: { string },
	changes: { Entry },
}

local Skipped: { [string]: boolean } = {
	Parent = true,
	Name = true,
	ClassName = true,
}

local Limit = 400

local function blank(preview: boolean?): Report
	return {
		added = 0,
		updated = 0,
		removed = 0,
		failed = 0,
		preview = preview == true,
		deletions = {},
		changes = {},
	}
end

local function note(report: Report, kind: string, path: string, detail: string)
	if #report.changes < Limit then
		table.insert(report.changes, { kind = kind, path = path, detail = detail })
	end
end

local function fail(report: Report, path: string, detail: string)
	report.failed += 1
	note(report, "failed", path, detail)
	Log.warn(`{path}: {detail}`)
end

local function count(node: Node): number
	local total = 1

	for _, child in node.children or {} do
		if child.ownership ~= "reference" then
			total += count(child)
		end
	end

	return total
end

local function properties(target: Instance, node: Node, report: Report): { string }
	local fields = node.properties
	local touched = {}

	if not fields then
		return touched
	end

	for key, value in fields do
		if Skipped[key] then
			continue
		end

		local ok, current = pcall(function()
			return (target :: any)[key]
		end)

		if not ok then
			fail(report, target:GetFullName(), `{node.className} has no property "{key}"`)
			continue
		end

		local decoded = Decode.coerce(current, value)

		if decoded == nil then
			fail(report, target:GetFullName(), `could not read a value for "{key}"`)
			continue
		end

		if Decode.same(current, decoded) then
			continue
		end

		table.insert(touched, key)

		if report.preview then
			continue
		end

		local written = pcall(function()
			(target :: any)[key] = decoded
		end)

		if not written then
			fail(report, target:GetFullName(), `"{key}" would not accept its value`)
		end
	end

	return touched
end

local function attributes(target: Instance, node: Node, report: Report, cleared: { string }?): { string }
	local fields = node.attributes
	local present: { [string]: boolean } = {}
	local touched = {}

	if fields then
		for key, value in fields do
			present[key] = true

			local decoded = Decode.attribute(value)

			if decoded == nil or Decode.same(target:GetAttribute(key), decoded) then
				continue
			end

			table.insert(touched, `@{key}`)

			if report.preview then
				continue
			end

			pcall(function()
				target:SetAttribute(key, decoded)
			end)
		end
	end

	if not cleared then
		return touched
	end

	for _, key in cleared do
		if present[key] or target:GetAttribute(key) == nil then
			continue
		end

		table.insert(touched, `-@{key}`)

		if report.preview then
			continue
		end

		pcall(function()
			target:SetAttribute(key, nil)
		end)
	end

	return touched
end

local function tags(target: Instance, node: Node, report: Report): { string }
	local declared = node.tags
	local touched = {}

	if not declared then
		return touched
	end

	local wanted: { [string]: boolean } = {}

	for _, tag in declared do
		wanted[tag] = true

		if target:HasTag(tag) then
			continue
		end

		table.insert(touched, `#{tag}`)

		if not report.preview then
			target:AddTag(tag)
		end
	end

	for _, tag in target:GetTags() do
		if wanted[tag] then
			continue
		end

		table.insert(touched, `-#{tag}`)

		if not report.preview then
			target:RemoveTag(tag)
		end
	end

	return touched
end

local function owned(node: Node): boolean
	return node.ownership == "managed"
end

local function settle(target: Instance, node: Node, report: Report, cleared: { string }?, fresh: boolean?)
	local touched = properties(target, node, report)

	for _, key in attributes(target, node, report, cleared) do
		table.insert(touched, key)
	end

	for _, key in tags(target, node, report) do
		table.insert(touched, key)
	end

	if fresh or #touched == 0 then
		return
	end

	report.updated += 1
	note(report, "updated", target:GetFullName(), table.concat(touched, ", "))
end

local function sweep(target: Instance, node: Node, report: Report)
	if not owned(node) then
		return
	end

	local declared: { [string]: boolean } = {}

	for _, child in node.children or {} do
		declared[child.name] = true
	end

	for _, child in target:GetChildren() do
		if declared[child.Name] or Bridge.is(child) then
			continue
		end

		report.removed += 1
		table.insert(report.deletions, child:GetFullName())
		note(report, "removed", child:GetFullName(), child.ClassName)

		if report.preview then
			continue
		end

		pcall(function()
			child:Destroy()
		end)
	end
end

function Apply.node(parent: Instance, node: Node, report: Report): Instance?
	if node.ownership == "reference" then
		return nil
	end

	local target = parent:FindFirstChild(node.name)
	local fresh = false

	if target and target.ClassName ~= node.className and owned(node) then
		report.removed += 1
		table.insert(report.deletions, target:GetFullName())
		note(report, "removed", target:GetFullName(), `replacing a {target.ClassName} with a {node.className}`)

		if report.preview then
			report.added += count(node)
			return nil
		end

		target:Destroy()
		target = nil
	end

	if not target then
		local path = `{parent:GetFullName()}.{node.name}`

		note(report, "added", path, node.className)

		if report.preview then
			report.added += count(node)
			return nil
		end

		local made = pcall(function()
			local built = Instance.new(node.className :: any)
			built.Name = node.name
			built.Parent = parent
			target = built
		end)

		if not made or not target then
			fail(report, path, `cannot create a {node.className}`)
			return nil
		end

		report.added += 1
		fresh = true
	end

	local instance = target :: Instance

	settle(instance, node, report, nil, fresh)

	for _, child in node.children or {} do
		Apply.node(instance, child, report)
	end

	sweep(instance, node, report)

	return instance
end

local function ghost(path: string, node: Node, report: Report)
	for _, child in node.children or {} do
		if child.ownership == "reference" then
			continue
		end

		local inner = `{path}.{child.name}`

		if child.ownership == "managed" then
			note(report, "added", inner, child.className)
			report.added += count(child)
		else
			note(report, "added", inner, "Folder")
			report.added += 1
			ghost(inner, child, report)
		end
	end
end

local function container(parent: Instance, node: Node, report: Report): Instance?
	if parent == game then
		local found = Resolve.find(node.name)

		if not found then
			fail(report, node.name, "this place has no such service")
		end

		return found
	end

	local found = parent:FindFirstChild(node.name)

	if found then
		return found
	end

	local path = `{parent:GetFullName()}.{node.name}`

	note(report, "added", path, "Folder")
	report.added += 1

	if report.preview then
		ghost(path, node, report)
		return nil
	end

	local built = Instance.new("Folder")
	built.Name = node.name
	built.Parent = parent

	return built
end

function Apply.place(parent: Instance, node: Node, report: Report): Instance?
	if node.ownership == "reference" then
		return nil
	end

	if node.ownership == "managed" then
		return Apply.node(parent, node, report)
	end

	local target = container(parent, node, report)

	if not target then
		return nil
	end

	settle(target, node, report, nil)
	Apply.walk(target, node, report)

	return target
end

function Apply.walk(parent: Instance, node: Node, report: Report)
	for _, child in node.children or {} do
		Apply.place(parent, child, report)
	end
end

local function forget(stale: { string }, report: Report)
	for _, path in stale do
		local target = Resolve.find(path)

		if not target or target.Parent == game then
			continue
		end

		report.removed += 1
		table.insert(report.deletions, target:GetFullName())
		note(report, "removed", target:GetFullName(), `{target.ClassName}, no longer in the project`)

		if not report.preview then
			pcall(function()
				target:Destroy()
			end)
		end
	end
end

function Apply.tree(root: Node, preview: boolean?, stale: { string }?): Report
	local report = blank(preview)
	forget(stale or {}, report)
	Apply.walk(game, root, report)
	return report
end

Apply.blank = blank
Apply.settle = settle
Apply.note = note
Apply.fail = fail

return Apply
