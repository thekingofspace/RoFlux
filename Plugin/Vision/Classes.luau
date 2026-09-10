--!strict

const Symbols = require(script.Parent.Symbols)

const Classes = {}

const Registry: { [string]: any } = {}

const function Fold(Custom: any, Given: any)
    const Made = {}

    for Key, Default in Custom.Properties do
        const Value = if Given == nil then nil else Given[Key]

        if Value == nil or Symbols.Bound(Value) then
            Made[Key] = Default
        else
            Made[Key] = Value
        end
    end

    return Made
end

function Classes.new(Name: string, Definition: any)
    if type(Name) ~= "string" or Name == "" then
        error("a custom class needs a name", 0)
    end

    if Registry[Name] then
        error(`a custom class named "{Name}" is already registered`, 0)
    end

    if type(Definition) ~= "table" then
        error(`class "{Name}" needs a definition table`, 0)
    end

    const Base = Definition.Base or Definition.ClassName

    if type(Base) ~= "string" then
        error(`class "{Name}" needs a Base, the ClassName it is built on`, 0)
    end

    if Registry[Base] then
        error(`class "{Name}" cannot be built on "{Base}", a custom class cannot extend another`, 0)
    end

    if type(Definition.Construct) ~= "function" then
        error(`class "{Name}" needs a Construct that returns a declaration`, 0)
    end

    const Properties = Definition.Properties or {}

    if type(Properties) ~= "table" then
        error(`class "{Name}" needs its Properties to be a table of names to default values`, 0)
    end

    const Names = {}

    for Key, Default in Properties do
        if type(Key) ~= "string" then
            error(`class "{Name}" has a property that is not named`, 0)
        end

        if Default == nil then
            error(`class "{Name}" property "{Key}" needs a default value`, 0)
        end

        Names[Key] = true
    end

    const Changed = Definition.Changed or {}

    if type(Changed) ~= "table" then
        error(`class "{Name}" needs its Changed to be a table of property names to callbacks`, 0)
    end

    for Key, Call in Changed do
        if not Names[Key] then
            error(`class "{Name}" watches "{Key}", which is not one of its properties`, 0)
        end

        if type(Call) ~= "function" then
            error(`class "{Name}" needs a function to watch "{Key}"`, 0)
        end
    end

    Registry[Name] = {
        Name = Name,
        Base = Base,
        Properties = Properties,
        Names = Names,
        Construct = Definition.Construct,
        Changed = Changed,
    }

    return Name
end

function Classes.Find(Name: any): any
    if type(Name) ~= "string" then
        return nil
    end

    return Registry[Name]
end

function Classes.Made(Custom: any, Declaration: any)
    return Fold(Custom, Declaration)
end

function Classes.Bound(Custom: any, Given: any): { any }
    const Found = {}

    for Key in Custom.Names do
        const Value = Given[Key]

        if Symbols.Bound(Value) then
            table.insert(Found, { Key, Value })
        end
    end

    return Found
end

function Classes.Build(Custom: any, Made: any): { any }
    const Inner = Custom.Construct(Made)

    if type(Inner) ~= "table" then
        error(`class "{Custom.Name}" must construct a declaration`, 0)
    end

    if Inner.ClassName ~= nil or Inner.FromParent ~= nil then
        return { Inner }
    end

    const Parts = {}

    for _, Entry in ipairs(Inner) do
        if type(Entry) ~= "table" then
            error(`class "{Custom.Name}" constructed something that is not a declaration`, 0)
        end

        table.insert(Parts, Entry)
    end

    if #Parts == 0 then
        error(`class "{Custom.Name}" constructed nothing, return a declaration or a list of them`, 0)
    end

    return Parts
end

function Classes.Watch(Custom: any, Key: string): any
    return Custom.Changed[Key]
end

return Classes
