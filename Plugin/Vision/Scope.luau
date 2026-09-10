--!strict

local Runtime = require(script.Parent.Link)
const Capture = require(script.Parent.Capture)
const Interpolate = require(script.Parent.Interpolate)
const Style = require(script.Parent.Style)
const Animation = require(script.Parent.Animate)
const Flipbook = require(script.Parent.Flipbook)

type StyleSheet = {
    Name: string,
    Get: (self: StyleSheet, Field: string) -> any,
    Set: (self: StyleSheet, Field: string, Value: any) -> (),
    Load: (self: StyleSheet, Declaration: { [string]: any }) -> (),
    Release: (self: StyleSheet) -> (),
}

type Owners = { [any]: boolean }

const Scope = {}
Scope.__index = Scope

const Live: { [any]: boolean } = {}

const function AsList(Value: any): { any }
    if typeof(Value) == "Instance" or Capture.Is(Value) then
        return { Value }
    end

    return Value
end

const function Sheet(self, Value: any)
    if Style.Is(Value) then
        return Value
    end

    const Found = self.Styles[Value]

    if not Found then
        error(`style "{tostring(Value)}" is not loaded on this scope`, 0)
    end

    return Found
end

const function AsSheets(self, Value: any): { any }
    if type(Value) == "string" or Style.Is(Value) then
        return { Sheet(self, Value) }
    end

    const Out = {}

    for _, Item in Value do
        table.insert(Out, Sheet(self, Item))
    end

    return Out
end

const function Start(Target, Field: string): any
    const Current = Target:Get(Field)

    if Current == nil then
        error(`style "{Target.Name}" has no field "{Field}" to animate from`, 0)
    end

    return Current
end

function Scope.new()
    return setmetatable({
        Runtime = Runtime.new(),
        Visions = {} :: { any },
        Styles = {} :: { [string]: StyleSheet },
        Owned = setmetatable({}, { __mode = "k" }),
    }, Scope)
end

function Scope:Capture(Declaration: any)
    return Capture.new(self, Declaration)
end

function Scope:LoadStyle(Declaration: any)
    const Name = Declaration.name or Declaration.Name

    if type(Name) ~= "string" then
        error("a style declaration needs a name", 0)
    end

    local Sheet: StyleSheet = self.Styles[Name]

    if not Sheet then
        Sheet = (Style.new(Name) :: any) :: StyleSheet
        self.Styles[Name] = Sheet
    end

    Sheet:Load(Declaration)

    return Sheet
end

function Scope:Animate(Keyframes: { any }, Target: any)
    return Animation.new(self, Keyframes, Target)
end

function Scope:FlipBook(Sheet: any, Object: Instance, Frames: { string }, Rate: number?)
    return Flipbook.new(self, Sheet, Object, Frames, Rate)
end

function Scope:Update(EventName: string, Value: any)
    for Vision in self.Owned :: Owners do
        if type(Vision[EventName]) == "function" then
            Vision[EventName](Value)
        end
    end
end

function Scope:Adopt(Vision: any)
    self.Owned[Vision] = true

    if not table.find(self.Visions, Vision) then
        table.insert(self.Visions, Vision)
    end

    Live[self] = true
end

function Scope:Forget(Vision: any)
    self.Owned[Vision] = nil

    const Index = table.find(self.Visions, Vision)

    if Index then
        table.remove(self.Visions, Index)
    end

    if #self.Visions == 0 then
        Live[self] = nil
    end
end

function Scope:SpringValue(Info: TweenInfo, Vision: any, ValueName: string, TargetValue: any)
    const Targets = AsList(Vision)
    const Starts = {}
    const Slots = {}

    for _, Item in Targets do
        const Cap = Item[ValueName]

        if type(Cap) ~= "function" then
            error(`Vision has no value named "{ValueName}"`, 0)
        end

        Starts[Item] = Cap()
        table.insert(Slots, { Item, ValueName })
    end

    return self.Runtime:Create(Info, function(Alpha: number)
        for _, Item in Targets do
            Item[ValueName](Interpolate.Value(Starts[Item], TargetValue, Alpha))
        end
    end, Slots)
end

function Scope:SpringEvent(Info: TweenInfo, Vision: any, TargetEvents: { [string]: any })
    const Targets = AsList(Vision)
    const Tracks = {}
    const Slots = {}

    for _, Item in Targets do
        for Name, Goal in TargetEvents do
            const Cap = Item[Name]

            if type(Cap) ~= "function" then
                error(`Vision has no value named "{Name}"`, 0)
            end

            table.insert(Tracks, { Cap = Cap, Start = Cap(), Goal = Goal })
            table.insert(Slots, { Item, Name })
        end
    end

    return self.Runtime:Create(Info, function(Alpha: number)
        for _, Track in Tracks do
            Track.Cap(Interpolate.Value(Track.Start, Track.Goal, Alpha))
        end
    end, Slots)
end

