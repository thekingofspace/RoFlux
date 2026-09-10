--!strict

const Sheet = require(script.Parent.Sheet)
const Types = require(script.Parent.Types)

type Store = Types.Dynamic
type Handle = Types.Linker

const Methods = {} :: Store

const Tuning: { [string]: string } = { Looped = "boolean", Speed = "number", Rate = "number" }

const Flipbook = {
    __index = function(self: any, Key: string): any
        if Key == "Finished" then
            const Link = rawget(self, "Link") :: any

            return Link == nil or Link.Finished
        end

        if Key == "Frame" then
            return rawget(self, "Last") or 0
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
            error(`a flipbook's {Key} must be a {Want}`, 0)
        end

        if Key == "Speed" and Value < 0 then
            error("a flipbook's Speed cannot be negative", 0)
        end

        if Key == "Rate" and Value <= 0 then
            error("a flipbook's Rate must be above zero", 0)
        end

        const Saved = rawget(self, "Saved") :: Store

        Saved[Key] = Value

        const Link = rawget(self, "Link") :: any

        if Link and not Link.Finished then
            Link[Key] = Value
        end
    end,
}

function Flipbook.new(Scope: any, Page: any, Object: Instance, Frames: { string }, Rate: number?)
    if not Sheet.Is(Page) then
        error("a flipbook needs a sheet to read its sprites from", 0)
    end

    if typeof(Object) ~= "Instance" then
        error("a flipbook needs an instance to play on", 0)
    end

    if type(Frames) ~= "table" or #Frames == 0 then
        error("a flipbook needs at least one frame", 0)
    end

    const Order = table.clone(Frames)

    for Index, Name in Order do
        if type(Name) ~= "string" then
            error(`frame {Index} of the flipbook must be a sprite name`, 0)
        end

        if not Page:Has(Name) then
            error(`the sheet has no sprite named "{Name}", asked for by frame {Index}`, 0)
        end
    end

    const Beat = Rate or 12

    if type(Beat) ~= "number" or Beat <= 0 then
        error("a flipbook's rate must be above zero", 0)
    end

    const Self = setmetatable({}, Flipbook) :: any

    rawset(Self, "Saved", { Looped = false, Speed = 1, Rate = Beat })
    rawset(Self, "Scope", Scope)
    rawset(Self, "Page", Page)
    rawset(Self, "Object", Object)
    rawset(Self, "Order", Order)
    rawset(Self, "Link", nil)
    rawset(Self, "Last", 0)

    return Self
end

function Methods:Play()
    self:Stop()

    const Saved = rawget(self, "Saved") :: Store
    const Page = rawget(self, "Page") :: any
    const Object = rawget(self, "Object") :: Instance
    const Order = rawget(self, "Order") :: { string }

    if not Page then
        return self
    end

    const Show = function(Index: number)
        rawset(self, "Last", Index)
        Page:Apply(Object, Order[Index])
    end

    const Link = (rawget(self, "Scope") :: any).Runtime:Flip(Object, #Order, Saved.Rate, Show)

    Link.Speed = Saved.Speed
    Link.Looped = Saved.Looped

    rawset(self, "Link", Link)

    return self
end

function Methods:Stop()
    const Link = rawget(self, "Link") :: Handle?

    if Link then
        Link:Cancel()
    end

    rawset(self, "Link", nil)

    return self
end

function Methods:Await()
    const Link = rawget(self, "Link") :: Handle?

    if Link and not Link.Finished then
        Link:Await()
    end
end

function Methods:Destroy()
    self:Stop()

    rawset(self, "Scope", nil)
    rawset(self, "Page", nil)
    rawset(self, "Object", nil)
    rawset(self, "Order", nil)
end

return Flipbook
