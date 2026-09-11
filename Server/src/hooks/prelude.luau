local roflux = roflux

local Directives = {
	["$ClassName"] = true,
	["$Path"] = true,
	["$FromModel"] = true,
	["$Properties"] = true,
	["$Attributes"] = true,
	["$Tags"] = true,
	["$Children"] = true,
	["$Name"] = true,
	["$Parent"] = true,
	["$Ignore"] = true,
}

local Keywords = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"] = true,
	["while"] = true,
	["continue"] = true,
	["export"] = true,
	["type"] = true,
	["const"] = true,
}

local function isArray(value)
	if type(value) ~= "table" then
		return false
	end

	local count = 0

	for _ in value do
		count += 1
	end

	return count == #value
end

local function isDeclaration(value)
	if type(value) ~= "table" then
		return false
	end

	for key in value do
		if Directives[key] then
			return true
		end
	end

	return false
end

function roflux.luau.isIdentifier(name)
	return type(name) == "string" and string.match(name, "^[%a_][%w_]*$") ~= nil and not Keywords[name]
end

local function inspect(value, depth, seen)
	local kind = type(value)

	if kind == "string" then
		return string.format("%q", value)
	end

	if kind ~= "table" then
		return tostring(value)
	end

	if seen[value] then
		return "<cycle>"
	end

	if depth > 6 then
		return "{...}"
	end

	local keys = {}

	for key in value do
		table.insert(keys, key)
	end

	if #keys == 0 then
		return "{}"
	end

	table.sort(keys, function(a, b)
		local left, right = type(a), type(b)

		if left ~= right then
			return left < right
		end

		if left == "number" or left == "string" then
			return a < b
		end

		return tostring(a) < tostring(b)
	end)

	seen[value] = true

	local pad = string.rep("  ", depth + 1)
	local sequence = #keys == #value
	local lines = {}

	for _, key in keys do
		local shown = inspect(value[key], depth + 1, seen)

		if sequence then
			table.insert(lines, pad .. shown)
		elseif roflux.luau.isIdentifier(key) then
			table.insert(lines, pad .. key .. " = " .. shown)
		else
			table.insert(lines, pad .. "[" .. inspect(key, depth + 1, seen) .. "] = " .. shown)
		end
	end

	seen[value] = nil

	return "{\n" .. table.concat(lines, ",\n") .. "\n" .. string.rep("  ", depth) .. "}"
end

function roflux.inspect(value)
	return inspect(value, 0, {})
end

local function render(...)
	local count = select("#", ...)
	local out = {}

	for index = 1, count do
		local value = select(index, ...)
		out[index] = if type(value) == "string" then value else roflux.inspect(value)
	end

	return table.unpack(out, 1, count)
end

for _, name in { "log", "warn", "error" } do
	local raw = roflux[name]

	roflux[name] = function(...)
		raw(render(...))
	end
end

local function childName(value)
	if type(value) ~= "table" or type(value["$Name"]) ~= "string" then
		error("a child passed by position needs a Name", 3)
	end

	return value["$Name"]
end

function roflux.new(className, fields, children)
	local declaration = { ["$ClassName"] = className }
	local properties = nil

	for key, value in fields or {} do
		if type(key) == "number" then
			declaration[childName(value)] = value
		elseif key == "Name" and type(value) == "string" then
			declaration["$Name"] = value
		elseif string.sub(key, 1, 1) == "$" then
			declaration[key] = value
		elseif type(value) == "table" and not isArray(value) and not isDeclaration(value) and value["$Type"] == nil then
			properties = properties or {}
			properties[key] = value
		else
			declaration[key] = value
		end
	end

	for key, value in children or {} do
		if type(key) == "number" then
			declaration[childName(value)] = value
		else
			declaration[key] = value
		end
	end

	if properties then
		local merged = declaration["$Properties"] or {}

		for key, value in properties do
			merged[key] = value
		end

		declaration["$Properties"] = merged
	end

	return declaration
end

local types = {}

function types.color(r, g, b)
	return { r, g, b }
end

function types.rgb(r, g, b)
	return { r / 255, g / 255, b / 255 }
end