function Scope:SpringStyle(Info: TweenInfo, Target: any, TargetFields: { [string]: any })
    const Sheets = AsSheets(self, Target)
    const Tracks = {}
    const Slots = {}

    for _, Book in Sheets do
        for Field, Goal in TargetFields do
            table.insert(Tracks, { Book = Book, Field = Field, Start = Start(Book, Field), Goal = Goal })
            table.insert(Slots, { Book, Field })
        end
    end

    return self.Runtime:Create(Info, function(Alpha: number)
        for _, Track in Tracks do
            Track.Book:Set(Track.Field, Interpolate.Value(Track.Start, Track.Goal, Alpha))
        end
    end, Slots)
end

function Scope:SpringInstance(Info: TweenInfo, Object: any, TargetProps: { [string]: any })
    const Targets = AsList(Object)
    const Starts = {}
    const Slots = {}

    for _, Item in Targets do
        const Values = {}

        for Key in TargetProps do
            Values[Key] = Item[Key]
            table.insert(Slots, { Item, Key })
        end

        Starts[Item] = Values
    end

    return self.Runtime:Create(Info, function(Alpha: number)
        for _, Item in Targets do
            const Values = Starts[Item]

            for Key, Goal in TargetProps do
                Item[Key] = Interpolate.Value(Values[Key], Goal, Alpha)
            end
        end
    end, Slots)
end

function Scope:SpringFunction(
    Info: TweenInfo,
    TargetFun: (any, number) -> (),
    InitialValue: any,
    TargetValue: any
)
    return self.Runtime:Create(Info, function(Alpha: number, DeltaTime: number)
        TargetFun(Interpolate.Value(InitialValue, TargetValue, Alpha), DeltaTime)
    end, { { TargetFun, "" } :: { any } })
end

const function Channel(Owner: any, Name: string, Current: any, Goal: any, Write: (any) -> ())
    local Kind = typeof(Current)

    if Kind ~= typeof(Goal) then
        error(`cannot solve {Kind} toward {typeof(Goal)}`, 0)
    end

    local Position = Interpolate.Components(Current)
    const Target = Interpolate.Components(Goal)

    if not Position or not Target then
        error(`{Kind} cannot be solved by a physics spring, use a tween instead`, 0)
    end

    local Velocity = table.create(#Position, 0)

    for Index = 1, #Position do
        Velocity[Index] = 0
    end

    return {
        Owner = Owner,
        Name = Name,
        Kind = Kind,
        Make = Interpolate.Maker(Kind),
        Position = Position,
        Velocity = Velocity,
        Goal = Target,
        Write = Write,
    }
end

function Scope:PhysicsValue(Period: number, Damping: number, Vision: any, ValueName: string, TargetValue: any)
    const Targets = AsList(Vision)
    const Channels = {}

    for _, Item in Targets do
        const Cap = Item[ValueName]

        if type(Cap) ~= "function" then
            error(`Vision has no value named "{ValueName}"`, 0)
        end

        table.insert(Channels, Channel(Item, ValueName, Cap(), TargetValue, Cap))
    end

    return self.Runtime:Solve(Period, Damping, Channels)
end

function Scope:PhysicsEvent(Period: number, Damping: number, Vision: any, TargetEvents: { [string]: any })
    const Targets = AsList(Vision)
    const Channels = {}

    for _, Item in Targets do
        for Name, Goal in TargetEvents do
            const Cap = Item[Name]

            if type(Cap) ~= "function" then
                error(`Vision has no value named "{Name}"`, 0)
            end

            table.insert(Channels, Channel(Item, Name, Cap(), Goal, Cap))
        end
    end

    return self.Runtime:Solve(Period, Damping, Channels)
end

function Scope:PhysicsStyle(Period: number, Damping: number, Target: any, TargetFields: { [string]: any })
    const Sheets = AsSheets(self, Target)
    const Channels = {}

    for _, Book in Sheets do
        for Field, Goal in TargetFields do
            table.insert(
                Channels,
                Channel(Book, Field, Start(Book, Field), Goal, function(Value)
                    Book:Set(Field, Value)
                end)
            )
        end
    end

    return self.Runtime:Solve(Period, Damping, Channels)
end

function Scope:PhysicsInstance(Period: number, Damping: number, Object: any, TargetProps: { [string]: any })
    const Targets = AsList(Object)
    const Channels = {}

    for _, Item in Targets do
        for Key, Goal in TargetProps do
            table.insert(
                Channels,
                Channel(Item, Key, Item[Key], Goal, function(Value)
                    Item[Key] = Value
                end)
            )
        end
    end

    return self.Runtime:Solve(Period, Damping, Channels)
end

function Scope:PhysicsFunction(
    Period: number,
    Damping: number,
    TargetFun: (any) -> (),
    InitialValue: any,
    TargetValue: any
)
    return self.Runtime:Solve(Period, Damping, {
        Channel(TargetFun, "", InitialValue, TargetValue, TargetFun),
    })
end

function Scope:Release()
    local Fault = nil

    for _, Vision in table.clone(self.Visions) :: { any } do
        const Ok, Err = pcall(Vision.Cleanup, Vision)

        if not Ok and Fault == nil then
            Fault = Err
        end
    end

    for _, Sheet in self.Styles do
        Sheet:Release()
    end

    table.clear(self.Visions)
    table.clear(self.Owned)

    Live[self] = nil
    table.clear(self.Styles)
    self.Runtime:Release()

    if Fault ~= nil then
        error(Fault, 0)
    end
end

return Scope
