--!strict

const TweenService = game:GetService("TweenService")

const Interpolate = {}

const function Scalar(Start: number, Goal: number, Alpha: number): number
    return Start + (Goal - Start) * Alpha
end

local Lerps: { [string]: (any, any, number) -> any } = {
    number = Scalar,

    string = function(Start: string, Goal: string, Alpha: number)
        if Alpha >= 1 then
            return Goal
        end

        const Length = utf8.len(Goal) or #Goal
        const Count = math.round(Scalar(utf8.len(Start) or #Start, Length, Alpha))

        if Count <= 0 then
            return ""
        end

        if Count >= Length then
            return Goal
        end

        const Offset = utf8.offset(Goal, Count + 1)

        return if Offset then string.sub(Goal, 1, Offset - 1) else Goal
    end,

    UDim = function(Start: UDim, Goal: UDim, Alpha: number)
        return UDim.new(
            Scalar(Start.Scale, Goal.Scale, Alpha),
            math.round(Scalar(Start.Offset, Goal.Offset, Alpha))
        )
    end,

    Rect = function(Start: Rect, Goal: Rect, Alpha: number)
        return Rect.new(Start.Min:Lerp(Goal.Min, Alpha), Start.Max:Lerp(Goal.Max, Alpha))
    end,

    NumberRange = function(Start: NumberRange, Goal: NumberRange, Alpha: number)
        return NumberRange.new(Scalar(Start.Min, Goal.Min, Alpha), Scalar(Start.Max, Goal.Max, Alpha))
    end,

    Vector2int16 = function(Start: Vector2int16, Goal: Vector2int16, Alpha: number)
        return Vector2int16.new(
            math.round(Scalar(Start.X, Goal.X, Alpha)),
            math.round(Scalar(Start.Y, Goal.Y, Alpha))
        )
    end,

    Vector3int16 = function(Start: Vector3int16, Goal: Vector3int16, Alpha: number)
        return Vector3int16.new(
            math.round(Scalar(Start.X, Goal.X, Alpha)),
            math.round(Scalar(Start.Y, Goal.Y, Alpha)),
            math.round(Scalar(Start.Z, Goal.Z, Alpha))
        )
    end,

    Vector2 = function(Start: Vector2, Goal: Vector2, Alpha: number)
        return Start:Lerp(Goal, Alpha)
    end,

    Vector3 = function(Start: Vector3, Goal: Vector3, Alpha: number)
        return Start:Lerp(Goal, Alpha)
    end,

    UDim2 = function(Start: UDim2, Goal: UDim2, Alpha: number)
        return Start:Lerp(Goal, Alpha)
    end,

    CFrame = function(Start: CFrame, Goal: CFrame, Alpha: number)
        return Start:Lerp(Goal, Alpha)
    end,

    Color3 = function(Start: Color3, Goal: Color3, Alpha: number)
        return Start:Lerp(Goal, Alpha)
    end,

    NumberSequence = function(Start: NumberSequence, Goal: NumberSequence, Alpha: number)
        const From = Start.Keypoints
        const To = Goal.Keypoints

        if #From ~= #To then
            return if Alpha >= 0.5 then Goal else Start
        end

        const Keypoints = table.create(#From) :: { NumberSequenceKeypoint }

        for Index, Point in From do
            const Other = To[Index]

            Keypoints[Index] = NumberSequenceKeypoint.new(
                Scalar(Point.Time, Other.Time, Alpha),
                Scalar(Point.Value, Other.Value, Alpha),
                Scalar(Point.Envelope, Other.Envelope, Alpha)
            )
        end

        return NumberSequence.new(Keypoints)
    end,

    ColorSequence = function(Start: ColorSequence, Goal: ColorSequence, Alpha: number)
        const From = Start.Keypoints
        const To = Goal.Keypoints

        if #From ~= #To then
            return if Alpha >= 0.5 then Goal else Start
        end

        const Keypoints = table.create(#From) :: { ColorSequenceKeypoint }

        for Index, Point in From do
            const Other = To[Index]

            Keypoints[Index] = ColorSequenceKeypoint.new(
                Scalar(Point.Time, Other.Time, Alpha),
                Point.Value:Lerp(Other.Value, Alpha)
            )
        end

        return ColorSequence.new(Keypoints)
    end,
}

function Interpolate.Value(Start: any, Goal: any, Alpha: number): any
    const Kind = typeof(Start)

    if Kind ~= typeof(Goal) then
        return if Alpha >= 0.5 then Goal else Start
    end

    const Lerp = Lerps[Kind]

    if Lerp then
        return Lerp(Start, Goal, Alpha)
    end

    return if Alpha >= 0.5 then Goal else Start
end

local Shapes: { [string]: { Read: (any) -> { number }, Make: ({ number }) -> any } } = {
    number = {
        Read = function(Value: number)
            return { Value }
        end,
        Make = function(Parts)
            return Parts[1]
        end,
    },

    UDim = {
        Read = function(Value: UDim)
            return { Value.Scale, Value.Offset }
        end,
        Make = function(Parts)
            return UDim.new(Parts[1], math.round(Parts[2]))
        end,
    },

    UDim2 = {
        Read = function(Value: UDim2)
            return { Value.X.Scale, Value.X.Offset, Value.Y.Scale, Value.Y.Offset }
        end,
        Make = function(Parts)
            return UDim2.new(Parts[1], math.round(Parts[2]), Parts[3], math.round(Parts[4]))
        end,
    },

    Vector2 = {
        Read = function(Value: Vector2)
            return { Value.X, Value.Y }
        end,
        Make = function(Parts)
            return Vector2.new(Parts[1], Parts[2])
        end,
    },

    Vector3 = {
        Read = function(Value: Vector3)
            return { Value.X, Value.Y, Value.Z }
        end,
        Make = function(Parts)
            return Vector3.new(Parts[1], Parts[2], Parts[3])
        end,
    },

    Color3 = {
        Read = function(Value: Color3)
            return { Value.R, Value.G, Value.B }
        end,
        Make = function(Parts)
            return Color3.new(
                math.clamp(Parts[1], 0, 1),
                math.clamp(Parts[2], 0, 1),
                math.clamp(Parts[3], 0, 1)
            )
        end,
    },

    Rect = {
        Read = function(Value: Rect)
            return { Value.Min.X, Value.Min.Y, Value.Max.X, Value.Max.Y }
        end,
        Make = function(Parts)
            return Rect.new(Parts[1], Parts[2], Parts[3], Parts[4])
        end,
    },

    NumberRange = {
        Read = function(Value: NumberRange)
            return { Value.Min, Value.Max }
        end,
        Make = function(Parts)
            return NumberRange.new(Parts[1], math.max(Parts[1], Parts[2]))
        end,
    },
}

function Interpolate.Components(Value: any): { number }?
    const Shape = Shapes[typeof(Value)]

    return if Shape then Shape.Read(Value) else nil
end

function Interpolate.Rebuild(Kind: string, Parts: { number }): any
    return Shapes[Kind].Make(Parts)
end

function Interpolate.Maker(Kind: string)
    return Shapes[Kind].Make
end

function Interpolate.Solvable(Value: any): boolean
    return Shapes[typeof(Value)] ~= nil
end

function Interpolate.Cycle(Info: TweenInfo, Elapsed: number): (number, boolean)
    const Duration = Info.Time
    const Span = Duration * (if Info.Reverses then 2 else 1)
    const Length = Info.DelayTime + Span

    if Elapsed >= Length then
        return if Info.Reverses then 0 else 1, true
    end

    const Played = Elapsed - Info.DelayTime

    if Played <= 0 then
        return 0, false
    end

    local Alpha
    if Info.Reverses and Played > Duration then
        Alpha = 1 - (if Duration > 0 then (Played - Duration) / Duration else 1)
    else
        Alpha = if Duration > 0 then Played / Duration else 1
    end

    return TweenService:GetValue(math.clamp(Alpha, 0, 1), Info.EasingStyle, Info.EasingDirection), false
end

function Interpolate.Curve(Info: TweenInfo, Alpha: number): number
    return TweenService:GetValue(math.clamp(Alpha, 0, 1), Info.EasingStyle, Info.EasingDirection)
end

return Interpolate
