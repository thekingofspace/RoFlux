--!strict

local Encode = {}

local Depth = 16

local function number(value: number): any
	if value ~= value then
		return "nan"
	end

	if value == math.huge then
		return "inf"
	end

	if value == -math.huge then
		return "-inf"
	end

	return value
end

local function vector3(value: any): { [string]: any }
	return { X = number(value.X), Y = number(value.Y), Z = number(value.Z) }
end

local function vector2(value: any): { [string]: any }
	return { X = number(value.X), Y = number(value.Y) }
end

local function color(value: Color3): { [string]: any }
	return { R = value.R, G = value.G, B = value.B }
end

local function udim(value: UDim): { [string]: any }
	return { Scale = value.Scale, Offset = value.Offset }
end

local function cframe(value: CFrame): { [string]: any }
	local rx, ry, rz = value:ToOrientation()

	return {
		X = value.X,
		Y = value.Y,
		Z = value.Z,
		Position = vector3(value.Position),
		LookVector = vector3(value.LookVector),
		RightVector = vector3(value.RightVector),
		UpVector = vector3(value.UpVector),
		Orientation = { X = math.deg(rx), Y = math.deg(ry), Z = math.deg(rz) },
		Components = { value:GetComponents() },
	}
end

local Datatypes: { [string]: (any) -> { [string]: any } } = {
	Vector3 = vector3,
	Vector2 = vector2,
	Vector3int16 = vector3,
	Vector2int16 = vector2,
	CFrame = cframe,
	Color3 = function(value)
		local out = color(value)
		out.Hex = value:ToHex()
		return out
	end,
	BrickColor = function(value)
		return { Name = value.Name, Number = value.Number, Color = color(value.Color) }
	end,
	UDim = udim,
	UDim2 = function(value)
		return { X = udim(value.X), Y = udim(value.Y) }
	end,
	Rect = function(value)
		return { Min = vector2(value.Min), Max = vector2(value.Max), Width = value.Width, Height = value.Height }
	end,
	NumberRange = function(value)
		return { Min = value.Min, Max = value.Max }
	end,
	NumberSequence = function(value)
		local points = {}

		for _, point in value.Keypoints do
			table.insert(points, { Time = point.Time, Value = point.Value, Envelope = point.Envelope })
		end

		return { Keypoints = points }
	end,
	ColorSequence = function(value)
		local points = {}

		for _, point in value.Keypoints do
			table.insert(points, { Time = point.Time, Color = color(point.Value) })
		end

		return { Keypoints = points }
	end,
	EnumItem = function(value)
		return { EnumType = tostring(value.EnumType), Name = value.Name, Value = value.Value }
	end,
	Enum = function(value)
		return { Name = tostring(value) }
	end,
	Font = function(value)
		return { Family = value.Family, Weight = value.Weight.Name, Style = value.Style.Name }
	end,
	DateTime = function(value)
		return { UnixTimestampMillis = value.UnixTimestampMillis, Iso = value:ToIsoDate() }
	end,
	Ray = function(value)
		return { Origin = vector3(value.Origin), Direction = vector3(value.Direction) }
	end,
	Region3 = function(value)
		return { CFrame = cframe(value.CFrame), Size = vector3(value.Size) }
	end,
	PhysicalProperties = function(value)
		return {
			Density = value.Density,
			Friction = value.Friction,
			Elasticity = value.Elasticity,
			FrictionWeight = value.FrictionWeight,
			ElasticityWeight = value.ElasticityWeight,
		}
	end,
	TweenInfo = function(value)
		return {
			Time = value.Time,
			EasingStyle = value.EasingStyle.Name,
			EasingDirection = value.EasingDirection.Name,
			RepeatCount = value.RepeatCount,
			Reverses = value.Reverses,
			DelayTime = value.DelayTime,
		}
	end,
	Instance = function(value)
		return { ClassName = value.ClassName, Name = value.Name, Path = value:GetFullName() }
	end,
	buffer = function(value)
		return { Size = buffer.len(value) }
	end,
}

local function encode(value: any, depth: number, seen: { [any]: boolean }): any
	local kind = typeof(value)

	if kind == "nil" or kind == "boolean" or kind == "string" then
		return value
	end

	if kind == "number" then
		return number(value)
	end

	if kind == "table" then
		if seen[value] then
			return "<cycle>"
		end

		if depth >= Depth then
			return "<too deep>"
		end

		seen[value] = true

		local count = 0

		for _ in value do
			count += 1
		end

		local out: { [any]: any } = {}

		if count > 0 and count == #value then
			for index = 1, #value do
				out[index] = encode(value[index], depth + 1, seen)
			end
		else
			for key, entry in value do
				out[tostring(key)] = encode(entry, depth + 1, seen)
			end
		end

		seen[value] = nil

		return out
	end

	local convert = Datatypes[kind]

	if convert then
		local ok, converted = pcall(convert, value)

		if ok then
			converted.type = kind
			return converted
		end
	end

	return { type = kind, value = tostring(value) }
end

function Encode.value(value: any): any
	return encode(value, 0, {})
end

function Encode.tuple(...: any): { n: number, items: { [string]: any } }
	local count = select("#", ...)
	local items = {}

	for index = 1, count do
		local value = select(index, ...)

		if value ~= nil then
			items[tostring(index)] = encode(value, 0, {})
		end
	end

	return { n = count, items = items }
end

function Encode.unpack(args: any): (number, { any })
	local values = {}

	if type(args) ~= "table" then
		return 0, values
	end

	local count = tonumber(args.n) or 0
	local items = args.items

	if type(items) == "table" then
		for index = 1, count do
			local value = items[tostring(index)]

			if value == nil then
				value = items[index]
			end

			values[index] = value
		end
	end

	return count, values
end

return Encode
