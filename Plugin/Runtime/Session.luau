--!strict

local RunService = game:GetService("RunService")

local Changes = require(script.Parent.Changes)
local Log = require(script.Parent.Log)
local Reconcile = require(script.Parent.Reconcile)
local Settings = require(script.Parent.Settings)
local Transport = require(script.Parent.Transport)

local Session = {}
Session.__index = Session

type Fields = {
	transport: Transport.Transport?,
	status: string,
	project: string,
	detail: string,
	deferred: boolean,
	editing: boolean,
	watching: RBXScriptConnection?,
	listeners: { (string, string, string) -> () },
	confirm: ((string, { string }) -> boolean)?,
	reviewed: boolean,
}

export type Session = typeof(setmetatable({} :: Fields, Session))

local function editing(): boolean
	return RunService:IsEdit()
end

function Session.new(): Session
	local self: Session = setmetatable({
		transport = nil,
		status = "offline",
		project = "",
		detail = "not connected",
		deferred = false,
		editing = editing(),
		watching = nil,
		listeners = {},
		confirm = nil,
		reviewed = false,
	} :: Fields, Session)

	self.watching = RunService.Heartbeat:Connect(function()
		local now = editing()

		if now == self.editing then
			return
		end

		self.editing = now

		if now then
			Session.resume(self)
		else
			Session.announce(self, self.status, "paused while the place is running")
		end
	end)

	return self
end

function Session.onConfirm(self: Session, callback: ((string, { string }) -> boolean)?)
	self.confirm = callback
end

local function approved(self: Session, total: number, lines: { string }, what: string): boolean
	if self.reviewed or total <= 0 or not Settings.get("confirmChanges") then
		return true
	end

	local ask = self.confirm

	if not ask then
		return true
	end

	Session.announce(self, "paused", `waiting on you to review {total} changes`)

	return ask(what, lines)
end

function Session.listen(self: Session, callback: (string, string, string) -> ()): () -> ()
	table.insert(self.listeners, callback)

	return function()
		local index = table.find(self.listeners, callback)

		if index then
			table.remove(self.listeners, index)
		end
	end
end

function Session.announce(self: Session, status: string, detail: string)
	self.status = status
	self.detail = detail

	for _, listener in self.listeners do
		task.spawn(listener, status, detail, self.project)
	end
end

function Session.resume(self: Session)
	if not self.deferred then
		Session.announce(self, self.status, "connected")
		return
	end

	self.deferred = false

	local transport = self.transport

	if not transport or not transport.alive then
		return
	end

	Log.info("play session ended, catching up")
	Session.announce(self, "syncing", "catching up after the play session")
	Transport.send(transport, { type = "resync" })
end

local function onSync(self: Session, message: any)
	if not editing() then
		self.deferred = true
		Session.announce(self, "paused", "waiting for the play session to end")
		return
	end

	if not self.reviewed and Settings.get("confirmChanges") then
		local preview = Reconcile.preview(message.tree.root)
		local total = preview.added + preview.updated + preview.removed
		local outline = `{preview.added} to create, {preview.updated} to edit, {preview.removed} to delete.`

		if not approved(self, total, preview.changes, outline) then
			self.reviewed = true
			Log.warn("sync cancelled, disconnecting")
			Session.disconnect(self, "sync cancelled")
			return
		end
	end

	self.reviewed = true

	local ok, report = pcall(function()
		return Reconcile.full(message.tree.root)
	end)

	if not ok then
		Log.fail(`sync failed: {report}`)
		Session.announce(self, "error", tostring(report))
		return
	end

	local outcome = report :: any
	local summary = Reconcile.summary(outcome)

	if #outcome.changes > 0 then
		Changes.begin(`sync {summary}`)
		Changes.feed(outcome.changes)
	end

	Session.announce(self, "connected", if #outcome.changes > 0 then `synced {summary}` else "up to date")
end

local function onPatch(self: Session, message: any)
	if not editing() then
		self.deferred = true
		Session.announce(self, "paused", "changes are queued until the play session ends")
		return
	end

	local ok, report, resync = pcall(function()
		return Reconcile.patch(message.patch.ops)
	end)

	if not ok then
		Log.fail(`patch failed: {report}`)
		return
	end

	local outcome = report :: any
	local summary = Reconcile.summary(outcome)

	if #outcome.changes == 0 then
		return
	end

	Changes.begin(`update {summary}`)
	Changes.feed(outcome.changes)

	Session.announce(self, "connected", `applied {summary}`)

	if resync and self.transport then
		Transport.send(self.transport, { type = "resync" })
	end
end

local function onMessage(self: Session, message: any)
	local kind = message.type

	if kind == "hello" then
		self.project = tostring(message.project)
		Log.good(`connected to {self.project}`)
		Session.announce(self, "connected", `protocol {message.protocol}`)

		if self.transport then
			Transport.send(self.transport, { type = "ready", place = game.Name })
		end

		return
	end

	if kind == "sync" then
		onSync(self, message)
		return
	end

	if kind == "patch" then
		onPatch(self, message)
		return
	end

	if kind == "notice" then
		local level = tostring(message.level)
		local text = tostring(message.text)

		if level == "error" then
			Log.fail(text)
		else
			Log.warn(text)
		end

		return
	end
end

function Session.connect(self: Session): boolean
	if self.status == "connecting" then
		return false
	end

	Session.disconnect(self)
	self.reviewed = false

	local host = Settings.get("host")
	local port = Settings.get("port")
	local transport = Transport.new(host, port)

	self.transport = transport

	transport.onMessage = function(message)
		onMessage(self, message)
	end

	transport.onClosed = function(reason)
		Log.warn(`disconnected{if reason then `: {reason}` else ""}`)
		Session.announce(self, "offline", reason or "the server closed the connection")
	end

	Session.announce(self, "connecting", `{host}:{port}`)

	local ok, problem = Transport.connect(transport)

	if not ok then
		self.transport = nil
		Log.fail(`could not reach the server: {problem}`)
		Session.announce(self, "error", tostring(problem))
		return false
	end

	return true
end

function Session.disconnect(self: Session, reason: string?)
	if self.transport then
		Transport.close(self.transport)
		self.transport = nil
	end

	self.deferred = false

	if self.status ~= "offline" or reason then
		Session.announce(self, "offline", reason or "not connected")
	end
end

function Session.resync(self: Session)
	if not self.transport or not self.transport.alive then
		return
	end

	Transport.send(self.transport, { type = "resync" })
	Session.announce(self, "syncing", "asked the server for a full sync")
end

function Session.connected(self: Session): boolean
	return self.transport ~= nil and (self.transport :: Transport.Transport).alive
end

function Session.mode(self: Session): string
	return if self.transport then (self.transport :: Transport.Transport).mode else "idle"
end

function Session.destroy(self: Session)
	if self.watching then
		(self.watching :: RBXScriptConnection):Disconnect()
		self.watching = nil
	end

	Session.disconnect(self)
	table.clear(self.listeners)
end

return Session
