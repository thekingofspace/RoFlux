--!strict

const RunService = game:GetService("RunService")

const Interpolate = require(script.Parent.Interpolate)

export type Link = {
    Runtime: any,
    Update: (Link, number) -> boolean,
    Elapsed: number,
    Cycle: number,
    Finished: boolean,
    Claims: any,
    Threads: any,
    Watchers: any,

    Apply: any,
    Channels: any,
    Fire: any,
    Info: any,
    Marks: any,
    Object: any,
    Owner: any,
    Peek: any,
    Put: any,
    Show: any,
    Staged: number,
    Tracks: any,

    Count: number,
    Cursor: number,
    Damping: number,
    Index: number,
    Length: number,
    Omega: number,
    Rate: number,
    RestageTime: number,
    Speed: number,

    Looped: boolean,
    Primed: boolean,
    Restaging: boolean,
    SmoothLoop: boolean,

    Seek: (Link, number) -> (),
    Step: (Link, number) -> (),
    Cancel: (Link) -> (),
    Await: (Link) -> (),
}

export type Slots = { [string]: Link }

export type Runtime = {
    Links: { Link },
    Buffer: { Link },
    Claims: { [any]: Slots },
    Connection: RBXScriptConnection?,

    Claim: (Runtime, any, string, Link) -> (),
    Unclaim: (Runtime, any, string, Link) -> (),
    CancelOwner: (Runtime, any) -> (),
    Add: (Runtime, Link) -> (),
    Remove: (Runtime, Link) -> (),
    Start: (Runtime) -> (),
    Stop: (Runtime) -> (),
    Step: (Runtime, number) -> (),
    Release: (Runtime) -> (),
    Create: (Runtime, TweenInfo, (number, number) -> (), { { any } }) -> Link,
    Velocity: (Runtime, any, string) -> { number }?,
    Flip: (Runtime, Instance, number, number, (number) -> ()) -> Link,
    Play: (Runtime, any, (string) -> any, (string, any) -> (), { any }, { any }, number, (string, { any }) -> (), number?) -> Link,
    Solve: (Runtime, number, number, { any }) -> Link,
}

const Link = {}
Link.__index = Link

local Runtime = {}
Runtime.__index = Runtime

const Fading = { __mode = "v" }

const Epsilon = 0.0005
const Critical = 1e-4

const function Coefficients(Omega: number, Damping: number, DeltaTime: number)
    const Decay = Damping * Omega

    if Damping < 1 - Critical then
        const Ring = Omega * math.sqrt(1 - Damping * Damping)
        const Fade = math.exp(-Decay * DeltaTime)
        const Cos = math.cos(Ring * DeltaTime)
        const Sin = math.sin(Ring * DeltaTime) / Ring

        return Fade * (Cos + Decay * Sin), Fade * Sin, -Fade * Omega * Omega * Sin, Fade * (Cos - Decay * Sin)
    end

    if Damping <= 1 + Critical then
        const Fade = math.exp(-Omega * DeltaTime)
        const Span = Fade * DeltaTime

        return Fade + Omega * Span, Span, -Omega * Omega * Span, Fade - Omega * Span
    end

    const Root = Omega * math.sqrt(Damping * Damping - 1)
    const Fast = math.exp((Root - Decay) * DeltaTime)
    const Slow = math.exp((-Root - Decay) * DeltaTime)
    const Cosh = (Fast + Slow) * 0.5
    const Sinh = (Fast - Slow) * 0.5 / Root

    return Cosh + Decay * Sinh, Sinh, -Omega * Omega * Sinh, Cosh - Decay * Sinh
end

const function Springs(Easing: any): boolean
    return type(Easing) == "table"
        and typeof(Easing) ~= "TweenInfo"
        and (Easing.Damping ~= nil or Easing.Dampening ~= nil or Easing.Period ~= nil)
end

const function Solve(Track: any, Put: (string, any) -> (), DeltaTime: number): boolean
    const Carry, Push, Pull, Keep = Coefficients(Track.Omega, Track.Damping, DeltaTime)
    const Position = Track.Position
    const Velocity = Track.Velocity
    const Goal = Track.Goal
    const Count = #Position

    local Done = true

    for Index = 1, Count do
        const Offset = Position[Index] - Goal[Index]
        const Speed = Velocity[Index]

        Position[Index] = Goal[Index] + Carry * Offset + Push * Speed
        Velocity[Index] = Pull * Offset + Keep * Speed

        const Scale = math.max(1, math.abs(Goal[Index]))

        if
            math.abs(Position[Index] - Goal[Index]) > Epsilon * Scale
            or math.abs(Velocity[Index]) > Epsilon * Scale
        then
            Done = false
        end
    end

    if Done then
        for Index = 1, Count do
            Position[Index] = Goal[Index]
            Velocity[Index] = 0
        end
    end

    Put(Track.Property, Track.Make(Position))

    return Done
