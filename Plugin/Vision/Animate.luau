--!strict

const Symbols = require(script.Parent.Symbols)
const Capture = require(script.Parent.Capture)
const Types = require(script.Parent.Types)

type Store = Types.Dynamic

type Listener = (any, ...any) -> ()

type Binds = { [string]: { Listener } }

type Peek = (Key: string) -> any

type Put = (Key: string, Value: any) -> ()

type Fire = (Name: string, Args: { any }) -> ()

type Link = {
    Elapsed: number,
    Finished: boolean,
    Looped: boolean,
    RestageTime: number,
    SmoothLoop: boolean,
    Speed: number,
    Await: (self: Link) -> (),
    Cancel: (self: Link) -> (),
    Seek: (self: Link, Time: number) -> (),
}

type Runtime = {
    Play: (
        self: Runtime,
        Target: any,
        Peek: Peek,
        Put: Put,
        Tracks: { any },
        Marks: { any },
        Length: number,
        Fire: Fire,
        Start: number?
    ) -> Link,
}

type Scope = { Runtime: Runtime }

const Methods = {} :: Store

const Tuning: { [string]: string } =
    { Looped = "boolean", SmoothLoop = "boolean", Speed = "number", RestageTime = "number" }

const Animation = {
    __index = function(self: any, Key: string): any
        if Key == "Finished" then
            const Link = rawget(self, "Link") :: Link?

            return Link == nil or Link.Finished
        end

        if Key == "Time" then
            const Link = rawget(self, "Link") :: Link?

            return if Link then Link.Elapsed else (rawget(self, "Saved") :: Store).Time
        end

        if Tuning[Key] then
            return (rawget(self, "Saved") :: Store)[Key]
        end

        return Methods[Key]
    end,

    __newindex = function(self: any, Key: string, Value: any)
        const Want = Tuning[Key]

        if not Want then
            rawset(self, Key, Value)

            return
        end

        if type(Value) ~= Want then
            error(`an animation's {Key} must be a {Want}`, 0)
        end

        if Key == "Speed" and Value < 0 then
            error("an animation's Speed cannot be negative", 0)
        end

        if Key == "RestageTime" and Value < 0 then
            error("an animation's RestageTime cannot be negative", 0)
        end

        const Saved = rawget(self, "Saved") :: Store

        Saved[Key] = Value

        const Link = rawget(self, "Link") :: any

        if Link and not Link.Finished then
            Link[Key] = Value
        end
    end,
}

const function Order(Left: any, Right: any): boolean
    return Left.Time < Right.Time
end

const function Read(Keyframes: { any })
    if type(Keyframes) ~= "table" or #Keyframes == 0 then
        error("an animation needs at least one keyframe", 0)
    end

    const Sorted = table.clone(Keyframes)

    for Index, Entry in Sorted do
        if not Symbols.Framed(Entry) then
            error(`entry {Index} of the animation is not a Keyframe`, 0)
        end
    end

    table.sort(Sorted, Order)

    const Tracks = {}
    const Named = {}
    const Marks = {}

    local Length = 0

    for _, Frame in Sorted do
        if Frame.Time > Length then
            Length = Frame.Time
        end

        for Property, Value in Frame.Properties do
            local Track = Named[Property]

            if not Track then
                Track = { Property = Property, Stops = {}, Index = 0, From = nil, Springy = false }
                Named[Property] = Track
                table.insert(Tracks, Track)
            end

            table.insert(Track.Stops, { Time = Frame.Time, Value = Value, Easing = Frame.Easing })
        end

        if Frame.Events then
            for Name, Args in Frame.Events do
                table.insert(Marks, { Time = Frame.Time, Name = Name, Args = if type(Args) == "table" then Args else { Args } })
            end
        end
    end

    table.sort(Marks, Order)

    if #Tracks == 0 and #Marks == 0 then
        error("an animation needs at least one property or event", 0)
    end

    return Tracks, Marks, Length
end

const function Reach(Target: any, Tracks: { any })
    if Capture.Is(Target) then
        for _, Track in Tracks do
            if type(Target[Track.Property]) ~= "function" then
                error(`this vision has no value named "{Track.Property}"`, 0)
            end
        end

        return function(Key: string): any
            return Target[Key]()
        end, function(Key: string, Value: any)
            Target[Key](Value)
        end
    end

    if typeof(Target) ~= "Instance" then
        error("an animation needs an instance or a vision to play on", 0)
    end

    const Fields = (Target :: any) :: Types.Dynamic

    return function(Key: string): any
        return Fields[Key]
    end, function(Key: string, Value: any)
        Fields[Key] = Value
    end
