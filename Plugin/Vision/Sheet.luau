--!strict

type Painted = ImageLabel

type Cell = { Offset: Vector2, Size: Vector2 }

type Entry = {
    [number]: string | Vector2,
    Name: string?,
    Offset: Vector2?,
    Position: Vector2?,
    Size: Vector2?,
}

const Sheet = {}

const Reserved = {
    Image = true,
    Size = true,
}

const function Cell(Name: string, Value: any, Default: Vector2?): Cell
    local Offset: Vector2?
    local Span: Vector2?

    if typeof(Value) == "Vector2" then
        Offset = Value
        Span = Default
    elseif type(Value) == "table" then
        Offset = Value[1] or Value.Offset or Value.Position
        Span = Value[2] or Value.Size or Default
    else
        error(`sprite "{Name}" needs a Vector2 position`, 0)
    end

    if typeof(Offset) ~= "Vector2" then
        error(`sprite "{Name}" needs a Vector2 position`, 0)
    end

    if typeof(Span) ~= "Vector2" then
        error(`sprite "{Name}" has no size, give it one or set Size on the sheet`, 0)
    end

    return { Offset = Offset, Size = Span }
end

Sheet.__index = Sheet

Sheet.__call = function(self, Object: Instance, Name: string)
    return self:Apply(Object, Name)
end

function Sheet.Is(Value: any): boolean
    return type(Value) == "table" and getmetatable(Value) == Sheet
end

function Sheet.new(Declaration: any)
    if type(Declaration) ~= "table" then
        error("a sheet needs a table of sprites", 0)
    end

    const Default = Declaration.Size

    if Default ~= nil and typeof(Default) ~= "Vector2" then
        error("a sheet's Size must be a Vector2", 0)
    end

    const Image = Declaration.Image

    if Image ~= nil and type(Image) ~= "string" then
        error("a sheet's Image must be a string", 0)
    end

    const Cells: { [string]: Cell } = {}
    const Names: { string } = {}

    for Index, Entry in ipairs(Declaration :: { Entry }) do
        if type(Entry) ~= "table" then
            error(`sprite {Index} must be a table of a name and a position`, 0)
        end

        const Name = Entry[1] or Entry.Name

        if type(Name) ~= "string" then
            error(`sprite {Index} needs a name`, 0)
        end

        Cells[Name] = Cell(Name, { Entry[2] or Entry.Offset or Entry.Position, Entry[3] or Entry.Size }, Default)
        table.insert(Names, Name)
    end

    for Key, Value in Declaration do
        if type(Key) ~= "string" or Reserved[Key] then
            continue
        end

        Cells[Key] = Cell(Key, Value, Default)
        table.insert(Names, Key)
    end

    if #Names == 0 then
        error("a sheet needs at least one sprite", 0)
    end

    table.sort(Names)

    return setmetatable({
        Image = Image,
        Cells = Cells,
        Names = Names,
    }, Sheet)
end

function Sheet:Has(Name: string): boolean
    return self.Cells[Name] ~= nil
end

function Sheet:Frames(): { string }
    return table.clone(self.Names)
end

function Sheet:Apply(Object: Instance, Name: string)
    const Spot = self.Cells[Name] :: Cell?

    if not Spot then
        error(`this sheet has no sprite named "{tostring(Name)}"`, 0)
    end

    const Target = Object :: Painted

    if self.Image and Target.Image ~= self.Image then
        Target.Image = self.Image
    end

    Target.ImageRectOffset = Spot.Offset
    Target.ImageRectSize = Spot.Size

    return Object
end

return Sheet
