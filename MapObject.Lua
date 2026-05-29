-- see https://github.com/pret/pokeplatinum/blob/main/src/map_object.c#L40
local MapObject = {}
MapObject.__index = MapObject

function MapObject:new(sprite, dir, pos)
    local instance = setmetatable({}, self)
    instance.sprite = sprite or 0
    instance.dir = dir or 0
    instance.pos = pos or {0, 0, 0}
    return instance
end

local MapObjectManager = {
    address = 0,
    max_objects = 64,
    num_objects = 0
}
function MapObjectManager.get_map_object(address)
    local data = memory.readbyterange(address, 296)
    local sprite = data[17] + data[18]*0x100 + data[19]*0x10000 + data[20]*0x1000000
    local dir = data[33] + data[34]*0x100 + data[35]*0x10000 + data[36]*0x1000000
    local x = data[89] + data[90]*0x100 + data[91]*0x10000 + data[92]*0x1000000
    local y = data[93] + data[94]*0x100 + data[95]*0x10000 + data[96]*0x1000000
    local z = data[97] + data[98]*0x100 + data[99]*0x10000 + data[100]*0x1000000
    local pos = {x, y, z}
    return MapObject:new(sprite, dir, pos)
end
function MapObjectManager.place_map_object(address, mapobj)
    memory.writedword(address + 16, mapobj.sprite)
    memory.writedword(address + 32, mapobj.dir)
    memory.writedword(address + 88, mapobj.pos[1])
    memory.writedword(address + 92, mapobj.pos[2])
    memory.writedword(address + 96, mapobj.pos[3])
end

return {MapObject, MapObjectManager}