function types.hex(value)
	local text = string.gsub(value, "^#", "")

	if #text == 3 then
		text = string.gsub(text, "(%x)", "%1%1")
	end

	if #text ~= 6 or string.find(text, "%X") then
		error("roflux.types.hex needs a color like \"#3C91F5\"", 2)
	end

	return types.rgb(
		tonumber(string.sub(text, 1, 2), 16),
		tonumber(string.sub(text, 3, 4), 16),
		tonumber(string.sub(text, 5, 6), 16)
	)
end

function types.hsv(h, s, v)
	local sector = math.floor(h * 6)
	local f = h * 6 - sector
	local p = v * (1 - s)
	local q = v * (1 - f * s)
	local t = v * (1 - (1 - f) * s)
	local slot = sector % 6

	if slot == 0 then
		return { v, t, p }
	elseif slot == 1 then
		return { q, v, p }
	elseif slot == 2 then
		return { p, v, t }
	elseif slot == 3 then
		return { p, q, v }
	elseif slot == 4 then
		return { t, p, v }
	end

	return { v, p, q }
end

function types.vector3(x, y, z)
	return { x or 0, y or 0, z or 0 }
end

function types.vector2(x, y)
	return { x or 0, y or 0 }
end

function types.udim(scale, offset)
	return { scale or 0, offset or 0 }
end

function types.udim2(xScale, xOffset, yScale, yOffset)
	return { xScale or 0, xOffset or 0, yScale or 0, yOffset or 0 }
end

function types.fromScale(x, y)
	return { x or 0, 0, y or 0, 0 }
end

function types.fromOffset(x, y)
	return { 0, x or 0, 0, y or 0 }
end

function types.cframe(x, y, z, ...)
	if select("#", ...) >= 9 then
		return { x, y, z, ... }
	end

	return { x or 0, y or 0, z or 0 }
end

function types.rect(minX, minY, maxX, maxY)
	return { minX or 0, minY or 0, maxX or 0, maxY or 0 }
end

function types.range(min, max)
	return { min, max or min }
end

function types.numberSequence(first, ...)
	if type(first) == "number" and select("#", ...) == 0 then
		return first
	end

	if type(first) == "table" and type(first[1]) == "table" then
		return first
	end

	return { first, ... }
end

local function isColor(value)
	return type(value) == "table" and #value == 3 and type(value[1]) == "number" and type(value[2]) == "number"
end

function types.colorSequence(...)
	local count = select("#", ...)
	local first = ...

	if count == 1 and type(first) == "table" and type(first[1]) == "table" and not isColor(first) then
		return first
	end

	if count == 1 then
		return { { 0, first }, { 1, first } }
	end

	if count == 2 and (isColor(first) or type(first) == "string") then
		return { { 0, first }, { 1, (select(2, ...)) } }
	end

	return { ... }
end

function types.font(family, weight, style)
	if not string.find(family, "/", 1, true) then
		family = "rbxasset://fonts/families/" .. family .. ".json"
	end

	return { family = family, weight = weight, style = style }
end

function types.typed(name, value)
	return { ["$Type"] = name, ["$Value"] = value }
end

roflux.types = types

local text = {}

function text.trim(value)
	return (string.gsub(value, "^%s*(.-)%s*$", "%1"))
end

function text.trimStart(value)
	return (string.gsub(value, "^%s+", ""))
end

function text.trimEnd(value)
	return (string.gsub(value, "%s+$", ""))
end

