local secretary = require("TemporalSecretary")
require("SpriteData")

-- OOP wrapper for slurped in data processing. Allows definition of some basic functions and removes the need to handle 1-indexing math.
Data = {}
Data.__index = Data

function Data:new(address, size) -- Because this is only to be used for processing of readbyterange, we want the constructor to idiot-proof creation of these objects and only operate in that narrow context.
    if(not address or not size) then
        return setmetatable({}, self)
    end
    return setmetatable(memory.readbyterange(address, size), self)
end

function Data:readbyte(addr)
    return self[addr+1]
end
function Data:writebyte(addr, val)
    self[addr+1] = val
end
function Data:readbyterange(addr, length) -- Length is number of bytes. Returns a 1-indexed table of the bytes in the range. Included more for completeness than any actual utility.
    return {unpack(self, addr+1, addr+length)} -- Deprecated in later versions of Lua, but Desmume stands for Dinosaur Emulator Smume, so we're on 5.1.
end
function Data:writebyterange(addr, byte_table)
    for i, val in ipairs(byte_table) do
        self[addr+i] = val
    end
end

function Data:readword(addr)
    return self[addr+1] + self[addr+2]*0x100
end
function Data:writeword(addr, val)
    self[addr+1] = secretary.band(val, 0xFF)
    self[addr+2] = secretary.band(secretary.shift(val, ">>", 8), 0xFF)
end
function Data:readwordrange(addr, length) -- Length is number of words, not the number of bytes. Returns a 1-indexed table of the words in the range.
    local ret = {}
    for i = 1, length do
        local offset = addr + (i-1)*2
        ret[i] = self:readword(offset)
    end
    return ret
end
function Data:writewordrange(addr, word_table)
    for i, val in ipairs(word_table) do
        local offset = addr + (i-1)*2
        self:writeword(offset, val)
    end
end

function Data:readdword(addr)
    return self[addr+1] + self[addr+2]*0x100 + self[addr+3]*0x10000 + self[addr+4]*0x1000000
end
function Data:writedword(addr, val)
    self[addr+1] = secretary.band(val, 0xFF)
    self[addr+2] = secretary.band(secretary.shift(val, ">>", 8), 0xFF)
    self[addr+3] = secretary.band(secretary.shift(val, ">>", 16), 0xFF)
    self[addr+4] = secretary.band(secretary.shift(val, ">>", 24), 0xFF)
end
function Data:readdwordrange(addr, length) -- Length is number of dwords, not the number of bytes. Returns a 1-indexed table of the dwords in the range.
    local ret = {}
    for i = 1, length do
        local offset = addr + (i-1)*4
        ret[i] = self:readdword(offset)
    end
    return ret
end
function Data:writedwordrange(addr, dword_table)
    for i, val in ipairs(dword_table) do
        local offset = addr + (i-1)*4
        self:writedword(offset, val)
    end
end

function Data:write_to_memory(addr)
    local length = #self
    local length_dwords = math.floor(length/4)
    for i = 1, length_dwords do
        local offset = (i-1)*4
        memory.writedword(addr+offset, self:readdword(offset))
    end
    for i = length_dwords*4 + 1, length do
        local offset = i-1
        memory.writebyte(addr+offset, self:readbyte(offset))
    end
end

-- In Gen 4, strings encode as 16-bit sequences terminating in 0xFFFF. Note that the encoding is NOT UTF-16, but is instead specific to Pokemon.
-- For now, I will only dedicate energy to handling alphanumeric characters, and will add handling for the rest later.
function Data:readstring(addr)
    local str = ""
    for i = 0, 20, 2 do
        local char = self:readword(addr + i)
        if char == 0xFFFF then
            break
        else
            if char >= 0x145 and char <= 0x15e then
                char = char - 0x145 + string.byte("a")
            elseif char >= 0x12b and char <= 0x144 then
                char = char - 0x12b + string.byte("A")
            elseif char >= 0x121 and char <= 0x12a then
                char = char - 0x121 + string.byte("0")
            else
                char = string.byte("?")
            end

            str = str .. string.char(char)
        end
    end
    return str
end

