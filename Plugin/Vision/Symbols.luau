--!strict

const Symbols = {}

const Marker = {}
Marker.__index = Marker

const Token = {}
const Bind = {}
const Graft = {}
const Frame = {}

function Symbols.Is(Value: any): boolean
    return type(Value) == "table" and getmetatable(Value) == Marker
end

function Symbols.event(Event: string, InitialValue: any, Callback: (Instance, any, any) -> ())
    return setmetatable({
        Kind = "Event",
        Name = Event,
        Initial = InitialValue,
        Callback = Callback,
    }, Marker)
end

function Symbols.merge(Event: string, Callback: (Instance, any, any) -> ())
    return setmetatable({
        Kind = "Merge",
        Name = Event,
        Callback = Callback,
    }, Marker)
end

function Symbols.derive(
    Name: string,
    Compute: (Mode: string, Read: (string) -> any, Write: (string, any) -> any, Value: any) -> any
)
    return setmetatable({
        Kind = "Derive",
        Name = Name,
        Callback = Compute,
    }, Marker)
end

function Symbols.ready(Callback: (Instance, any, any) -> ())
    return setmetatable({
        Kind = "Ready",
        Callback = Callback,
    }, Marker)
end

function Symbols.cleanup(Callback: (Instance, any) -> ())
    return setmetatable({
        Kind = "Cleanup",
        Callback = Callback,
    }, Marker)
end

function Symbols.drawcall(Callback: (Instance, any, Vector2) -> ())
    return setmetatable({
        Kind = "Draw",
        Callback = Callback,
    }, Marker)
end

function Symbols.receive(Callback: (Instance, any, Instance, any) -> Instance?)
    return setmetatable({
        Kind = "Receive",
        Callback = Callback,
    }, Marker)
end

function Symbols.Injected(Value: any): boolean
    return type(Value) == "table" and getmetatable(Value) == Graft
end

function Symbols.inject(...: any)
    return setmetatable({ Hosts = { ... } }, Graft)
end

function Symbols.Styled(Value: any): boolean
    return type(Value) == "table" and getmetatable(Value) == Token
end

function Symbols.Bound(Value: any): boolean
    return type(Value) == "table" and getmetatable(Value) == Bind
end

function Symbols.fromEvent(Event: string, InitialValue: any?)
    if type(Event) ~= "string" then
        error("fromEvent needs the name of a value to follow", 0)
    end

    return setmetatable({
        Name = Event,
        Initial = InitialValue,
    }, Bind)
end

function Symbols.style(Name: string)
    return setmetatable({}, {
        __index = function(_, Field: string)
            return setmetatable({ Style = Name, Field = Field }, Token)
        end,
    })
end

function Symbols.fromClone(Target: Instance)
    return setmetatable({
        Kind = "Clone",
        Target = Target,
    }, Marker)
end

function Symbols.fromInstance(Target: Instance)
    return setmetatable({
        Kind = "Adopt",
        Target = Target,
    }, Marker)
end

function Symbols.mount(Target: Instance | string)
    return setmetatable({
        Kind = "Mount",
        Target = Target,
    }, Marker)
end

function Symbols.Framed(Value: any): boolean
    return type(Value) == "table" and getmetatable(Value) == Frame
end

function Symbols.Keyframe(Easing: any, Time: number, Properties: any, Events: any?)
    if type(Time) ~= "number" then
        error("a keyframe needs a time in seconds", 0)
    end

    if type(Properties) ~= "table" then
        error("a keyframe needs a table of properties", 0)
    end

    return setmetatable({
        Easing = Easing,
        Time = Time,
        Properties = Properties,
        Events = Events,
    }, Frame)
end

Symbols.Token = Token
Symbols.Graft = Graft

return Symbols
