--!strict

const Symbols = require(script.Parent.Symbols)

const Types = require(script.Parent.Types)
const Classes = require(script.Parent.Classes)

const Token = Symbols.Token
const Viewport = require(script.Parent.Viewport)

const Capture = {}

export type Handler = (Instance, Types.Vision, any) -> ()

export type CleanupCall = (Instance, Types.Vision) -> ()

export type ReadyCall = (Instance, Types.Vision, (CleanupCall) -> ()) -> ()

export type ReceiveCall = (Instance, Types.Vision, Instance, Types.Vision) -> Instance?

export type DrawCall = (Instance, Types.Vision, Vector2) -> ()

export type Node = {
    Kind: string,
    Origin: string | Instance,
    Owned: boolean,
    Attributes: { [string]: any }?,
    AttributeChanged: Types.AttributeChanged?,
    PropertyChanged: Types.PropertyChanged?,
    Tags: { [any]: any }?,
    Fields: { any },
    Painted: { any }?,
    Children: { Node },
    Ready: { ReadyCall },
    Receive: { ReceiveCall },
    Draw: { DrawCall },
    Cleanup: { CleanupCall },
    Transient: { CleanupCall },
    Connections: { any },
    Pending: { any },
    Watched: { any }?,
    Parent: Node?,
    Target: any,
    Instance: any,
}

export type Binding = {
    Node: Node,
    Callback: Handler,
}

export type Event = {
    Name: string,
    Value: any,
    Declared: boolean,
    Bindings: { Binding },
    Targets: { Instance },
    Handlers: { Handler },
    Dependents: { [Event]: boolean },
    Sources: { [Event]: boolean },
    Compute: any,
    Firing: boolean,
    Pending: boolean,
    Running: boolean,
    Set: (any?) -> any,
    Write: (any?) -> any,
}

export type State = {
    Scope: any,
    Vision: any,
    Declaration: Types.Declaration,
    Events: { [string]: Event },
    Derived: { Event },
    Mounts: { [string]: Node },
    Nodes: { Node },
    Handle: { any },
    Root: Node,
    Mounted: boolean,
    Generation: number,
    Recompute: (Event) -> (),
}

const Held = {}

const Methods = {}

const Meta = { __index = Methods }

const Reserved = {
    ClassName = true,
    attributes = true,
    Attributes = true,
    tags = true,
    Tags = true,
    AttributeChanged = true,
    PropertyChanged = true,
    FromParent = true,
}

const Settling = 64

const Protected = {
    Mount = true,
    MountAsync = true,
    Open = true,
    Cleanup = true,
    Clone = true,
}

const function Register(State: State, Name: string): Event
    const Known = State.Events[Name]

    if Known then
        return Known
    end

    if Protected[Name] then
        error(`Vision event "{Name}" collides with a reserved method name`, 0)
    end

    const Event: Event = ({
        Name = Name,
        Value = nil,
        Declared = false,
        Bindings = {},
        Targets = {},
        Handlers = {},
        Dependents = {},
        Sources = {},
    } :: any) :: Event

    State.Events[Name] = Event

    const Targets = Event.Targets
    const Handlers = Event.Handlers
    const Dependents = Event.Dependents
    const Handle = State.Handle

    const Write = function(NewValue: any?): any
        if NewValue == nil then
            return Event.Value
        end

        if NewValue == Event.Value and (type(NewValue) ~= "table" or table.isfrozen(NewValue)) then
            return NewValue
        end

        Event.Value = NewValue

        if Event.Firing then
            Event.Pending = true

            return NewValue
        end

        Event.Firing = true

        const Ok, Err = pcall(function()
            local Rounds = 0

            repeat
                Rounds += 1

                if Rounds > Settling then
                    error(`Vision value "{Name}" kept changing while its handlers ran`, 0)
                end

                Event.Pending = false

                const Current = Event.Value

                for Index = 1, #Handlers do
                    const Handler = Handlers[Index]

                    if not Handler then
                        break
                    end

                    Handler(Targets[Index], Handle[1], Current)
                end
            until not Event.Pending
        end)

        Event.Firing = false

        if not Ok then
            error(Err, 0)
        end

        for Derived in Dependents do
            State.Recompute(Derived)
        end

        return NewValue
    end

    Event.Write = Write
    Event.Set = Write
    State.Vision[Name] = Write

    return Event
end

const Setters: { [string]: Handler } = {}