-- Decrypts the data in-place rather than returning a new table. Implementation of this and the next function is largely copied from Emi's versus link ersatz. See https://projectpokemon.org/home/docs/gen-4/pkm-structure-r65/ for further info.
function Data:decrypt(seed, offset, length) 
	local ret = {}
	local prng = seed;
	-- Did you know Lua will coerce all literals to be at max 0xffffffff?
	-- This means if you do `% 0x100000000` you're actually doing `% 0xffffffff`
	-- This isn't a limitation of the math though, just the literal parsing
	local mod = 0xffffffff + 1
	for i = 0, length-1, 2 do
		local index = i + offset
		-- Multiplying by 0x41C64E6D without losing precision
		local next = (((0x41C6 * prng) % 0x100000) * 0x10000) % mod
		next = next + (0x4E6D * prng) % mod
		prng = (next + 0x6073) % mod
		local v = self:readword(index)
		v = secretary.xor(v, math.floor(prng / 0x10000))

		self[index+1] = v % 0x100
		self[index+2] = math.floor(v / 0x100)
	end
end

function Data:checksum(addr, length)
	local sum = 0
	for i = 0, length-1, 2 do
		sum = (sum + self:readword(addr+i)) % 0x10000
	end
	return sum
end

----------

-- Coordinates as Fx32 (fixed point 32-bit) values. 1 bit for the sign, then 19 bits for the integer portion, then 12 decimal bits. Graphics coordinates use these in the game's engine.
-- Note that each tile is 16 (=2^4) pixels.
Pos = {
    Fx32_ONE = 0x00001000,
}
Pos.__index = Pos

function Pos:new(coords)
    local table = coords or {0, 0, 0}
    return setmetatable(table, self)
end

function Pos:to_pixels()
    local x = self[1] / Pos.Fx32_ONE
    local y = self[2] / Pos.Fx32_ONE
    local z = self[3] / Pos.Fx32_ONE
    return {x, y, z}
end

function Pos:from_pixels(pixels)
    local x = pixels[1] * Pos.Fx32_ONE
    local y = pixels[2] * Pos.Fx32_ONE
    local z = pixels[3] * Pos.Fx32_ONE
    return setmetatable({x, y, z}, Pos)
end

function Pos:to_tiles()
    local pixels = self:to_pixels()
    local x = pixels[1] / 16
    local y = pixels[2] / 16
    local z = pixels[3] / 16
    return setmetatable({x, y, z}, Pos)
end

function Pos:from_tiles(tiles)
    local x = tiles[1] * 16
    local y = tiles[2] * 16
    local z = tiles[3] * 16
    return self:from_pixels({x, y, z})
end

function Pos.__add(pos1, pos2)
    return Pos:new({pos1[1] + pos2[1], pos1[2] + pos2[2], pos1[3] + pos2[3]})
end

function Pos.__sub(pos1, pos2)
    return Pos:new({pos1[1] - pos2[1], pos1[2] - pos2[2], pos1[3] - pos2[3]})
end

function Pos.__mul(pos, scalar) -- scalar is assumed to be in fx32
    return Pos:new({pos[1] * (scalar/Pos.Fx32_ONE), pos[2] * (scalar/Pos.Fx32_ONE), pos[3] * (scalar/Pos.Fx32_ONE)})
end

function Pos.__div(pos, scalar) -- scalar is assumed to be in fx32
    return Pos:new({pos[1] / (scalar/Pos.Fx32_ONE), pos[2] / (scalar/Pos.Fx32_ONE), pos[3] / (scalar/Pos.Fx32_ONE)})
end

----------

-- Billboards are, somewhat simplifying, the 3d objects which are generated from 2d objects, angled towards the camera. The game generates one for each map object (which represent trainers, cut trees, etc), and the billboards are what actually gets fed
-- into the graphics pipeline. They are tracked via linked list format. The size of a single billboard is 0xC4 (=196) bytes.
-- See https://github.com/pret/pokeplatinum/blob/main/include/billboard.h#L22.
Billboard = {
    POS_OFFSET = 0x00,
    CALLBACK_OFFSET = 0x18,
    DRAW_OFFSET = 0x24,
    MODELSET_OFFSET = 0x84,
    MODEL_OFFSET = 0x88,
    TEXTURE_OFFSET = 0x8c,
    ANIM_TEXTURE_OFFSET = 0x90,
    TEXKEY_OFFSET = 0x94,
    TEX44KEY_OFFSET = 0x98,
    PLTTKEY_OFFSET = 0x9c,
    GFXSEQUENCE_OFFSET = 0xa0,
    ANIM_TYPE_OFFSET_1 = 0xb6,
    ANIM_TYPE_OFFSET_2 = 0xba,
    ANIM_FRAME_OFFSET = 0xb9,
    NEXT_OFFSET = 0xbc,
    PREV_OFFSET = 0xc0,
    SIZE = 0xC4,
    scratch_base = 0x023c0000
}
Billboard.__index = Billboard

