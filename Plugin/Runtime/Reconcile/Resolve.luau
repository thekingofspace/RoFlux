--!strict

local Resolve = {}

local Services: { [string]: boolean } = {}

local function service(name: string): Instance?
	local ok, found = pcall(function()
		return game:GetService(name :: any)
	end)

	if ok and found then
		Services[name] = true
		return found
	end

	return nil
end

function Resolve.split(path: string): { string }
	local parts = {}

	for part in path:gmatch("[^/]+") do
		table.insert(parts, part)
	end

	return parts
end

function Resolve.isService(name: string): boolean
	if Services[name] then
		return true
	end

	return service(name) ~= nil
end

function Resolve.find(path: string): Instance?
	local parts = Resolve.split(path)

	if #parts == 0 then
		return game
	end

	local cursor: Instance? = service(parts[1])

	if not cursor then
		cursor = game:FindFirstChild(parts[1])
	end

	for index = 2, #parts do
		if not cursor then
			return nil
		end

		cursor = (cursor :: Instance):FindFirstChild(parts[index])
	end

	return cursor
end

function Resolve.container(path: string): Instance?
	local parts = Resolve.split(path)

	if #parts == 0 then
		return game
	end

	local cursor = service(parts[1])

	if not cursor then
		return nil
	end

	for index = 2, #parts do
		local name = parts[index]
		local next = cursor:FindFirstChild(name)

		if not next then
			next = Instance.new("Folder")
			next.Name = name
			next.Parent = cursor
		end

		cursor = next
	end

	return cursor
end

return Resolve