end

const function Enter(Track: any, Peek: (string) -> any, Head: any, Tail: any)
    Track.From = if Track.Springy then Peek(Track.Property) else Head.Value

    const Easing = Tail.Easing

    if not Springs(Easing) then
        Track.Springy = false

        return
    end

    const Span = Tail.Time - Head.Time
    const Period = Easing.Period or (if Span > 0 then Span else 0.5)

    Track.Springy = true
    Track.Omega = 2 * math.pi / math.max(Period, 1e-4)
    Track.Damping = math.max(Easing.Damping or Easing.Dampening or 0, 0)

    const Start = Interpolate.Components(Track.From)
    const Goal = Interpolate.Components(Tail.Value)

    if not Start or not Goal then
        error(`{Track.Property} cannot be solved by a physics keyframe, use a TweenInfo instead`, 0)
    end

    if Track.Position then
        for Index = 1, math.min(#Track.Position, #Goal) do
            Track.Goal[Index] = Goal[Index]
        end
    else
        Track.Position = Start
        Track.Velocity = table.create(#Start, 0)
        Track.Goal = Goal
        Track.Make = Interpolate.Maker(typeof(Track.From))
    end
end

const function Blank(Tracks: { any })
    for _, Track in Tracks do
        Track.Index = 0
        Track.From = nil
        Track.Home = nil
        Track.Curve = nil
        Track.Blend = nil
        Track.Springy = false
        Track.Position = nil
        Track.Velocity = nil
        Track.Goal = nil
    end
end

const function Rewind(Self: Link)
    Self.Elapsed = if Self.Length > 0 then Self.Elapsed % Self.Length else 0
    Self.Cursor = 1

    Blank(Self.Tracks)
end

const function Restage(Self: Link)
    const Peek = Self.Peek
    const Span = math.max(Self.RestageTime, 1e-4)

    Self.Elapsed = 0
    Self.Cursor = 1
    Self.Restaging = true
    Self.Staged = 0

    for _, Track in Self.Tracks do
        const Stops = Track.Stops
        const Home = Stops[1].Value
        const Style = Stops[#Stops].Easing

        Track.Index = 0
        Track.From = nil
        Track.Home = Home
        Track.Curve = Style

        Enter(Track, Peek, { Time = 0, Value = Peek(Track.Property) }, { Time = Span, Value = Home, Easing = Style })
    end
end

const function Timeline(Self: Link, DeltaTime: number): boolean
    const Tick = DeltaTime * Self.Speed

    if Self.Restaging then
        Self.Staged += Tick

        const Span = Self.RestageTime
        const Raw = if Span > 0 then math.min(Self.Staged / Span, 1) else 1
        const Put = Self.Put

        local Ready = Raw >= 1

        for _, Track in Self.Tracks do
            if Track.Springy then
                if not Solve(Track, Put, DeltaTime) then
                    Ready = false
                end
            else
                const Shape = Track.Curve
                const Curve = if Shape and typeof(Shape) == "TweenInfo" then Interpolate.Curve(Shape, Raw) else Raw

                Put(Track.Property, Interpolate.Value(Track.From, Track.Home, Curve))
            end
        end

        if Ready then
            Self.Restaging = false

            for _, Track in Self.Tracks do
                Track.From = nil
                Track.Home = nil
                Track.Curve = nil
            end
        end

        return false
    end

    Self.Elapsed += Tick

    if Self.Looped and Self.Length > 0 and Self.Elapsed >= Self.Length then
        if Self.SmoothLoop and Self.RestageTime > 0 then
            Restage(Self)

            return false
        end

        Rewind(Self)
    end

    const Now = Self.Elapsed
    const Peek = Self.Peek
    const Put = Self.Put
    const Marks = Self.Marks
    const Total = #Marks

    const Fresh = not Self.Primed

    Self.Primed = true

    if not Fresh then
        local Cursor = Self.Cursor

        while Cursor <= Total and Marks[Cursor].Time <= Now do
            const Mark = Marks[Cursor]

            Cursor += 1
            Self.Cursor = Cursor
            Self.Fire(Mark.Name, Mark.Args)
        end

        Self.Cursor = Cursor
    end

    local Resting = Now >= Self.Length

    for _, Track in Self.Tracks do
        const Stops = Track.Stops
        const Count = #Stops
        local Index = Track.Index

        while Index < Count and Now >= Stops[Index + 1].Time do
            Index += 1
            Track.Index = Index
            Track.From = nil
        end

        if Index == 0 then
            Resting = false

            continue
        end

        if Index >= Count then
            if Track.Springy then
                if not Solve(Track, Put, DeltaTime) then
                    Resting = false
                end
            elseif Track.From == nil then
                const Last = Stops[Count].Value

                Put(Track.Property, Last)
                Track.From = Last
            end

            continue
        end

        Resting = false

        const Head = Stops[Index]
        const Tail = Stops[Index + 1]

        if Track.From == nil then
            Enter(Track, Peek, Head, Tail)
        end

        if Track.Springy then
            Solve(Track, Put, DeltaTime)

            continue
        end

        const Span = Tail.Time - Head.Time
        const Alpha = if Span > 0 then (Now - Head.Time) / Span else 1
        const Curve = if Tail.Easing then Interpolate.Curve(Tail.Easing, Alpha) else math.clamp(Alpha, 0, 1)

        Put(Track.Property, Interpolate.Value(Track.From, Tail.Value, Curve))
    end

    return Resting and not Fresh
end

const function Flip(Self: Link, DeltaTime: number): boolean
    Self.Elapsed += DeltaTime * Self.Speed

    const Count = Self.Count
    const Span = 1 / Self.Rate

    local Index = math.floor(Self.Elapsed / Span) + 1
    local Done = false

    if Index > Count then
        if Self.Looped then
            Index = (Index - 1) % Count + 1
        else
            Index = Count
            Done = true
        end
    end

    if Index ~= Self.Index then
        Self.Index = Index
        Self.Show(Index)
    end

    return Done
end

const function Tween(Self: Link, DeltaTime: number): boolean
    Self.Elapsed += DeltaTime

    const Info = Self.Info
    const Alpha, Ended = Interpolate.Cycle(Info, Self.Elapsed)

    Self.Apply(Alpha, DeltaTime)

    if not Ended then
        return false
    end

    const Repeats = Info.RepeatCount

    if Repeats >= 0 and Self.Cycle >= Repeats then
        return true
    end

    Self.Cycle += 1
    Self.Elapsed = 0

    return false
end

const function Physics(Self: Link, DeltaTime: number): boolean
    const Carry, Push, Pull, Keep = Coefficients(Self.Omega, Self.Damping, DeltaTime)
    local Settled = true

    for _, Channel in Self.Channels do
        const Position = Channel.Position
        const Velocity = Channel.Velocity
        const Goal = Channel.Goal
        const Count = #Position

        for Index = 1, Count do
            const Offset = Position[Index] - Goal[Index]
            const Speed = Velocity[Index]

            Position[Index] = Goal[Index] + Carry * Offset + Push * Speed
            Velocity[Index] = Pull * Offset + Keep * Speed
        end

        local Done = true

        for Index = 1, Count do
            const Scale = math.max(1, math.abs(Goal[Index]))

            if
                math.abs(Position[Index] - Goal[Index]) > Epsilon * Scale
                or math.abs(Velocity[Index]) > Epsilon * Scale
            then
                Done = false
                break
            end
        end

        if Done then
            for Index = 1, Count do
                Position[Index] = Goal[Index]
                Velocity[Index] = 0
            end
        else
            Settled = false
        end

        Channel.Write(Channel.Make(Position))
    end

    return Settled
end

function Link.new(Owner: any, Update: any): Link
    return (setmetatable({
        Runtime = Owner,
        Update = Update,
        Elapsed = 0,
        Cycle = 0,
        Finished = false,
        Claims = {},
        Threads = {},
        Watchers = {},
    }, Link) :: any) :: Link
end

function Link.Seek(self: Link, Time: number)
    if self.Finished or not self.Tracks then
        return
    end

    const Now = math.clamp(Time, 0, self.Length)
    const Marks = self.Marks
    const Total = #Marks

    self.Elapsed = Now
    self.Restaging = false
    self.Staged = 0

    local Cursor = 1

    while Cursor <= Total and Marks[Cursor].Time <= Now do
        Cursor += 1
    end

    self.Cursor = Cursor

    Blank(self.Tracks)

    Timeline(self, 0)
end

function Link.Step(self: Link, DeltaTime: number)
    if self.Finished then
        return
    end

    if self.Update(self, DeltaTime) then
        self:Cancel()
    end
end

function Link.Cancel(self: Link)
    if self.Finished then
        return
    end

    self.Finished = true

    const Owner = self.Runtime

    for _, Watcher in self.Watchers do
        Watcher:Disconnect()
    end

    table.clear(self.Watchers)

    for _, Claim in self.Claims do
        const Held = Claim[1][1]

        if Held ~= nil then
            Owner:Unclaim(Held, Claim[2], self)
        end
    end

    Owner:Remove(self)

    local Threads = self.Threads

    self.Apply = nil
    self.Tracks = nil
    self.Marks = nil
    self.Fire = nil
    self.Show = nil
    self.Peek = nil
    self.Put = nil
    self.Owner = nil
    self.Object = nil
    self.Claims = nil
    self.Threads = nil
    self.Runtime = nil
    self.Info = nil
    self.Channels = nil
    self.Watchers = nil

    for _, Thread in Threads do
        task.spawn(Thread)
    end
end

function Link.Await(self: Link)
    if self.Finished then
        return
    end

    table.insert(self.Threads, coroutine.running())
    coroutine.yield()
end

function Runtime.new(): Runtime
    return (setmetatable({
        Links = {},
        Buffer = {},
        Claims = setmetatable({}, { __mode = "k" }),
        Connection = nil,
    }, Runtime) :: any) :: Runtime
end

function Runtime.Claim(self: Runtime, Owner: any, Name: string, Target: Link)
    local Slots = self.Claims[Owner]

    if not Slots then
        Slots = {}
        self.Claims[Owner] = Slots
    end

    const Existing = Slots[Name]

    if Existing and Existing ~= Target then
        Existing:Cancel()
        Slots = self.Claims[Owner]

        if not Slots then
            Slots = {}
            self.Claims[Owner] = Slots
        end
    end

    Slots[Name] = Target
    table.insert(Target.Claims, { setmetatable({ Owner }, Fading) :: any, Name })
end

function Runtime.Unclaim(self: Runtime, Owner: any, Name: string, Target: Link)
    local Slots = self.Claims[Owner]

    if not Slots then
        return
    end

    if Slots[Name] == Target then
        Slots[Name] = nil
    end

    if next(Slots) == nil then
        self.Claims[Owner] = nil
    end
end

function Runtime.CancelOwner(self: Runtime, Owner: any)
    local Slots = self.Claims[Owner]

    if not Slots then
        return
    end

    const Doomed = {}

    for _, Target in Slots do
        table.insert(Doomed, Target)
    end

    for _, Target in Doomed do
        Target:Cancel()
    end
end

function Runtime.Add(self: Runtime, Target)
    table.insert(self.Links, Target)
    self:Start()
end

function Runtime.Remove(self: Runtime, Target)
    const Index = table.find(self.Links, Target)

    if Index then
        table.remove(self.Links, Index)
    end

    if #self.Links == 0 then
        self:Stop()
    end
end

function Runtime.Start(self: Runtime)
    if self.Connection then
        return
    end

    const Signal = if RunService:IsClient() then RunService.RenderStepped else RunService.Heartbeat

    self.Connection = Signal:Connect(function(DeltaTime: number)
        self:Step(DeltaTime)
    end)
end

function Runtime.Stop(self: Runtime)
    if not self.Connection then
        return
    end

    self.Connection:Disconnect()
    self.Connection = nil
end

function Runtime.Step(self: Runtime, DeltaTime: number)
    const Links = self.Links
    const Count = #Links

    if Count == 0 then
        return
    end

    const Buffer = self.Buffer

    table.move(Links, 1, Count, 1, Buffer)

    local Fault = nil

    for Index = 1, Count do
        const Target = Buffer[Index]

        Buffer[Index] = nil

        if not Target.Finished then
            const Ok, Err = pcall(Target.Step :: any, Target, DeltaTime)

            if not Ok and Fault == nil then
                Fault = Err
            end
        end
    end

    if Fault ~= nil then
        error(Fault, 0)
    end
end

function Runtime.Release(self: Runtime)
    for _, Target in table.clone(self.Links) do
        Target:Cancel()
    end

    table.clear(self.Links)
    table.clear(self.Buffer)
    table.clear(self.Claims)
    self:Stop()
end

const function Guard(Target: Link, Owners: { unknown })
    const Seen: { [Instance]: boolean } = {}

    for _, Owner in Owners do
        if typeof(Owner) == "Instance" and not Seen[Owner] then
            Seen[Owner] = true

            table.insert(
                Target.Watchers,
                Owner.Destroying:Connect(function()
                    Target:Cancel()
                end)
            )
        end
    end
end

function Runtime.Create(self: Runtime, Info: TweenInfo, Apply: (number, number) -> (), Slots: { { any } })
    const Target = Link.new(self, Tween)

    Target.Info = Info
    Target.Apply = Apply

    const Owners = {}

    for _, Slot in Slots do
        self:Claim(Slot[1], Slot[2], Target)
        table.insert(Owners, Slot[1])
    end

    Guard(Target, Owners)

    const Primed, Fault = pcall(Target.Step :: any, Target, 0)

    if not Primed then
        Target:Cancel()

        error(Fault, 0)
    end

    if not Target.Finished then
        self:Add(Target)
    end

    return Target
end

function Runtime.Velocity(self: Runtime, Owner: any, Name: string): { number }?
    local Slots = self.Claims[Owner]

    if not Slots then
        return nil
    end

    const Existing = Slots[Name]

    if not Existing or not Existing.Channels then
        return nil
    end

    for _, Channel in Existing.Channels do
        if Channel.Owner == Owner and Channel.Name == Name then
            return Channel.Velocity
        end
    end

    return nil
end

function Runtime.Flip(self: Runtime, Object: Instance, Count: number, Rate: number, Show: (number) -> ())
    const Target = Link.new(self, Flip)

    Target.Object = Object
    Target.Count = Count
    Target.Rate = Rate
    Target.Show = Show
    Target.Index = 0
    Target.Speed = 1
    Target.Looped = false

    self:Claim(Object, "ImageRectOffset", Target)
    Guard(Target, { Object })

    const Primed, Fault = pcall(Target.Step :: any, Target, 0)

    if not Primed then
        Target:Cancel()

        error(Fault, 0)
    end

    if not Target.Finished then
        self:Add(Target)
    end

    return Target
end

function Runtime.Play(self: Runtime, Owner: any, Peek: (string) -> any, Put: (string, any) -> (), Tracks: { any }, Marks: { any }, Length: number, Fire: (string, { any }) -> (), Start: number?)
    const Target = Link.new(self, Timeline)

    Target.Owner = Owner
    Target.Peek = Peek
    Target.Put = Put
    Target.Elapsed = math.clamp(Start or 0, 0, Length)
    Target.Tracks = Tracks
    Target.Marks = Marks
    Target.Length = Length
    Target.Fire = Fire
    Target.Cursor = 1
    Target.Speed = 1
    Target.Looped = false
    Target.SmoothLoop = false
    Target.RestageTime = 0.25
    Target.Restaging = false
    Target.Staged = 0
    Target.Primed = false

    if #Tracks == 0 then
        self:Claim(Owner, "", Target)
    else
        for _, Track in Tracks do
            self:Claim(Owner, Track.Property, Target)
        end
    end

    Guard(Target, { Owner })
    Blank(Tracks)

    if Target.Elapsed > 0 then
        Target:Seek(Target.Elapsed)
    end

    const Primed, Fault = pcall(Target.Step :: any, Target, 0)

    if not Primed then
        Target:Cancel()

        error(Fault, 0)
    end

    if not Target.Finished then
        self:Add(Target)
    end

    return Target
end

function Runtime.Solve(self: Runtime, Period: number, Damping: number, Channels: { any })
    const Target = Link.new(self, Physics)

    Target.Omega = 2 * math.pi / math.max(Period, 1e-4)
    Target.Damping = math.max(Damping, 0)
    Target.Channels = Channels

    for _, Channel in Channels do
        const Carried = self:Velocity(Channel.Owner, Channel.Name)

        if Carried then
            for Index = 1, math.min(#Carried, #Channel.Velocity) do
                Channel.Velocity[Index] = Carried[Index]
            end
        end
    end

    const Owners = {}

    for _, Channel in Channels do
        self:Claim(Channel.Owner, Channel.Name, Target)
        table.insert(Owners, Channel.Owner)
    end

    Guard(Target, Owners)

    const Primed, Fault = pcall(Target.Step :: any, Target, 0)

    if not Primed then
        Target:Cancel()

        error(Fault, 0)
    end

    if not Target.Finished then
        self:Add(Target)
    end

    return Target
end

return Runtime
