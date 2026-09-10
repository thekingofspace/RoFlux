--!strict

const Symbols = require(script.Parent.Symbols)
const Types = require(script.Parent.Types)
const Classes = require(script.Parent.Classes)

type Dynamic = Types.Dynamic

const Reserved = {
    ClassName = true,
    attributes = true,
    Attributes = true,
    tags = true,
    Tags = true,
    AttributeChanged = true,
    PropertyChanged = true,
}

const function Create(Declaration: any): Instance
    const ClassName = Declaration.ClassName

    if type(ClassName) ~= "string" then
        error("Declaration requires a ClassName", 0)
    end

    const Custom = Classes.Find(ClassName)
    const Made = if Custom then Classes.Made(Custom, Declaration) else nil
    const Object = Instance.new(if Custom then Custom.Base else ClassName)
    const Fields = (Object :: any) :: Dynamic

    for Key, Value in Declaration do
        if type(Key) ~= "string" or Reserved[Key] then
            continue
        end

        if Custom and Custom.Names[Key] then
            continue
        end

        if Symbols.Styled(Value) then
            error(`create cannot resolve the style token on "{Key}", styles need a scope`, 0)
        end

        if Symbols.Bound(Value) then
            error(`create cannot follow the value on "{Key}", fromEvent needs a vision`, 0)
        end

        const Member = Fields[Key]

        if typeof(Member) == "RBXScriptSignal" then
            Member:Connect(function(...)
                Value(Object, nil, ...)
            end)
        else
            Fields[Key] = Value
        end
    end

    const Attributes = Declaration.attributes or Declaration.Attributes

    if Attributes then
        for Key, Value in Attributes do
            Object:SetAttribute(Key, Value)
        end
    end

    const Tags = Declaration.tags or Declaration.Tags

    if Tags then
        for Key, Value in Tags do
            if type(Key) == "number" then
                Object:AddTag(Value)
            elseif Value then
                Object:AddTag(Key)
            end
        end
    end

    if Declaration.AttributeChanged then
        for Key, Callback in Declaration.AttributeChanged do
            Object:GetAttributeChangedSignal(Key):Connect(function()
                Callback(Object, nil, Object:GetAttribute(Key))
            end)
        end
    end

    if Declaration.PropertyChanged then
        for Key, Callback in Declaration.PropertyChanged do
            Object:GetPropertyChangedSignal(Key):Connect(function()
                Callback(Object, nil, Fields[Key])
            end)
        end
    end

    if Custom then
        for _, Inner in Classes.Build(Custom, Made) do
            const Child = Create(Inner)

            if Child.Parent == nil then
                Child.Parent = Object
            end
        end
    end

    for _, Entry in ipairs(Declaration) do
        if Symbols.Is(Entry) then
            if Entry.Kind == "Mount" and typeof(Entry.Target) == "Instance" then
                Object.Parent = Entry.Target
            end

            continue
        end

        if type(Entry) == "table" then
            const Child = Create(Entry)

            if Child.Parent == nil then
                Child.Parent = Object
            end
        end
    end

    return Object
end

return Create