function Billboard:new(addr, pos, sprite, anim, frame, visible, next_billboard, prev_billboard)
    local instance = setmetatable({}, self)
    instance.addr = addr or 0
    instance.pos = pos or Pos:new()
    instance.sprite = sprite or 0
    instance.anim_type = anim or 0
    instance.anim_frame = frame or 0
    instance.visible = visible or 0
    instance.next = next_billboard or nil
    instance.prev = prev_billboard or nil
    return instance
end

function Billboard.from_memory(address)
    local addr = address
    local data = Data:new(addr, Billboard.SIZE)

    local coords = data:readdwordrange(Billboard.POS_OFFSET, 3)
    local pos = Pos:new(coords)

    local animtex_addr = data:readdword(Billboard.ANIM_TEXTURE_OFFSET)
    local sprite_info = memory.readdword(animtex_addr + 0x1cc)
    local sprite = nil
    if sprite_info == 0x675f6c70 then -- "pl_g"
        sprite = 1
    elseif sprite_info == 0x625f6c70 then -- "pl_b"
        sprite = 2
    end

    local anim_type = data:readbyte(Billboard.ANIM_TYPE_OFFSET_1)
    local anim_frame = data:readbyte(Billboard.ANIM_FRAME_OFFSET)

    return Billboard:new(addr, pos, sprite, anim_type, anim_frame)
end

function Billboard:update_from_memory()
    local update = Billboard.from_memory(self.addr)
    self.pos = update.pos
    self.anim_type = update.anim_type
    self.anim_frame = update.anim_frame
end

function Billboard:flesh_forward() -- Finds next billboard in the game's linked list and sets up an object to track it. Returns nil if there is no next billboard, or if we already have a "next billboard" object.
    if self.next then
        return self.next
    end

    local next_addr = memory.readdword(self.addr + Billboard.NEXT_OFFSET)
    if next_addr < 0x02200000 or next_addr > 0x02400000 then -- Very basic sanity check.
        print("Warning: next billboard address out of bounds: " .. string.format("0x%x", next_addr))
        return nil
    end

    self.next = Billboard.from_memory(next_addr)
    self.next.prev = self

    return self.next
end

function Billboard:flesh_back() -- Finds previous billboard in the game's linked list and sets up an object to track it. Returns nil if there is no previous billboard, or if we already have a "previous billboard" object.
    if self.prev then
        return self.prev
    end

    local prev_addr = memory.readdword(self.addr + Billboard.PREV_OFFSET)
    if prev_addr < 0x02200000 or prev_addr > 0x02400000 then -- Very basic sanity check.
        print("Warning: previous billboard address out of bounds: " .. string.format("0x%x", prev_addr))
        return nil
    end

    self.prev = Billboard.from_memory(prev_addr)
    self.prev.next = self

    return self.prev
end

function Billboard:set_next(next_billboard)
    self.next = next_billboard
    memory.writedword(self.addr + Billboard.NEXT_OFFSET, next_billboard.addr)
end

function Billboard:set_prev(prev_billboard)
    self.prev = prev_billboard
    memory.writedword(self.addr + Billboard.PREV_OFFSET, prev_billboard.addr)
end

function Billboard:delete()
    self.next:set_prev(self.prev)
    self.prev:set_next(self.next)

    self.next = nil
    self.prev = nil
end

function Billboard:insert_after(target) -- Inserts the this billboard after the given billboard in the linked list.
    if self.prev then
        return
    end
    self:set_next(target.next)
    target.next:set_prev(self)

    self:set_prev(target)
    target:set_next(self)
end

function Billboard:insert_before(target) -- Inserts the this billboard before the given billboard in the linked list.
    if self.next then
        return
    end
    self:set_prev(target.prev)
    target.prev:set_next(self)

    self:set_next(target)
    target:set_prev(self)
end

function Billboard:move_to(new_pos)
    self.pos = new_pos
    memory.writedword(self.addr + Billboard.POS_OFFSET, new_pos[1])
    memory.writedword(self.addr + Billboard.POS_OFFSET + 0x04, new_pos[2])
    memory.writedword(self.addr + Billboard.POS_OFFSET + 0x08, new_pos[3])
