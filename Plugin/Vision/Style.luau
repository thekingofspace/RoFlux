--!strict

type Use = {
    Object: Instance,
    Property: string,
}

type Uses = { [Use]: boolean }

const Style = {}
Style.__index = Style

function Style.Is(Value: any): boolean
    return type(Value) == "table" and getmetatable(Value) == Style
end

function Style.new(Name: string)
    return setmetatable({
        Name = Name,
        Fields = {} :: { [string]: any },
        Users = {} :: { [string]: Uses },
    }, Style)
end

function Style:Get(Field: string): any
    return self.Fields[Field]
end

function Style:Set(Field: string, Value: any)
    if typeof(Value) == "table" then
        error(`style "{self.Name}" field "{Field}" cannot be a table`, 0)
    end

    if self.Fields[Field] == Value then
        return
    end

    self.Fields[Field] = Value

    const Bound: Uses = self.Users[Field]

    if not Bound then
        return
    end

    for Use in Bound do
        (Use.Object :: any)[Use.Property] = Value
    end
end

function Style:Load(Declaration: { [string]: any })
    for Field, Value in Declaration do
        if Field ~= "name" and Field ~= "Name" then
            self:Set(Field, Value)
        end
    end
end

function Style:Attach(Object: Instance, Property: string, Field: string)
    local Bound: Uses = self.Users[Field]

    if not Bound then
        Bound = setmetatable({}, { __mode = "k" }) :: any
        self.Users[Field] = Bound
    end

    const Use: Use = { Object = Object, Property = Property }

    Bound[Use] = true

    return {
        Disconnect = function()
            Bound[Use] = nil
        end,
    }
end

function Style:Release()
    table.clear(self.Users)
end

return Style