const function Setter(Key: string): Handler
    local Made = Setters[Key]

    if not Made then
        Made = function(Object: Instance, _, Value: any)
            if Value == nil then
                return
            end

            const Members = (Object :: any) :: Types.Dynamic

            Members[Key] = Value
        end

        Setters[Key] = Made
    end

    return Made
end

const function Parse(State: State, Declaration: any, Parent: Node?): Node
    local Kind = "Class"
    local Origin = Declaration.ClassName
    local Sources = 0

    const Borrowed = Declaration.FromParent

    if Borrowed ~= nil then
        if type(Borrowed) ~= "string" then
            error("FromParent needs the name of a child to take", 0)
        end

        if not Parent then
            error("FromParent needs a declaration around it to look inside", 0)
        end

        Kind = "Child"
        Origin = Borrowed
        Sources += 1
    end

    for _, Entry in ipairs(Declaration) do
        if Symbols.Is(Entry) then
            const What = Entry.Kind

            if What == "Clone" or What == "Adopt" then
                if typeof(Entry.Target) ~= "Instance" then
                    error(
                        `{if What == "Clone" then "fromClone" else "fromInstance"} needs an instance to take from`,
                        0
                    )
                end

                Kind = What
                Origin = Entry.Target
                Sources += 1
            end
        end
    end

    if Sources > 1 then
        error("a declaration can only take its instance from one place", 0)
    end

    if Sources == 0 and type(Origin) ~= "string" then
        error("Declaration requires a ClassName", 0)
    end

    const Custom = if Sources == 0 then Classes.Find(Origin) else nil
    local Made = nil

    if Custom then
        Made = Classes.Made(Custom, Declaration)
        Origin = Custom.Base
    end

    const Node = ({
        Kind = Kind,
        Origin = Origin,
        Owned = Kind == "Class" or Kind == "Clone",
        Attributes = Declaration.attributes or Declaration.Attributes,
        AttributeChanged = Declaration.AttributeChanged,
        PropertyChanged = Declaration.PropertyChanged,
        Tags = Declaration.tags or Declaration.Tags,
        Fields = nil,
        Painted = nil,
        Children = {},
        Ready = {},
        Receive = {},
        Draw = {},
        Cleanup = {},
        Transient = {},
        Connections = {},
        Pending = {},
        Watched = if Declaration.AttributeChanged or Declaration.PropertyChanged then {} else nil,
        Parent = Parent,
        Target = nil,
        Instance = nil,
    } :: any) :: Node

    table.insert(State.Nodes, Node)

    const Fields = {}
    const Name = Declaration.Name
    local Painted
    local Slot = 0

    for Key, Value in Declaration do
        if type(Key) ~= "string" or Reserved[Key] then
            continue
        end

        if Custom and Custom.Names[Key] then
            continue
        end

        if type(Value) == "table" and getmetatable(Value) == Token then
            if not Painted then
                Painted = {}
            end

            table.insert(Painted, Key)
            table.insert(Painted, Value)
        elseif Symbols.Bound(Value) then
            const Event = Register(State, Value.Name)

            if not Event.Declared and Value.Initial ~= nil then
                Event.Declared = true
                Event.Value = Value.Initial
            end

            table.insert(Event.Bindings, { Node = Node, Callback = Setter(Key) })
        else
            Fields[Slot + 1] = Key
            Fields[Slot + 2] = Value
            Slot += 2
        end
    end

    Node.Fields = Fields
    Node.Painted = Painted

    if type(Name) == "string" then
        State.Mounts[Name] = Node
    end

    if Custom then
        const Props = Made :: any

        for _, Entry in ipairs(Declaration) do
            if Symbols.Is(Entry) and Entry.Kind == "Event" then
                const Early = Register(State, Entry.Name)

                if not Early.Declared then
                    Early.Declared = true
                    Early.Value = Entry.Initial
                end
            end
        end

        for _, Pair in Classes.Bound(Custom, Declaration) do
            const Key = Pair[1]
            const Token = Pair[2]
            const Watch = Classes.Watch(Custom, Key)

            if not Watch then
                error(`class "{Custom.Name}" cannot follow a value on "{Key}", it does not watch that property`, 0)
            end

            const Event = Register(State, Token.Name)

            if not Event.Declared and Token.Initial ~= nil then
                Event.Declared = true
                Event.Value = Token.Initial
            end

            if Event.Value ~= nil then
                Props[Key] = Event.Value
            end

            table.insert(Event.Bindings, { Node = Node, Callback = Watch })
        end

        for _, Inner in Classes.Build(Custom, Props) do
            table.insert(Node.Children, Parse(State, Inner, Node))
        end
    end

    for _, Entry in ipairs(Declaration) do
        if Symbols.Is(Entry) then
            const What = Entry.Kind

            if What == "Event" then
                local Event = Register(State, Entry.Name)

                if not Event.Declared then
                    Event.Declared = true
                    Event.Value = Entry.Initial
                end

                table.insert(Event.Bindings, { Node = Node, Callback = Entry.Callback })
            elseif What == "Merge" then
                local Event = Register(State, Entry.Name)

                table.insert(Event.Bindings, { Node = Node, Callback = Entry.Callback })
            elseif What == "Derive" then
                local Event = Register(State, Entry.Name)

                if Event.Compute then
                    error(`Vision value "{Entry.Name}" is derived more than once`, 0)
                end

                Event.Compute = Entry.Callback
                table.insert(State.Derived, Event)
            elseif What == "Ready" then
                table.insert(Node.Ready, Entry.Callback)
            elseif What == "Receive" then
                table.insert(Node.Receive, Entry.Callback)
            elseif What == "Cleanup" then
                table.insert(Node.Cleanup, Entry.Callback)
            elseif What == "Draw" then
                table.insert(Node.Draw, Entry.Callback)
            elseif What == "Mount" then
                Node.Target = Entry.Target
            end
        elseif Symbols.Bound(Entry) then
            error(`fromEvent belongs on a property, not in the array part, as Property = fromEvent("{Entry.Name}")`, 0)
        elseif type(Entry) == "table" then
            table.insert(Node.Children, Parse(State, Entry, Node))
        end
    end

    return Node