end

function Billboard:show()
    self.visible = 1
    memory.writedword(self.addr + Billboard.DRAW_OFFSET, self.visible)
end

function Billboard:hide()
    self.visible = 0
    memory.writedword(self.addr + Billboard.DRAW_OFFSET, self.visible)
end

function Billboard:adv_frame()
    self.anim_frame = (self.anim_frame + 0x10) % 0x100
    memory.writebyte(self.addr + Billboard.ANIM_FRAME_OFFSET, self.anim_frame)
end

function Billboard.generate_texkey(addr, size) -- If size not defined, defaults to 0x3000
    if not size then
        size = Textures.SIZE
    end
    local size_word = secretary.shift(size, "<<", 12)
    local addr_word = secretary.band(secretary.shift(addr, ">>", 3), 0x0000FFFF)

    return size_word + addr_word
end

function Billboard.decode_texkey(texkey)
    local size_word = secretary.band(texkey, 0x7fff0000)
    local size = secretary.shift(size_word, ">>", 12)

    local addr_word = secretary.band(texkey, 0x0000FFFF)
    local addr = secretary.shift(addr_word, "<<", 3)

    return {addr, size}
end

function Billboard.generate_plttkey(addr, size)
    local size_word = secretary.shift(size, "<<", 13)
    local addr_word = secretary.band(secretary.shift(addr, ">>", 3), 0x0000FFFF)

    return size_word + addr_word
end

function Billboard.decode_plttkey(plttkey)
    local size_word = secretary.band(plttkey, 0x7ffe0000)
    local size = secretary.shift(size_word, ">>", 13)

    local addr_word = secretary.band(plttkey, 0x0000FFFF)
    local addr = secretary.shift(addr_word, "<<", 3)

    return {addr, size}
end

function Billboard:write()
    memory.writedword(self.addr + Billboard.POS_OFFSET, self.pos[1])
    memory.writedword(self.addr + Billboard.POS_OFFSET + 0x04, self.pos[2])
    memory.writedword(self.addr + Billboard.POS_OFFSET + 0x08, self.pos[3])

    memory.writedword(self.addr + Billboard.DRAW_OFFSET, self.visible)

    memory.writebyte(self.addr + Billboard.ANIM_TYPE_OFFSET_1, self.anim_type)
    memory.writebyte(self.addr + Billboard.ANIM_TYPE_OFFSET_2, self.anim_type)
    memory.writebyte(self.addr + Billboard.ANIM_FRAME_OFFSET, self.anim_frame)
    if self.next then
        memory.writedword(self.addr + Billboard.NEXT_OFFSET, self.next.addr)
    end
    if self.prev then
        memory.writedword(self.addr + Billboard.PREV_OFFSET, self.prev.addr)
    end

    if self.sprite then
        local addr = 0x6840000 + (self.sprite - 1) * (Textures.SIZE)
        local texkey = Billboard.generate_texkey(addr, Textures.SIZE)
        memory.writedword(self.addr + Billboard.TEXKEY_OFFSET, texkey)

        local addr = Palettes.BASE - self.sprite * (Palettes.SIZE)
        local plttkey = Billboard.generate_plttkey(addr, Palettes.SIZE)
        memory.writedword(self.addr + Billboard.PLTTKEY_OFFSET, plttkey)
    end
end

----------

BillboardList = {
    addr = 0,
    billboards = {}, -- Excludes the head and tail.
    head = {}, -- First billboard, doesn't track an actual player but exists as a reference point to attach the list into the game's list. 
    tail = {}, -- Last billboard, see above.
    scratch_base = 0x023c0000, -- This is a safe place to write temporary data that won't mess with the game. It's far away from any critical data structures, and the game doesn't seem to use it for anything.
    CAPACITY_OFFSET = 0x08
}

function BillboardList.update_template(template)
    for i = 0, 101 do -- TODO: Avoid writing to texkey and plttkey fields.
        local offset = BillboardList.scratch_base + i*Billboard.SIZE
        template:write_to_memory(offset)
    end
end

function BillboardList.clear_list()
    local current = BillboardList.head.next
    while current ~= BillboardList.tail do
        local temp = current.next
        current:delete()
        current = temp
    end
end

function BillboardList.get_index(billboard) -- Returns neighbor index from their billboard.
    local offset = billboard.addr - BillboardList.scratch_base
    return math.floor(offset / Billboard.SIZE)
