--!strict

local Decode = {}

type Any = any

local function number(value: Any, fallback: number): number
	return if type(value) == "number" then value else fallback
end

local function list(value: Any): { Any }
	return if type(value) == "table" then value else {}
end

local function field(value: Any, key: string, index: number, fallback: number): number
	if type(value) ~= "table" then
		return fallback
	end

	local named = (value :: Any)[key]

	if type(named) == "number" then
		return named
	end

	return number((value :: Any)[index], fallback)
end

local function hex(value: string): Color3?
	local text = value:gsub("^#", "")

	if #text ~= 6 then
		return nil
	end

	local red = tonumber(text:sub(1, 2), 16)
	local green = tonumber(text:sub(3, 4), 16)
	local blue = tonumber(text:sub(5, 6), 16)

	if not red or not green or not blue then
		return nil
	end

	return Color3.fromRGB(red, green, blue)
end

local Readers: { [string]: (Any) -> Any } = {}

Readers.string = function(value)
	return if type(value) == "string" then value else tostring(value)
end

Readers.number = function(value)
	return tonumber(value)
end

Readers.boolean = function(value)
	return value == true
end

Readers.Vector3 = function(value)
	return Vector3.new(field(value, "x", 1, 0), field(value, "y", 2, 0), field(value, "z", 3, 0))
end

Readers.Vector2 = function(value)
	return Vector2.new(field(value, "x", 1, 0), field(value, "y", 2, 0))
end

Readers.UDim = function(value)
	return UDim.new(field(value, "Scale", 1, 0), field(value, "Offset", 2, 0))
end

Readers.UDim2 = function(value)
	local entries = list(value)

	if type(entries[1]) == "table" then
		local x = list(entries[1])
		local y = list(entries[2])

		return UDim2.new(number(x[1], 0), number(x[2], 0), number(y[1], 0), number(y[2], 0))
	end

	return UDim2.new(
		field(value, "ScaleX", 1, 0),
		field(value, "OffsetX", 2, 0),
		field(value, "ScaleY", 3, 0),
		field(value, "OffsetY", 4, 0)
	)
end

Readers.Color3 = function(value)
	if type(value) == "string" then
		return hex(value)
	end

	local entries = list(value)
	local red = number(entries[1], 0)
	local green = number(entries[2], 0)
	local blue = number(entries[3], 0)

	if red > 1 or green > 1 or blue > 1 then
		return Color3.fromRGB(red, green, blue)
	end

	return Color3.new(red, green, blue)
end

Readers.BrickColor = function(value)
	if type(value) == "string" then
		return BrickColor.new(value)
	end

	if type(value) == "number" then
		return BrickColor.new(value)
	end

	return nil
end

Readers.CFrame = function(value)
	local entries = list(value)

	if #entries >= 12 then
		return CFrame.new(table.unpack(entries, 1, 12))
	end

	if #entries >= 3 then
		return CFrame.new(number(entries[1], 0), number(entries[2], 0), number(entries[3], 0))
	end

	return CFrame.identity
end

Readers.Rect = function(value)
	local entries = list(value)

	return Rect.new(
		number(entries[1], 0),
		number(entries[2], 0),
		number(entries[3], 0),
		number(entries[4], 0)
	)
end

Readers.NumberRange = function(value)
	if type(value) == "number" then
		return NumberRange.new(value)
	end

	local entries = list(value)

	return NumberRange.new(number(entries[1], 0), number(entries[2], number(entries[1], 0)))
end

Readers.NumberSequence = function(value)
	if type(value) == "number" then
		return NumberSequence.new(value)
	end

	local points = {}

	for _, entry in list(value) do
		table.insert(
			points,
			NumberSequenceKeypoint.new(
				field(entry, "time", 1, 0),
				field(entry, "value", 2, 0),
				field(entry, "envelope", 3, 0)
			)
		)
	end

	if #points < 2 then
		return NumberSequence.new(0)
	end

	return NumberSequence.new(points)
end

