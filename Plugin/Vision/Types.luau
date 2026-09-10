--!strict

export type CapFunc<v> = (i:v?) -> v

export type Vision = {
    Cleanup:(self:Vision) -> (),
    Mount:(self:Vision) -> (),
    Open:(self:Vision) -> Instance,
    MountAsync:(self:Vision, Budget:number?) -> (),
    Clone:(self:Vision) -> Vision,
    [string]:CapFunc<any>
}

export type Marker = {
    Kind:string,
    Name:string?,
    Initial:any,
    Callback:any,
    Target:(Instance | string)?
}

export type Dynamic = {[string]:any}

export type Declaration = {[any]:any}

export type AttributeChanged = {[string]:(self:Instance, vision:Vision, Value:any) -> ()}
export type PropertyChanged = {[string]:(self:Instance, vision:Vision, Value:any) -> ()}

export type Graft = {Hosts:{Vision}}

export type Style = {
    Name:string,
    Get:(self:Style, Field:string) -> any,
    Set:(self:Style, Field:string, Value:any) -> ()
}

export type event = (Event:string, InitialValue:any, Callback:(self:Instance, vision:Vision, Value:any) -> ()) -> Marker
export type merge = (Event:string, Callback:(self:Instance, vision:Vision, Value:any) -> ()) -> Marker
export type derive = (Event:string, Compute:(Mode:string, Read:(Event:string) -> any, Write:(Event:string, Value:any) -> any, Value:any) -> any) -> Marker
export type ready = (Callback:(self:Instance, vision:Vision, cleanup:(Callback:(self:Instance, vision:Vision) -> ()) -> ()) -> ()) -> Marker
export type cleanup = (Callback:(self:Instance, vision:Vision) -> ()) -> Marker
export type drawcall = (Callback:(self:Instance, vision:Vision, Viewport:Vector2) -> ()) -> Marker
export type mount = (Target:Instance | string | Graft) -> Marker
export type fromClone = (Template:Instance) -> Marker
export type fromInstance = (Existing:Instance) -> Marker
export type receive = (Callback:(self:Instance, vision:Vision, Target:Instance, Source:Vision) -> Instance?) -> Marker
export type inject = (...Vision) -> Graft
export type lint = (Declaration:Declaration) -> {string}
export type create = (Declaration:Declaration) -> Instance
export type style = (Name:string) -> {[string]:any}
export type fromEvent = (Event:string, InitialValue:any?) -> any

export type Class = {
    Base:string,
    Properties:{[string]:any},
    Construct:(Made:{[string]:any}) -> Declaration,
    Changed:{[string]:(self:Instance, vision:Vision, Value:any) -> ()}?
}

export type class = (Name:string, Definition:Class) -> string

export type Keyframe = {
    Easing:TweenInfo | {Period:number?, Damping:number?, Dampening:number?},
    Time:number,
    Properties:{[string]:any},
    Events:{[string]:{any}}?
}

export type Bond = {Disconnect:(self:Bond) -> ()}

export type Sheet = {
    Has:(self:Sheet, Name:string) -> boolean,
    Frames:(self:Sheet) -> {string},
    Apply:(self:Sheet, Object:Instance, Name:string) -> Instance
}

export type FlipBook = {
    Play:(self:FlipBook) -> FlipBook,
    Stop:(self:FlipBook) -> FlipBook,
    Await:(self:FlipBook) -> (),
    Destroy:(self:FlipBook) -> (),
    Looped:boolean,
    Speed:number,
    Rate:number,
    Frame:number,
    Finished:boolean
}

export type Animation = {
    Bind:(self:Animation, Name:string, Callback:(self:Instance, ...any) -> ()) -> Bond,
    Play:(self:Animation) -> Animation,
    Jump:(self:Animation, Time:number) -> Animation,
    Await:(self:Animation) -> (),
    Stop:(self:Animation) -> (),
    Destroy:(self:Animation) -> (),
    Looped:boolean,
    SmoothLoop:boolean,
    RestageTime:number,
    Speed:number,
    Time:number,
    Length:number,
    Finished:boolean
}

export type keyframe = (Easing:any, Time:number, Properties:{[string]:any}, Events:{[string]:{any}}?) -> Keyframe

export type Linker = {
    Cancel:(self:Linker) -> (),
    Await:(self:Linker) -> (),
    Finished:boolean
}

export type Scope = {
    Capture:(Self:Scope, Declaration:Declaration) -> Vision,
    LoadStyle:(self:Scope, Declaration:Declaration) -> Style,
    
    ---@deprecaited
    SpringValue:(self:Scope, TweenInfo:TweenInfo, Vision:Vision | {Vision}, ValueName:string, TargetValue:any) -> Linker,
    ---@deprecaited
    PhysicsValue:(self:Scope, Period:number, Damping:number, Vision:Vision | {Vision}, ValueName:string, TargetValue:any) -> Linker,

    SpringEvent:(self:Scope, TweenInfo:TweenInfo, Vision:Vision | {Vision}, TargetEvents:{[string]:any}) -> Linker,
    SpringStyle:(self:Scope, TweenInfo:TweenInfo, Style:Style | string | {Style | string}, TargetFields:{[string]:any}) -> Linker,
    SpringInstance:(self:Scope, TweenInfo:TweenInfo, Instance:Instance | {Instance}, TargetProps:{[string]:any}) -> Linker,
    SpringFunction:(self:Scope, TweenInfo:TweenInfo, TargetFun:(NewValue:any, dt:number) -> (), InitialValue:any, TargetValue:any) -> Linker,

    PhysicsEvent:(self:Scope, Period:number, Damping:number, Vision:Vision | {Vision}, TargetEvents:{[string]:any}) -> Linker,
    PhysicsStyle:(self:Scope, Period:number, Damping:number, Style:Style | string | {Style | string}, TargetFields:{[string]:any}) -> Linker,
    PhysicsInstance:(self:Scope, Period:number, Damping:number, Instance:Instance | {Instance}, TargetProps:{[string]:any}) -> Linker,
    PhysicsFunction:(self:Scope, Period:number, Damping:number, TargetFun:(NewValue:any) -> (), InitialValue:any, TargetValue:any) -> Linker,

    Animate:(self:Scope, Keyframes:{Keyframe}, Target:Instance | Vision) -> Animation,
    FlipBook:(self:Scope, Sheet:Sheet, Instance:Instance, Frames:{string}, Rate:number?) -> FlipBook,
    Update:(self:Scope, EventName:string, Value:any) -> (),
    Release:(self:Scope) -> ()
}

return nil