end

function BillboardList.insert_A_before_B(A, B)
    A:insert_before(B)
    BillboardList.billboards[BillboardList.get_index(A)] = A
end

function BillboardList.insert_A_after_B(A, B)
    A:insert_after(B)
    BillboardList.billboards[BillboardList.get_index(A)] = A
end

----------

-- The info we care about for a given Pokemon.
Pokemon = {
    party_addr = 0,
    battle_addr = 0,
    unshuffle_table = {
        {1,2,3,4},
        {1,2,4,3},
        {1,3,2,4},
        {1,4,2,3},
        {1,3,4,2},
        {1,4,3,2},
        {2,1,3,4},
        {2,1,4,3},
        {3,1,2,4},
        {4,1,2,3},
        {3,1,4,2},
        {4,1,3,2},
        {2,3,1,4},
        {2,4,1,3},
        {3,2,1,4},
        {4,2,1,3},
        {3,4,1,2},
        {4,3,1,2},
        {2,3,4,1},
        {2,4,3,1},
        {3,2,4,1},
        {4,2,3,1},
        {3,4,2,1},
        {4,3,2,1},
    },
    -- We have some constants here defined for the sake of sanity checks for data integrity, since the game messes with Pokemon memory a lot.
    MAX_LEVEL = 100,
    MAX_STAT = 714, -- Blissey max possible HP.
    NUM_ABILITIES = 123, -- Number of abilities in Gen 4 minus 1, since "no ability" is treated as 0.
    NUM_MOVES = 467, -- Number of moves in Gen 4 minus 1, since "no move" is treated as 0. 
    NUM_ITEMS = 467, -- Number of items in Gen 4 minus 1, since "no item" is treated as 0. As far as I can tell, a complete coincidence.
    NUM_SPECIES = 493 -- Dex number of Arceus. 
}
Pokemon.__index = Pokemon

function Pokemon:new(species, forme, gender, ability,name, level, stats, moves, held_item, curr_hp)
    local instance = setmetatable({}, self)
    instance.species = species or 0
    instance.forme = forme or 0
    instance.gender = gender or 4
    instance.ability = ability or 1
    instance.name = name or ""
    instance.level = level or 1
    instance.stats = stats or {0, 0, 0, 0, 0, 0}
    instance.moves = moves or {0, 0, 0, 0}
    instance.held_item = held_item or 0
    instance.curr_hp = curr_hp or 0
    return instance
end

function Pokemon:sanity_check()
    if self.species > Pokemon.NUM_SPECIES or self.level > Pokemon.MAX_LEVEL or self.ability > Pokemon.NUM_ABILITIES or self.held_item > Pokemon.NUM_ITEMS then
        return false
    end
    for i, stat in pairs(self.stats) do
        if stat > Pokemon.MAX_STAT then
            return false
        end
    end
    if self.curr_hp > self.stats[1] then
        return false
    end
    for i, move in pairs(self.moves) do
        if move > Pokemon.NUM_MOVES then
            return false
        end
    end

    return true
end