Readers.ColorSequence = function(value)
	local points = {}

	for _, entry in list(value) do
		local color = Readers.Color3(if type(entry) == "table" then (entry :: Any).value or (entry :: Any)[2] else entry)

		table.insert(points, ColorSequenceKeypoint.new(field(entry, "time", 1, 0), color or Color3.new()))
	end

	if #points < 2 then
		return ColorSequence.new(Color3.new())
	end

	return ColorSequence.new(points)
end

Readers.Vector3int16 = function(value)
	return Vector3int16.new(field(value, "x", 1, 0), field(value, "y", 2, 0), field(value, "z", 3, 0))
end

Readers.Vector2int16 = function(value)
	return Vector2int16.new(field(value, "x", 1, 0), field(value, "y", 2, 0))
end

Readers.Font = function(value)
	if type(value) == "string" then
		return Font.new(value)
	end

	local family = (value :: Any).family or (value :: Any).Family

	if type(family) ~= "string" then
		return nil
	end

	local weight = (value :: Any).weight or (value :: Any).Weight
	local style = (value :: Any).style or (value :: Any).Style

	return Font.new(
		family,
		if type(weight) == "string" then (Enum.FontWeight :: Any)[weight] else Enum.FontWeight.Regular,
		if type(style) == "string" then (Enum.FontStyle :: Any)[style] else Enum.FontStyle.Normal
	)
end

local function enum(current: EnumItem, value: Any): EnumItem?
	local kind = current.EnumType

	if type(value) == "string" then
		local ok, item = pcall(function()
			return (kind :: Any)[value]
		end)

		return if ok then item else nil
	end

	if type(value) == "number" then
		for _, item in kind:GetEnumItems() do
			if item.Value == value then
				return item
			end
		end
	end

	return nil
end

local Epsilon = 1e-5

local function near(a: number, b: number): boolean
	local scale = math.max(1, math.abs(a), math.abs(b))
	return math.abs(a - b) <= Epsilon * scale
end

function Decode.same(a: Any, b: Any): boolean
	local kind = typeof(a)

	if kind ~= typeof(b) then
		return false
	end

	if kind == "number" then
		return near(a, b)
	end

	if kind == "Color3" then
		return near(a.R, b.R) and near(a.G, b.G) and near(a.B, b.B)
	end

	if kind == "Vector3" then
		return near(a.X, b.X) and near(a.Y, b.Y) and near(a.Z, b.Z)
	end

	if kind == "Vector2" then
		return near(a.X, b.X) and near(a.Y, b.Y)
	end

	if kind == "UDim" then
		return near(a.Scale, b.Scale) and a.Offset == b.Offset
	end

	if kind == "UDim2" then
		return Decode.same(a.X, b.X) and Decode.same(a.Y, b.Y)
	end

	if kind == "Rect" then
		return Decode.same(a.Min, b.Min) and Decode.same(a.Max, b.Max)
	end

	if kind == "NumberRange" then
		return near(a.Min, b.Min) and near(a.Max, b.Max)
	end

	if kind == "CFrame" then
		local left = { a:GetComponents() }
		local right = { b:GetComponents() }

		for index, value in left do
			if not near(value, right[index]) then
				return false
			end
		end

		return true
	end

	return a == b
end

function Decode.tagged(value: Any): (boolean, Any)
	if type(value) ~= "table" then
		return false, nil
	end

	local kind = (value :: Any)["$Type"]

	if type(kind) ~= "string" then
		return false, nil
	end

	local reader = Readers[kind]

	if not reader then
		return false, nil
	end

	return true, reader((value :: Any)["$Value"])
end

function Decode.coerce(current: Any, value: Any): Any
	local tagged, decoded = Decode.tagged(value)

	if tagged then
		return decoded
	end

	local kind = typeof(current)

	if kind == "EnumItem" then
		return enum(current :: EnumItem, value)
	end

	local reader = Readers[kind]

	if reader then
		return reader(value)
	end

	return value
end

function Decode.attribute(value: Any): Any
	local tagged, decoded = Decode.tagged(value)

	if tagged then
		return decoded
	end

	if type(value) == "table" then
		local entries = list(value)

		if #entries == 3 then
			return Readers.Vector3(value)
		end

		if #entries == 2 then
			return Readers.Vector2(value)
		end

		return nil
	end

	return value
end

Decode.readers = Readers

return Decode
