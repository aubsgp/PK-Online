local secretary = require("TemporalSecretary")
local FictionalDictionary = require("FictionalDictionary")
local ENCODING = FictionalDictionary.ENCODING

-- OOP wrapper for slurped in data processing. Allows definition of some basic functions and removes the need to handle 1-indexing math.
local Data = {}
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

-- In Gen 4, strings encode as 16-bit sequences terminating in 0xFFFF. Note that the encoding is NOT UTF-16, but is instead specific to Pokemon.
function Data:readstring(addr)
    local ret = {}
    for i = 0, 20, 2 do
        local char = self:readword(addr + i)
        if char == 0xFFFF then
            break
        end
        table.insert(ret, char)
    end
    return ret
end
function Data.encode_string(data)
    local str = ""
    for _, char in ipairs(data) do
        if char == 0xFFFF or char == 0 then
            break
        end
        local character = ENCODING[char]
        if string.byte(character) < 32 or string.byte(character) > 126 then
            str = str .. "_"
        else
            str = str .. character
        end
    end
    return str
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

function Data.deep_copy(orig, memo)
    if type(orig) ~= "table" then 
        return orig
    end
    memo = memo or {}
    if memo[orig] then 
        return memo[orig] 
    end
    local copy = {}
    memo[orig] = copy
    for k, v in pairs(orig) do
        copy[Data.deep_copy(k, memo)] = Data.deep_copy(v, memo)
    end
    return setmetatable(copy, getmetatable(orig))
end

function Data.deep_compare(a, b, memo)
    if a == b then return true end
    if type(a) ~= type(b) or type(a) ~= "table" or getmetatable(a) ~= getmetatable(b) then 
        return false 
    end

    memo = memo or {}
    if memo[a] == b then 
        return true 
    end
    memo[a] = b

    for k, v in pairs(a) do
        if not Data.deep_compare(v, b[k], memo) then 
            return false 
        end
    end
    for k, v in pairs(b) do
        if a[k] == nil then 
            return false 
        end
    end

    return true
end

return Data