-- This function is for reading party members OUTSIDE of battle. Index ranges 1 to 6, correlating to the party order of the Pokemon we want to read.
function Pokemon.from_party_memory(index)
    local ret = Pokemon:new()
    local mon_data = Data:new(Pokemon.party_addr + (index-1)*0xec, 0xec) 
    -- Anatomy: First 0x08 bytes contain unencrypted personality and checksum info. Remaining 0xe4 (=228) bytes splits into two segments.
    -- First segment is generic info that changes relatively little (species, name, ability, moves, ivs, etc). This is 0x80 (=128) bytes and is encrypted using the checksum, and then shuffled in four blocks of 0x20 (=32) bytes.
    -- Second segment is mostly dynamic info relevant for battling (computed stats, current HP, etc). This is 0x64 (=100) bytes and is encrypted using the personality value. This half is not shuffled.

    local mon_info = 0x08
    local battle_info = 0x08 + 0x80
    local personality = mon_data:readdword(0x00)
	local checksum = mon_data:readword(0x06)

    -- Sometimes, the data is already decrypted by the game. To check this, we just see if the checksum passes. If not, we'll decrypt it and check again
    if checksum ~= mon_data:checksum(mon_info, 0x80) then
	    mon_data:decrypt(checksum, mon_info, 0x80)
        if checksum ~= mon_data:checksum(mon_info, 0x80) then
            return false
        end
	end

	local shift_val = (secretary.band(personality, 0x3E000) / 8192) % 24
    local permutation = Pokemon.unshuffle_table[shift_val + 1]

    local A = (permutation[1]-1)*32
    local B = (permutation[2]-1)*32
    local C = (permutation[3]-1)*32
    local D = (permutation[4]-1)*32

    ret.species = mon_data:readword(mon_info + A + 0x00)
    ret.held_item = mon_data:readword(mon_info + A + 0x02)
    ret.ability = mon_data:readbyte(mon_info + A + 0x0D)
    for i = 1, 4 do
        local offset = (i-1)*2
        ret.moves[i] = mon_data:readword(mon_info + B + offset)
    end

    ret.name = mon_data:readstring(mon_info + C)

    local gender_forme = mon_data:readbyte(mon_info + B + 0x18)
    ret.gender = secretary.band(gender_forme, 0x06)/0x02 -- %00000110, bit shifted >> 1
    ret.forme = secretary.band(gender_forme, 0xF8)/0x08 -- %11111000, bit shifted >> 3

    ret.level = mon_data:readbyte(battle_info + 0x04)
    ret.curr_hp = mon_data:readword(battle_info + 0x06)
    ret.stats = mon_data:readwordrange(battle_info + 0x08, 6)

    -- There is no checksum for this region of memory, so we pull a basic sanity check at the end to make sure we have proper data before returning.
    if not ret:sanity_check() then
        mon_data:decrypt(personality, battle_info, 0x64)
        ret.level = mon_data:readbyte(battle_info + 0x04)
        ret.curr_hp = mon_data:readword(battle_info + 0x06)
        ret.stats = mon_data:readwordrange(battle_info + 0x08, 6)
        if not ret:sanity_check() then
            return false
        end
    end
    return ret
end

-- This function parses battle data for a given currently out pokemon. Index ranges 1 to 4, correlating to the order of Pokemon in battle.
function Pokemon.from_battle_memory(index)
    local mon_data = Data:new(Pokemon.battle_addr + (index-1)*0xb4, 0xb4)

    local species = mon_data:readword(0x00)
    local forme = secretary.band(mon_data:readbyte(0x26), 0x1f) -- %00011111
    local ability = mon_data:readbyte(0x27)
    local level = mon_data:readbyte(0x34)
    local name = mon_data:readstring(0x36)
    local held_item = mon_data:readword(0x78)
    local gender = secretary.band(mon_data:readbyte(0x7e), 0x0f) -- %00001111
    local curr_hp = mon_data:readword(0x4c)

    local stats = {}
    stats[1] = mon_data:readword(0x50) -- max hp
    for i = 2, 6 do
        local offset = (i-1)*2
        stats[i] = mon_data:readword(offset)
    end

    local moves = {}
    for i = 1, 4 do
        local offset = 0x0C +(i-1)*2
        moves[i] = mon_data:readword(offset)
    end

    local ret = Pokemon:new(species, forme, gender, ability,name, level, stats, moves, held_item, curr_hp)
    if not ret:sanity_check() then
        return false
    end
    return ret
end

----------

-- Map Objects are how the game tracks other trainers, or interactible world objects such as cut trees or rock smash rocks. Actors should very roughly correspond to the trainer map objects.
-- The struct is 0x128 (=296) bytes long. Party info is stored elsewhere, but for our purposes we want them here, so don't expect the notion of an Actor in this script to map totally cleanly onto the notion of a Map Object.
-- See https://github.com/pret/pokeplatinum/blob/main/src/map_object.c#L40
Actor = {
    MAP_OFFSET = 0x0C,
    DIR_OFFSET = 0x28,
    POS_OFFSET = 0x70,
    BILLBOARD_OFFSET = 0x10c
}
Actor.__index = Actor

function Actor:new(id, name, pronouns, map, is_moving, party, billboard)
    local instance = setmetatable({}, self)
    instance.id = id or 0
    instance.name = name or ""
    instance.pronouns = pronouns or 0
    instance.map = map or 0 -- route, except we set it to 0 if its the overworld.
    instance.route = map or 0
    instance.is_moving = is_moving or 0
    instance.party = party or {}
    instance.billboard = billboard or nil
    return instance
end

