--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Apply = require(script.Apply)
local Log = require(script.Parent.Log)
local Memory = require(script.Memory)
local Resolve = require(script.Resolve)

local Reconcile = {}

export type Node = Apply.Node
export type Report = Apply.Report
export type Entry = Apply.Entry

export type Op = {
	op: string,
	id: string?,
	parent: string?,
	node: Node?,
	className: string?,
	properties: { [string]: any }?,
	attributes: { [string]: any }?,
	clearedAttributes: { string }?,
	tags: { string }?,
}

local function record<T>(label: string, body: () -> T): T
	local identifier = ChangeHistoryService:TryBeginRecording(label)

	local ok, result = pcall(body)

	if identifier then
		ChangeHistoryService:FinishRecording(
			identifier,
			if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end

	if not ok then
		error(result, 0)
	end

	return result
end

function Reconcile.full(root: Node, project: string): Report
	return record("RoFlux sync", function()
		local report = Apply.tree(root, false, Memory.stale(project, root))
		Memory.save(project, Memory.roots(root, {}))
		return report
	end)
end

function Reconcile.preview(root: Node, project: string): Report
	return Apply.tree(root, true, Memory.stale(project, root))
end

local function patchOne(op: Op, report: Report, resync: { boolean })
	if op.op == "add" then
		local node = op.node

		if not node then
			return
		end

		local parent = Resolve.find(op.parent or "")

		if not parent then
			report.failed += 1
			Log.warn(`cannot reach "{op.parent}" to add {node.name}`)
			resync[1] = true
			return
		end

		Apply.place(parent, node, report)
		return
	end

	if op.op == "remove" then
		local target = Resolve.find(op.id or "")

		if not target then
			return
		end

		report.removed += 1
		Apply.note(report, "removed", target:GetFullName(), target.ClassName)

		pcall(function()
			target:Destroy()
		end)

		return
	end

	if op.op ~= "update" then
		return
	end

	local target = Resolve.find(op.id or "")

	if not target then
		resync[1] = true
		return
	end

	if op.className and target.ClassName ~= op.className then
		Apply.note(report, "removed", target:GetFullName(), `class changed to {op.className}`)
		report.removed += 1

		pcall(function()
			target:Destroy()
		end)

		resync[1] = true
		return
	end

	local node: Node = {
		id = op.id or "",
		name = target.Name,
		className = target.ClassName,
		ownership = "managed",
		properties = op.properties,
		attributes = op.attributes,
		tags = op.tags,
	}

	Apply.settle(target, node, report, op.clearedAttributes)
end

function Reconcile.patch(ops: { Op }, project: string): (Report, boolean)
	local report = Apply.blank()
	local resync = { false }

	record("RoFlux patch", function()
		for _, op in ops do
			patchOne(op, report, resync)
		end

		Memory.track(project, ops)
	end)

	return report, resync[1]
end

function Reconcile.summary(report: Report): string
	return `+{report.added} ~{report.updated} -{report.removed}`
		.. (if report.failed > 0 then ` !{report.failed}` else "")
end

return Reconcile
