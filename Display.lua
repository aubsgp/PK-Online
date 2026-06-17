local Data = require("Data")
local ObjectOrientationDay = require("ObjectOrientationDay")
local Pos = ObjectOrientationDay.Pos

-- See https://github.com/pret/pokeplatinum/blob/main/include/camera.h
local Camera = {
    addr = 0,

    ANGLES_OFFSET = 0x00,
    POS_OFFSET = 0x14,
    TARGET_POS_OFFSET = 0x20,
    TARGET_PREV_POS_OFFSET = 0x48,
    DISTANCE_OFFSET = 0x38,

    SCREEN_WIDTH = 256,
    SCREEN_HEIGHT = 192,

    pos = Pos:new(),
    target_pos = Pos:new(),
    distance = 0,
    matrix = {}
}
Camera.__index = Camera

function Camera.update_from_memory()
    local data = Data:new(Camera.addr, 0x68)

    Camera.pos = Pos:new(data:readdwordrange(Camera.POS_OFFSET, 3))
    Camera.target_pos = Pos:new(data:readdwordrange(Camera.TARGET_POS_OFFSET, 3))
    Camera.distance = data:readdword(Camera.DISTANCE_OFFSET)

    local scaled_diff = ((Camera.target_pos - Camera.pos) / (Camera.distance * Pos.Fx32_ONE))
   
    Camera.matrix = {
        {scaled_diff[3], -scaled_diff[2]},
        {scaled_diff[2], scaled_diff[3]}
    }
end

function Camera.project(pos) -- convert a position vector to its absolute screen coordinates.
    local camera_to_pos = pos - Camera.pos
    local x = camera_to_pos[1]
    local y = (camera_to_pos[2] * Camera.matrix[1][1] + camera_to_pos[3] * Camera.matrix[1][2])
    local z = (camera_to_pos[2] * Camera.matrix[2][1] + camera_to_pos[3] * Camera.matrix[2][2])

    local scaled_x =  (Camera.distance / Pos.Fx32_ONE) * (x / z)
    local scaled_y =  (Camera.distance / Pos.Fx32_ONE) * (y / z)
    return {scaled_x + Camera.SCREEN_WIDTH / 2, scaled_y - Camera.SCREEN_HEIGHT / 2}
end

----------

local Obstructions = {-- list of rectangles defined by their upper-left and lower-right coordinates, representing areas where text cannot be displayed, i.e. in the case of open menus and such.
    addr = 0,
    menus = {
        bottom_screen = {
            is_showing = true, -- Lower screen is considered fully obstructed by default.
            coords = {{0, 0}, {256, 192}}
        },
        start_menu = {
            is_showing = false,
            coords = {{154, -190}, {253, -11}}
        },
        text_box = {
            is_showing = false,
            coords = {{2, -46}, {253, -3}}
        }
    }
}

function Obstructions.update_from_memory()
    local dword_1 = memory.readdword(Obstructions.addr)
    local dword_2 = memory.readdword(Obstructions.addr + 0x04)
    if dword_1 == Obstructions.addr + 0x6B7C then
        Obstructions.menus.start_menu.is_showing = false
        Obstructions.menus.text_box.is_showing = false
    elseif dword_1 ~= dword_2 then
        Obstructions.menus.start_menu.is_showing = true
        Obstructions.menus.text_box.is_showing = false
    elseif dword_1 == dword_2 then
        Obstructions.menus.start_menu.is_showing = false
        Obstructions.menus.text_box.is_showing = true
    end
end


----------

local Text = { -- Object that represents a string of text to be displayed on the screen.
    LETTER_WIDTH = 6,
    LETTER_HEIGHT = 8,
}
Text.__index = Text

function Text:new(text, x, y)
    local instance = {}
    setmetatable(instance, Text)
    instance.text = text or ""
    instance.x = x or 0 -- The internal coordinates are upper-left aligned for ease of computation.
    instance.y = y or 0
    return instance
end

-- Sets corner coordinates such that the center of the string is at (x,y).
function Text:set_center(x, y)
    local string_width = string.len(self.text) * Text.LETTER_WIDTH
    local ul_corner_x = x - string_width / 2
    local ul_corner_y = y - Text.LETTER_HEIGHT / 2
    self.x = ul_corner_x
    self.y = ul_corner_y
end

-- Returns a table of upper-left coordinates of each letter in the string.
function Text:char_positions()
    local positions = {}
    for i = 1, string.len(self.text) do
        table.insert(positions, {
            x = self.x + (i - 1) * Text.LETTER_WIDTH, 
            y = self.y})
    end
    return positions
end

-- Returns which letters in the string are obstructed by obstacles. Obstacles are given by Text.obstructions, a table of rectangles defined by their upper-left and lower-right coordinates.
function Text:check_obstruction() 
    local positions = self:char_positions()
    local obstructed_letters = {}
    for index, pos in pairs(positions) do
        for _, obstruction in pairs(Obstructions.menus) do
            if obstruction.is_showing then
                local coords = obstruction.coords
                if (pos.x + Text.LETTER_WIDTH >= coords[1][1] and pos.x <= coords[2][1]) 
                and (pos.y + Text.LETTER_HEIGHT >= coords[1][2] and pos.y <= coords[2][2]) then
                    table.insert(obstructed_letters, index)
                    break
                end
            end
        end
    end
    return obstructed_letters
end

function Text:display(x, y) -- (x, y) optional if you want to be a bit lazy.
    if x and y then
        self:set_center(x, y)
    end

    local characters = {}
    for i = 1, string.len(self.text) do
        characters[i] = string.sub(self.text, i, i)
    end

    local obstructed_chars = self:check_obstruction()
    for _, index in pairs(obstructed_chars) do
        characters[index] = nil
    end

    local positions = self:char_positions()
    for index, char in pairs(characters) do
        gui.text(positions[index].x, positions[index].y, char)
    end
end

return {
    Camera = Camera,
    Obstructions = Obstructions,
    Text = Text
}