function text.startsWith(value, prefix)
	return string.sub(value, 1, #prefix) == prefix
end

function text.endsWith(value, suffix)
	return suffix == "" or string.sub(value, -#suffix) == suffix
end

function text.replace(value, find, with)
	if find == "" then
		return value
	end

	local out = {}
	local index = 1

	while true do
		local start, stop = string.find(value, find, index, true)

		if not start then
			break
		end

		table.insert(out, string.sub(value, index, start - 1))
		table.insert(out, with)
		index = stop + 1
	end

	table.insert(out, string.sub(value, index))

	return table.concat(out)
end

function text.split(value, separator)
	return string.split(value, separator or ",")
end

function text.lines(value)
	local out = {}

	for line in string.gmatch(value .. "\n", "(.-)\r?\n") do
		table.insert(out, line)
	end

	if out[#out] == "" then
		table.remove(out)
	end

	return out
end

function text.indent(value, prefix)
	local out = {}

	for _, line in text.lines(value) do
		table.insert(out, if line == "" then line else (prefix or "\t") .. line)
	end

	return table.concat(out, "\n")
end

function text.words(value)
	local spaced = string.gsub(value, "(%l)(%u)", "%1 %2")
	spaced = string.gsub(spaced, "(%u)(%u%l)", "%1 %2")
	spaced = string.gsub(spaced, "[^%w]+", " ")

	local out = {}

	for word in string.gmatch(spaced, "%w+") do
		table.insert(out, word)
	end

	return out
end

local function capital(word)
	return string.upper(string.sub(word, 1, 1)) .. string.lower(string.sub(word, 2))
end

local function joined(value, separator, shape)
	local out = {}

	for _, word in text.words(value) do
		table.insert(out, shape(word))
	end

	return table.concat(out, separator)
end

function text.pascal(value)
	return joined(value, "", capital)
end

function text.camel(value)
	local pascal = text.pascal(value)
	return string.lower(string.sub(pascal, 1, 1)) .. string.sub(pascal, 2)
end

function text.snake(value)
	return joined(value, "_", string.lower)
end

function text.kebab(value)
	return joined(value, "-", string.lower)
end

function text.title(value)
	return joined(value, " ", capital)
end

function text.padStart(value, width, fill)
	local filler = fill or " "

	while #value < width do
		value = filler .. value
	end

	return value
end

function text.padEnd(value, width, fill)
	local filler = fill or " "

	while #value < width do
		value ..= filler
	end

	return value
end

roflux.text = text

local path = {}

function path.normalize(value)
	local cleaned = string.gsub(value, "\\", "/")
	local parts = {}

	for part in string.gmatch(cleaned, "[^/]+") do
		if part == ".." then
			if #parts > 0 and parts[#parts] ~= ".." then
				table.remove(parts)
			else
				table.insert(parts, "..")
			end
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end

	return table.concat(parts, "/")
end

function path.join(...)
	return path.normalize(table.concat({ ... }, "/"))
end

function path.dirname(value)
	return string.match(path.normalize(value), "^(.*)/[^/]*$") or ""
end

function path.basename(value)
	local normal = path.normalize(value)
	return string.match(normal, "([^/]*)$") or normal
end

function path.extension(value)
	return string.lower(string.match(path.basename(value), "%.([^%.]+)$") or "")
end

function path.stem(value)
	local base = path.basename(value)
	return string.match(base, "^(.+)%.[^%.]+$") or base
end

function path.withExtension(value, extension)
	local folder = path.dirname(value)
	local cleaned = string.gsub(extension, "^%.", "")
	local file = if cleaned == "" then path.stem(value) else path.stem(value) .. "." .. cleaned

	return if folder == "" then file else folder .. "/" .. file
end

roflux.path = path

local tree = roflux.tree

local function steps(value)
	local out = {}

	for part in string.gmatch(value, "[^/]+") do
		table.insert(out, part)
	end

	return out
end

local function detach(parent, name)
	for index, child in parent.children do
		if child.name == name then
			table.remove(parent.children, index)
			return child
		end
	end

	return nil
end

function tree.child(node, name)
	for _, child in node.children do
		if child.name == name then
			return child
		end
	end

	return nil
end

function tree.find(root, target)
	local cursor = root

	for _, part in steps(target) do
		cursor = tree.child(cursor, part)

		if not cursor then
			return nil
		end
	end

	return cursor
end

local function copy(list)
	local out = {}

	for index = 1, #list do
		out[index] = list[index]
	end

	return out
end

function tree.each(root, visit)
	local function walk(node, trail)
		visit(node, trail)

		for _, child in copy(node.children) do
			walk(child, trail .. "/" .. child.name)
		end
	end

	for _, child in copy(root.children) do
		walk(child, child.name)
	end
end

function tree.add(parent, node)
	detach(parent, node.name)
	table.insert(parent.children, node)
	return node
end

function tree.remove(root, target)
	local parts = steps(target)
	local name = table.remove(parts)

	if not name then
		return nil
	end

	local parent = if #parts == 0 then root else tree.find(root, table.concat(parts, "/"))

	if not parent then
		return nil
	end

	return detach(parent, name)
end

function tree.ensure(root, target)
	local cursor = root

	for depth, part in steps(target) do
		local found = tree.child(cursor, part)

		if not found then
			found = tree.node(part, if depth == 1 then part else "Folder")
			found.ownership = "passthrough"
			table.insert(cursor.children, found)
		end

		cursor = found
	end

	return cursor
end
