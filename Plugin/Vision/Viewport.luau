--!strict

const Workspace = game:GetService("Workspace")

const Viewport = {}

type Watcher = (Vector2) -> ()

const Listeners: { [Watcher]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local Size = Vector2.zero
local Bound: RBXScriptConnection? = nil
local Watching: RBXScriptConnection? = nil

const function Measure(): Vector2
    const Camera = Workspace.CurrentCamera

    return if Camera then Camera.ViewportSize else Vector2.zero
end

local Rest

const function Publish()
    const Next = Measure()

    if Next == Size then
        return
    end

    Size = Next

    for Listener in Listeners do
        Listener(Size)
    end

    if next(Listeners) == nil then
        Rest()
    end
end

const function Bind()
    if Bound then
        Bound:Disconnect()
        Bound = nil
    end

    const Camera = Workspace.CurrentCamera

    if Camera then
        Bound = Camera:GetPropertyChangedSignal("ViewportSize"):Connect(Publish)
    end

    Publish()
end

function Rest()
    if Bound then
        Bound:Disconnect()
        Bound = nil
    end

    if Watching then
        Watching:Disconnect()
        Watching = nil
    end
end

function Viewport.Current(): Vector2
    if not Watching then
        Size = Measure()
    end

    return Size
end

function Viewport.Listen(Callback: (Vector2) -> ())
    Listeners[Callback] = true

    if not Watching then
        Watching = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(Bind)
        Size = Measure()
        Bind()
    end

    return {
        Disconnect = function()
            Listeners[Callback] = nil

            if next(Listeners) == nil then
                Rest()
            end
        end,
    }
end

return Viewport
