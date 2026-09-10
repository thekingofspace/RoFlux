--!strict

local Settings = {}

local Defaults = {
	host = "127.0.0.1",
	port = 34872,
	autoConnect = false,
	confirmChanges = true,
}

local Store: Plugin? = nil

function Settings.bind(plugin: Plugin)
	Store = plugin
end

function Settings.get(key: string): any
	local fallback = (Defaults :: any)[key]

	if not Store then
		return fallback
	end

	local stored = (Store :: Plugin):GetSetting(`RoFlux_{key}`)

	if stored == nil then
		return fallback
	end

	return stored
end

function Settings.set(key: string, value: any)
	if not Store then
		return
	end

	;(Store :: Plugin):SetSetting(`RoFlux_{key}`, value)
end

function Settings.defaults()
	return Defaults
end

return Settings