end

function Animation.new(Scope: any, Keyframes: { any }, Target: any)
    const Tracks, Marks, Length = Read(Keyframes)
    const Peek, Put = Reach(Target, Tracks)

    const Self = setmetatable({}, Animation) :: any

    rawset(Self, "Saved", { Looped = false, SmoothLoop = false, Speed = 1, RestageTime = 0.25, Time = 0 })
    rawset(Self, "Binds", {})
    rawset(Self, "Scope", Scope)
    rawset(Self, "Target", Target)
    rawset(Self, "Tracks", Tracks)
    rawset(Self, "Marks", Marks)
    rawset(Self, "Length", Length)
    rawset(Self, "Peek", Peek)
    rawset(Self, "Put", Put)
    rawset(Self, "Link", nil)

    const Binds = rawget(Self, "Binds") :: Binds

    rawset(Self, "Fire", function(Name: string, Args: { any })
        const Listeners = Binds[Name]

        if not Listeners then
            return
        end

        for _, Callback in table.clone(Listeners) do
            Callback(Target, table.unpack(Args))
        end
    end)

    return Self
end

function Methods:Play()
    const Live = rawget(self, "Link") :: Link?

    if Live and not Live.Finished then
        return self
    end

    const Scope = rawget(self, "Scope") :: Scope?

    if not Scope then
        return self
    end

    const Saved = rawget(self, "Saved") :: Store

    if Live then
        Saved.Time = Live.Elapsed
    end

    const Link = Scope.Runtime:Play(
        rawget(self, "Target"),
        rawget(self, "Peek") :: Peek,
        rawget(self, "Put") :: Put,
        rawget(self, "Tracks") :: { any },
        rawget(self, "Marks") :: { any },
        rawget(self, "Length") :: number,
        rawget(self, "Fire") :: Fire,
        Saved.Time
    )

    Link.Speed = Saved.Speed
    Link.Looped = Saved.Looped
    Link.SmoothLoop = Saved.SmoothLoop
    Link.RestageTime = Saved.RestageTime

    rawset(self, "Link", Link)

    return self
end

function Methods:Bind(Name: string, Callback: (any, ...any) -> ())
    if type(Name) ~= "string" then
        error("an animation event needs a name", 0)
    end

    const Binds = rawget(self, "Binds") :: Binds?

    if not Binds then
        return { Disconnect = function() end }
    end

    local Listeners = Binds[Name]

    if not Listeners then
        Listeners = {}
        Binds[Name] = Listeners
    end

    table.insert(Listeners, Callback)

    return {
        Disconnect = function()
            const Slot = if Listeners then table.find(Listeners, Callback) else nil

            if Slot then
                table.remove(Listeners, Slot)
            end
        end,
    }
end

function Methods:Jump(Time: number)
    if type(Time) ~= "number" then
        error("Jump needs a time in seconds", 0)
    end

    const Spot = math.clamp(Time, 0, (rawget(self, "Length") :: number?) or 0)
    const Saved = rawget(self, "Saved") :: Store

    Saved.Time = Spot

    const Link = rawget(self, "Link") :: Link?

    if Link then
        if Link.Finished then
            rawset(self, "Link", nil)
        else
            Link:Seek(Spot)
        end
    end

    return self
end

function Methods:Await()
    const Link = rawget(self, "Link") :: Link?

    if Link and not Link.Finished then
        Link:Await()
    end
end

function Methods:Stop()
    const Link = rawget(self, "Link") :: Link?

    if Link then
        if not Link.Finished then
            const Saved = rawget(self, "Saved") :: Store

            Saved.Time = Link.Elapsed
        end

        Link:Cancel()
    end

    rawset(self, "Link", nil)

    return self
end

function Methods:Destroy()
    self:Stop()

    const Binds = rawget(self, "Binds") :: Binds?

    if Binds then
        for _, Listeners in Binds do
            table.clear(Listeners)
        end

        table.clear(Binds)
    end

    rawset(self, "Binds", nil)
    rawset(self, "Scope", nil)
    rawset(self, "Target", nil)
    rawset(self, "Tracks", nil)
    rawset(self, "Marks", nil)
    rawset(self, "Peek", nil)
    rawset(self, "Put", nil)
    rawset(self, "Fire", nil)
end

return Animation