function Actor.wrap(raw) -- converts the raw table returned by the secretary to an Actor metatable
    setmetatable(raw.billboard, Billboard)
    raw.billboard.addr = Billboard.scratch_base + (raw.id * Billboard.SIZE)
    setmetatable(raw.billboard.pos, Pos)

    for i = 1, 6 do
        if raw.party[i] then
            setmetatable(raw.party[i], Pokemon)
        end
    end

    return setmetatable(raw, Actor)
end

----------

ActorManager = { -- Star of the show
    addr = 0,
    player_addr = 0,
    player = Actor:new(),
    neighbors = {}, -- indexed by PID
    BillboardList = BillboardList
} 
ActorManager.__index = ActorManager

function ActorManager.cull(indices) -- If called with no argument, culls the whole list.
    print("Culling neighbors: " .. (indices and table.concat(indices, ", ") or "all"))
    -- Setting to nil in pairs() loop is undefined in 5.1, so even when culling all we need to actually collect the full set of indices anyway.
    if not indices then
        indices = {}
        for index, _ in pairs(ActorManager.neighbors) do
            table.insert(indices, index)
        end
    end
    for _, index in pairs(indices) do
        local neighbor = ActorManager.neighbors[index]
        if neighbor then
            neighbor.billboard:delete()
            ActorManager.neighbors[index] = nil
        end
    end
end

function ActorManager.next_neighbor(neighbor) -- Returns the neighbor corresponding to the next billboard in the linked list.
    local next_billboard = neighbor.billboard.next
    if not next_billboard or next_billboard == ActorManager.BillboardList.tail then
        return nil
    end
    local index = ActorManager.BillboardList.get_index(next_billboard)
    return ActorManager.neighbors[index]
end

function ActorManager.update_from_secretary(update)
    local keep = update.keep
    for _, keep in ipairs(keep) do
        local id = keep.id
        local neighbor = Actor.wrap(keep)
        if neighbor and neighbor.map == ActorManager.player.map then 
            if ActorManager.neighbors[id] then
                neighbor.billboard.next = ActorManager.neighbors[id].billboard.next
                neighbor.billboard.prev = ActorManager.neighbors[id].billboard.prev
            else
                ActorManager.BillboardList.insert_A_before_B(neighbor.billboard, ActorManager.BillboardList.tail)
            end
            ActorManager.neighbors[id] = neighbor
            ActorManager.neighbors[id].billboard.visible = 1
            ActorManager.neighbors[id].billboard:write()
        end

    end

    local kick = update.kick
    if kick and #kick > 0 then
        ActorManager.cull(kick)
    end
end

function ActorManager.hide_billboard_list()
    local snip_start = ActorManager.BillboardList.head.prev
    local snip_end = ActorManager.BillboardList.tail.next

    if snip_start and snip_end then
        snip_start:set_next(snip_end)
        snip_end:set_prev(snip_start)
    end

    ActorManager.BillboardList.head.prev = nil
    ActorManager.BillboardList.tail.next = nil
end

function ActorManager.show_billboard_list()
    local snip_start = ActorManager.player.billboard
    local snip_end = ActorManager.player.billboard.next

    if snip_end ~= ActorManager.BillboardList.head then
        ActorManager.BillboardList.head:set_prev(snip_start)
        snip_start:set_next(ActorManager.BillboardList.head)

        ActorManager.BillboardList.tail:set_next(snip_end)
        snip_end:set_prev(ActorManager.BillboardList.tail)
    end
end

function ActorManager.update_billboard_list()
    ActorManager.hide_billboard_list()

    local player_billboard_addr = memory.readdword(ActorManager.player_addr + Actor.BILLBOARD_OFFSET)
    ActorManager.player.billboard = Billboard.from_memory(player_billboard_addr)
    ActorManager.player.billboard:flesh_forward()

    local billboard_template = Data:new(ActorManager.player.billboard.addr, Billboard.SIZE)
    billboard_template:writedwordrange(Billboard.POS_OFFSET, {0, 0, 0})
    billboard_template:writedwordrange(Billboard.CALLBACK_OFFSET, {0, 0, 0})
    billboard_template:writedword(Billboard.DRAW_OFFSET, 0)
    ActorManager.BillboardList.update_template(billboard_template)
    for i, neighbor in pairs(ActorManager.neighbors) do
        if neighbor.billboard then
            neighbor.billboard:write()
        end
    end

    ActorManager.BillboardList.head:write()
    ActorManager.BillboardList.tail:write()
    ActorManager.show_billboard_list()
end