end

const Wired: { [string]: { [string]: boolean } } = {}

const function Take(Node: Node): Instance
    const Kind = Node.Kind

    if Kind == "Class" then
        return Instance.new(Node.Origin :: string)
    end

    if Kind == "Clone" then
        return (Node.Origin :: Instance):Clone()
    end

    if Kind == "Adopt" then
        return Node.Origin :: Instance
    end

    const Host = if Node.Parent then Node.Parent.Instance else nil
    const Found = if Host then Host:FindFirstChild(Node.Origin) else nil

    if not Found then
        error(`FromParent found no child named "{Node.Origin}"`, 0)
    end

    return Found
end

const function Raise(State: State, Node: Node)
    const Object = Take(Node)
    const Members = (Object :: any) :: Types.Dynamic
    const ClassName = Object.ClassName

    Node.Instance = Object

    const Pending = Node.Pending
    const Fields = Node.Fields

    table.clear(Pending)

    local Known = Wired[ClassName]

    if not Known then
        Known = {}
        Wired[ClassName] = Known
    end

    local Slot = 0

    for Index = 1, #Fields, 2 do
        const Key = Fields[Index]
        const Value = Fields[Index + 1]

        local Signal = Known[Key]

        if Signal == nil then
            Signal = typeof(Members[Key]) == "RBXScriptSignal"
            Known[Key] = Signal
        end

        if Signal then
            Pending[Slot + 1] = Members[Key]
            Pending[Slot + 2] = Value
            Slot += 2
        else
            Members[Key] = Value
        end
    end

    const Painted = Node.Painted

    if Painted then
        const Sheets = State.Scope.Styles
        const Connections = Node.Connections

        for Index = 1, #Painted, 2 do
            const Key = Painted[Index]
            const Token = Painted[Index + 1]
            const Sheet = Sheets[Token.Style]

            if not Sheet then
                error(`style "{Token.Style}" is not loaded on this scope`, 0)
            end

            Members[Key] = Sheet:Get(Token.Field)
            Connections[#Connections + 1] = Sheet:Attach(Object, Key, Token.Field)
        end
    end

    if Node.Attributes then
        for Key, Value in Node.Attributes do
            Object:SetAttribute(Key, Value)
        end
    end

    if Node.Tags then
        for Key, Value in Node.Tags do
            if type(Key) == "number" then
                Object:AddTag(Value)
            elseif Value then
                Object:AddTag(Key)
            end
        end
    end

    const Watched = Node.Watched

    if not Watched then
        return
    end

    table.clear(Watched)

    local Seat = 0

    if Node.AttributeChanged then
        for Key, Callback in Node.AttributeChanged do
            Watched[Seat + 1] = Object:GetAttributeChangedSignal(Key)
            Watched[Seat + 2] = Callback
            Watched[Seat + 3] = Key
            Watched[Seat + 4] = true
            Seat += 4
        end
    end

    if Node.PropertyChanged then
        for Key, Callback in Node.PropertyChanged do
            Watched[Seat + 1] = Object:GetPropertyChangedSignal(Key)
            Watched[Seat + 2] = Callback
            Watched[Seat + 3] = Key
            Watched[Seat + 4] = false
            Seat += 4
        end
    end
end

const function Build(State: State)
    const Nodes = State.Nodes

    for Index = 1, #Nodes do
        Raise(State, Nodes[Index])
    end
end

const function Offer(Host: any, Pending: Instance, Source: any): Instance?
    const Other = if type(Host) == "table" then rawget(Host, Held) :: State? else nil

    if not Other or not Other.Mounted then
        return nil
    end

    for _, Node in Other.Nodes do
        const Object = Node.Instance

        if Object then
            for _, Callback in Node.Receive do
                const Taken = Callback(Object, Other.Handle[1], Pending, Source)

                if typeof(Taken) == "Instance" then
                    return Taken
                end
            end
        end
    end

    return nil
end

const function Graft(State: State, Node: Node, Target: any, Source: any): Instance?
    const Pending: Instance? = Node.Instance

    if not Pending then
        return nil
    end

    const Handle = State.Handle

    for _, Host in Target.Hosts do
        const Spot = Offer(Host, Pending, Source)

        if Spot then
            table.insert(
                Node.Connections,
                Pending.Destroying:Connect(function()
                    const Owner = Handle[1]

                    if Owner then
                        Owner:Cleanup()
                    end
                end)
            )

            return Spot
        end
    end

    return nil
end

const function Resolve(State: State, Node: Node, Source: any): Instance?
    local Target = Node.Target

    if typeof(Target) == "Instance" then
        return Target
    end

    if type(Target) == "string" then
        const Found = State.Mounts[Target]

        return if Found then Found.Instance else nil
    end

    if Symbols.Injected(Target) then
        return Graft(State, Node, Target, Source)
    end

    return if Node.Parent then Node.Parent.Instance else nil
end

const function Attach(State: State, Node: Node)
    for _, Child in Node.Children do
        Attach(State, Child)
    end

    const Object = Node.Instance
    const Pending = Node.Pending
    const Connections = Node.Connections
    const Handle = State.Handle

    for Index = 1, #Pending, 2 do
        const Callback = Pending[Index + 1]

        table.insert(
            Connections,
            (Pending[Index] :: RBXScriptSignal):Connect(function(...)
                Callback(Object, Handle[1], ...)
            end)
        )
    end

    table.clear(Pending)

    const Watched = Node.Watched

    if not Watched then
        return
    end

    for Index = 1, #Watched, 4 do
        const Callback = Watched[Index + 1]
        const Key = Watched[Index + 2]
        const Attribute = Watched[Index + 3]

        table.insert(
            Connections,
            (Watched[Index] :: RBXScriptSignal):Connect(function()
                Callback(Object, Handle[1], if Attribute then Object:GetAttribute(Key) else Object[Key])
            end)
        )
    end

    table.clear(Watched)
end

const function Paint(State: State, Node: Node, Size: Vector2)
    for _, Child in Node.Children do
        Paint(State, Child, Size)
    end

    const Owner = State.Handle[1]

    for _, Callback in Node.Draw do
        Callback(Node.Instance, Owner, Size)
    end
end

const function Observe(State: State, Node: Node)
    for _, Child in Node.Children do
        Observe(State, Child)
    end

    if #Node.Draw == 0 then
        return
    end

    const Object = Node.Instance
    const Draw = Node.Draw
    const Handle = State.Handle

    table.insert(
        Node.Connections,
        Viewport.Listen(function(Size: Vector2)
            const Owner = Handle[1]

            for _, Callback in Draw do
                Callback(Object, Owner, Size)
            end
        end)
    )
end

local function Ready(State: State, Node: Node)
    for _, Child in Node.Children do
        Ready(State, Child)
    end

    if #Node.Ready == 0 then
        return
    end

    const Later = function(Callback: (Instance, any) -> ())
        table.insert(Node.Transient, Callback)
    end

    const Owner = State.Handle[1]

    for _, Callback in Node.Ready do
        Callback(Node.Instance, Owner, Later)
    end
end

const function Recompute(State: State, Event: Event, Silent: boolean?)
    if Event.Running then
        error(`Vision value "{Event.Name}" depends on itself`, 0)
    end

    Event.Running = true

    for Source in Event.Sources do
        Source.Dependents[Event] = nil
    end

    table.clear(Event.Sources)

    const Read = function(Name: string): any
        const Source = State.Events[Name]

        if not Source then
            error(`Vision value "{Event.Name}" reads "{Name}", which is not declared`, 0)
        end

        if Source == Event then
            error(`Vision value "{Event.Name}" reads itself`, 0)
        end

        Event.Sources[Source] = true
        Source.Dependents[Event] = true

        return Source.Value
    end

    const Refuse = function(Name: string): any
        error(`Vision value "{Event.Name}" tried to write "{Name}" while computing`, 0)
    end

    local Ok, Result = pcall(Event.Compute, "get", Read, Refuse)

    if not Ok then
        Event.Running = false

        error(Result, 0)
    end

    local Wrote = true

    if Silent then
        Event.Value = Result
    else
        Wrote, Result = pcall(Event.Write, Result)
    end

    Event.Running = false

    if not Wrote then
        error(Result, 0)
    end

    return Result
end

const function Settle(State: State)
    local Derived = State.Derived

    if #Derived == 0 then
        return
    end

    for _ = 1, #Derived + 1 do
        local Changed = false

        for _, Event in Derived do
            const Before = Event.Value

            Recompute(State, Event, true)

            if Event.Value ~= Before then
                Changed = true
            end
        end

        if not Changed then
            return
        end
    end
end

const function Activate(State: State)
    for _, Event in State.Events do
        local Bindings = Event.Bindings
        local Targets = Event.Targets
        local Handlers = Event.Handlers

        table.clear(Targets)
        table.clear(Handlers)

        for Index = 1, #Bindings do
            const Binding = Bindings[Index]

            Targets[Index] = Binding.Node.Instance
            Handlers[Index] = Binding.Callback
        end
    end
end

const function Deactivate(State: State)
    for _, Event in State.Events do
        table.clear(Event.Targets)
        table.clear(Event.Handlers)
    end
end

const function Teardown(State: State, Node: Node)
    for _, Child in Node.Children do
        Teardown(State, Child)
    end

    if not Node.Instance then
        return
    end

    const Owner = State.Handle[1]

    local Fault = nil

    for Index = #Node.Transient, 1, -1 do
        const Ok, Err = pcall(Node.Transient[Index] :: any, Node.Instance, Owner)

        if not Ok and Fault == nil then
            Fault = Err
        end
    end

    table.clear(Node.Transient)

    for Index = #Node.Cleanup, 1, -1 do
        const Ok, Err = pcall(Node.Cleanup[Index] :: any, Node.Instance, Owner)

        if not Ok and Fault == nil then
            Fault = Err
        end
    end

    if Fault ~= nil then
        error(Fault, 0)
    end
end

const function Finish(State: State, Source: any, Mark: number)
    Activate(State)
    Settle(State)

    const Owner = State.Handle[1]

    for _, Event in State.Events do
        local Targets = Event.Targets
        local Handlers = Event.Handlers
        local Value = Event.Value

        for Index = 1, #Handlers do
            Handlers[Index](Targets[Index], Owner, Value)
        end
    end

    if State.Generation ~= Mark then
        return
    end

    Paint(State, State.Root, Viewport.Current())

    if State.Root.Owned or State.Root.Target ~= nil then
        State.Root.Instance.Parent = Resolve(State, State.Root, Source)
    end

    Ready(State, State.Root)

    if State.Generation ~= Mark then
        return
    end

    Attach(State, State.Root)
    Observe(State, State.Root)
end

function Methods:Mount()
    const State = rawget(self, Held) :: State

    if State.Mounted then
        const Root = State.Root.Instance

        if Root and Root.Parent == nil and Symbols.Injected(State.Root.Target) then
            Root.Parent = Resolve(State, State.Root, self)
        end

        return
    end

    State.Mounted = true
    State.Generation += 1
    State.Scope:Adopt(self)

    Build(State)

    for _, Node in State.Nodes do
        if Node ~= State.Root and (Node.Owned or Node.Target ~= nil) then
            Node.Instance.Parent = Resolve(State, Node, self)
        end
    end

    Finish(State, self, State.Generation)
end

function Methods:MountAsync(Budget: number?)
    const State = rawget(self, Held) :: State

    if State.Mounted then
        return
    end

    State.Mounted = true
    State.Generation += 1
    State.Scope:Adopt(self)

    const Mark = State.Generation
    const Slice = Budget or 0.002
    const Nodes = State.Nodes
    const Built: { Instance } = {}

    local Clock = os.clock()

    const function Spent(): boolean
        if os.clock() - Clock <= Slice then
            return false
        end

        task.wait()

        Clock = os.clock()

        if State.Generation ~= Mark then
            for _, Object in Built do
                Object:Destroy()
            end

            return true
        end

        return false
    end

    for Index = 1, #Nodes do
        Raise(State, Nodes[Index])

        if Nodes[Index].Owned then
            table.insert(Built, Nodes[Index].Instance)
        end

        if Spent() then
            return
        end
    end

    for Index = 1, #Nodes do
        const Node = Nodes[Index]

        if Node ~= State.Root and (Node.Owned or Node.Target ~= nil) then
            Node.Instance.Parent = Resolve(State, Node, self)
        end

        if Spent() then
            return
        end
    end

    Finish(State, self, Mark)
end

function Methods:Open(): Instance
    self:Mount()

    return (rawget(self, Held) :: State).Root.Instance
end

function Methods:Cleanup()
    const State = rawget(self, Held) :: State

    State.Scope:Forget(self)

    const Runtime = State.Scope.Runtime
    const Linked = next(Runtime.Claims) ~= nil

    if Linked then
        Runtime:CancelOwner(self)
    end

    if not State.Mounted then
        return
    end

    State.Mounted = false
    State.Generation += 1

    const Torn, Fault = pcall(Teardown :: any, State, State.Root)

    for _, Node in State.Nodes do
        for _, Connection in Node.Connections do
            Connection:Disconnect()
        end

        table.clear(Node.Connections)
        table.clear(Node.Pending)

        if Node.Watched then
            table.clear(Node.Watched)
        end

        if Linked and Node.Instance then
            Runtime:CancelOwner(Node.Instance)
        end
    end

    for _, Node in State.Nodes do
        if Node.Owned and Node.Instance then
            Node.Instance:Destroy()
        end
    end

    for _, Node in State.Nodes do
        Node.Instance = nil
    end

    Deactivate(State)

    if not Torn then
        error(Fault, 0)
    end
end

function Methods:Clone()
    const State = rawget(self, Held) :: State

    for _, Node in State.Nodes do
        if Node.Kind == "Adopt" then
            error(
                "this vision cannot be cloned, it takes an existing instance with fromInstance and there is only one of those, use fromClone instead",
                0
            )
        end
    end

    const Copy = State.Scope:Capture(State.Declaration)
    const Fresh = rawget(Copy, Held) :: State

    for Name, Event in State.Events do
        const Other = Fresh.Events[Name]

        if Other then
            Other.Value = Event.Value
        end
    end

    return Copy
end

function Capture.Is(Value: any): boolean
    return type(Value) == "table" and rawget(Value, Held) ~= nil
end

function Capture.new(Scope: any, Declaration: any)
    local Vision: Types.Vision = setmetatable({}, Meta) :: any

    const State: State = ({
        Scope = Scope,
        Vision = Vision,
        Declaration = Declaration,
        Events = {},
        Derived = {},
        Mounts = {},
        Nodes = {},
        Handle = setmetatable({}, { __mode = "v" }),
        Root = nil,
        Mounted = false,
        Generation = 0,
    } :: any) :: State

    State.Recompute = function(Event)
        Recompute(State, Event)
    end

    rawset(Vision :: any, Held, State)
    State.Handle[1] = Vision
    State.Root = Parse(State, Declaration, nil)

    for _, Event in State.Derived do
        const Compute = Event.Compute

        const Source = function(Name: string)
            const Found = State.Events[Name]

            if not Found then
                error(`Vision value "{Event.Name}" refers to "{Name}", which is not declared`, 0)
            end

            return Found
        end

        const Plain = function(Name: string): any
            return Source(Name).Value
        end

        const Push = function(Name: string, NewValue: any): any
            return Source(Name).Set(NewValue)
        end

        Event.Set = function(NewValue: any?): any
            if NewValue == nil then
                return Event.Value
            end

            Compute("set", Plain, Push, NewValue)

            return Event.Value
        end

        Vision[Event.Name] = Event.Set
    end

    State.Vision = nil

    return Vision
end

return Capture
