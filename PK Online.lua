local secretary = require("TemporalSecretary")
local pid = secretary.HANDSHAKE()
print("Handshake returned player server id: " .. pid)

require("SpriteData")
require("ObjectOrientationDay")
require("Display")
require("FictionalDictionary")

local mem_base_pointer = memory.readdword(0x2000BA8) + 0x20 -- Although we do a read here, this value should always be fixed across sessions. The read is primarily for future-proofing against the script being ported to other romhacks.
local mem_base = nil
local battlesystem_addr = nil
local battlecontext_addr = nil

local player = Actor:new(pid)
ActorManager.player = player

local function inject_textures_palettes()
    memory.writebyte(0x04000240, 0x80) -- makes texture/palette data visible to the cpu so that we can see it in the memory viewer
    memory.writebyte(0x04000241, 0x88)
    memory.writebyte(0x04000244, 0x80)

    for i, texture in ipairs(Textures) do
        local texdata = setmetatable(texture, Data)
        texdata:write_to_memory(Textures.BASE - i*Textures.SIZE) -- We inject textures back-to-front so that we don't have to worry about overwriting anything important in the memory region.
    end
    for i, palette in ipairs(Palettes) do
        local paldata = setmetatable(palette, Data)
        paldata:write_to_memory(Palettes.BASE - i*Palettes.SIZE) -- Same deal here.
    end

    memory.writebyte(0x04000240, 0x83) -- reverts it in the same frame so as to avoid causing visible graphical oddities.
    memory.writebyte(0x04000241, 0x8b)
    memory.writebyte(0x04000244, 0x83)
end
inject_textures_palettes()

local function get_addresses()
    mem_base = memory.readdword(mem_base_pointer)

    Pokemon.party_addr = mem_base + 0xb4
    battlesystem_addr = mem_base + 0x417fc
    battlecontext_addr = memory.readdword(battlesystem_addr + 0x30)
    Pokemon.battle_addr = battlecontext_addr + 0x2d40

    ActorManager.addr = mem_base + 0x23730
    ActorManager.player_addr = memory.readdword(ActorManager.addr + 0x124) -- The player is always the mapfirst object; the mapobject manager accordingly points to it as its second-to-last pointer.

    local namedata = Data:new(mem_base + 0x7c, 20)
    player.name = namedata:readstring(0)
    local player_billboard_addr = memory.readdword(ActorManager.player_addr + Actor.BILLBOARD_OFFSET)
    BillboardList.addr = memory.readdword(player_billboard_addr + 0x28)

    local fieldsystem_addr = memory.readdword(ActorManager.addr + 0x128)
    Camera.addr = memory.readdword(fieldsystem_addr + 0x24)
    Obstructions.addr = mem_base + 0x217A8
end
get_addresses()

memory.registerwrite(mem_base_pointer, 4, get_addresses) -- If our memory base ever gets changed, we will need to do all this again. This can happen, for instance, on reloading a save.

-- We now set up the billboards for all the potential neighbors.

-- First, we need to grab the player billboard. We won't proceed until we have done so.
local player_billboard_addr = memory.readdword(ActorManager.player_addr + Actor.BILLBOARD_OFFSET)
while(player_billboard_addr < 0x2000000 or player_billboard_addr > 0x2400000) do
    print("Waiting for valid player billboard address...")
    emu.frameadvance()
    player_billboard_addr = memory.readdword(ActorManager.player_addr + Actor.BILLBOARD_OFFSET)
end
player.billboard = Billboard.from_memory(player_billboard_addr)


-- Set the template for all neighbor billboards.
local billboard_template = Data:new(ActorManager.player.billboard.addr + Billboard.SIZE, Billboard.SIZE) 
billboard_template:writedwordrange(Billboard.POS_OFFSET, {0, 0, 0})
BillboardList.update_template(billboard_template)

-- Fixed "anchor" billboards make insertion and removal of the whole neighbor billboard list very painless.
BillboardList.head = Billboard.from_memory(Billboard.scratch_base)
BillboardList.tail = Billboard.from_memory(Billboard.scratch_base + 101*Billboard.SIZE)
BillboardList.head:set_next(BillboardList.tail)
BillboardList.tail:set_prev(BillboardList.head)

local hands_off_timer = 0
local timer = 1
local in_battle = false
local done_wait = false
local function billboard_setup()
    local player_billboard_addr = memory.readdword(ActorManager.player_addr + Actor.BILLBOARD_OFFSET)
    if player_billboard_addr < 0x2000000 or player_billboard_addr > 0x2400000 then
        timer = 1
        return
    end

    local next_addr = memory.readdword(player_billboard_addr + Billboard.NEXT_OFFSET)
    if next_addr < 0x2000000 or next_addr > 0x2400000 then
        timer = 1
        return
    end

    if not done_wait then
        timer = 100
        done_wait = true
        return
    end

    ActorManager.update_billboard_list()

    timer = -1
    done_wait = false
end

while timer >= 0 do
    if timer > 0 then
        emu.frameadvance()
    elseif timer == 0 then
        billboard_setup()
    end
    timer = timer - 1
end

memory.registerwrite(ActorManager.player_addr + Actor.BILLBOARD_OFFSET, 4, billboard_setup)

local to_update = {false, false, false, false, false, false}
local read_result = nil

local frame_counter = 0



local function update()
    if timer == 0 then
        billboard_setup()
    end
    if timer >= 0 then
        timer = timer - 1
    end

    frame_counter = (frame_counter+1)%60

    -- We want to be processing stuff differently depending on whether or not we are in battle.
    -- For instance, position should not update while we're in battle, and we need to be reading from different memory locations to get the stats of our Pokemon.
    local should_update_player = true
    if memory.readbyte(0x02197910) == 1 then
        if not in_battle then
            in_battle = true
            hands_off_timer = 1000 -- To prevent us from reading garbage when we enter battle, we set a timer of 1000 frames to give the game some time to get its affairs in order.
        end
    else
        if in_battle then
            in_battle = false
            billboard_setup()
            get_addresses()
            inject_textures_palettes()
        end
    end
    if hands_off_timer > 0 then
        hands_off_timer = hands_off_timer - 1
        return
    end

    -- Relevant pokeplatinum github pages: https://github.com/pret/pokeplatinum/blob/main/include/battle/battle_mon.h, https://github.com/pret/pokeplatinum/blob/main/include/battle/battle_context.h
    -- Each in-battle Pokemon's battle state is stored as an unencrypted BattleMon struct, which is 0xb4 (=180) bytes long. This includes, for instance, stats, current HP, moves, and so on.
    -- The battle context struct includes in-place an array of 4 BattleMon structs, 2 for each side. 
    --      - In a double battle, the first two are yours and the second two are the opponent's. (In a tag battle, the second is your partner's.)
    --      - In a single battle, the first one is yours and the second one is the opponent's, and the other two are just zeroed out.
    -- The tricky bit here is that Pokemon not currently out seem to be encrypted, and its nontrivial to figure out both where and with what key. As such, we use a bit of a workaround:
    -- We just track which Pokemon is currently out each turn, and use this to know who to update each frame. This is stored x11c (=284) bytes after the end of the BattleMon array.
    -- This means if a Pokemon in the back levels up, we won't know until the next time it is sent out, or once the battle ends. Otherwise, this should be accurate.
    if in_battle then
        local is_double_battle = false
        if memory.readbyte(battlesystem_addr + 0x2c) == 2 then -- See https://github.com/pret/pokeplatinum/blob/main/include/constants/battle.h#L24
            is_double_battle = true
        end

        local party_order = {}
        for i = 1, 4 do
            local offset = 4*0xb4 + 0x11c + (i-1)*6
            party_order[i] = memory.readbyterange(Pokemon.battle_addr + offset, 6) -- The party order of the ith participant in battle, as a permutation of the party order going in. The first byte is the currently-out mon. 
            -- TODO: double-check this actually works for double battles!!!!!
        end
        local currently_out = {party_order[1][1] + 1, party_order[1][2] + 1}
        read_result = Pokemon.from_battle_memory(1)
        if read_result then
            player.party[currently_out[1]] = read_result
        end
        if is_double_battle then
            read_result = Pokemon.from_battle_memory(2)
            if read_result then
                player.party[currently_out[2]] = read_result
            end
        end

    else

        get_addresses()
        if player.billboard.addr ~= 0 then
            inject_textures_palettes()
        end
        -- Update location info.
        local route = memory.readdword(mem_base + 0x1294)
        local map = route
        if Overworld[route] then
            map = 0
        end
        -- if player.route ~= route then
        --     player.route = route
        --     print(string.format("Route changed to %d", route))
        -- end
        if(player.map ~= map) then
            player.map = map
            ActorManager.cull()
        end

        -- Update Camera info.
        ActorManager.addr = mem_base + 0x23730
        local fieldsystem_addr = memory.readdword(ActorManager.addr + 0x128)
        Camera.addr = memory.readdword(fieldsystem_addr + 0x24)
        Camera.update_from_memory()
        Obstructions.update_from_memory()

        -- Keep an eye on the Player's Billboard struct to make sure it hasn't recently changed.
        local billboard_addr = memory.readdword(ActorManager.player_addr + Actor.BILLBOARD_OFFSET)
        if billboard_addr ~= ActorManager.player.billboard.addr then
            player.billboard.addr = billboard_addr
            billboard_setup()
        end
        if billboard_addr ~= 0 then
            player.billboard:update_from_memory()
        end

        -- Update party.
        if frame_counter == 0 then
            for i = 1, 6 do
                to_update[i] = true
            end
        end
        for i = 1, 6 do
            if to_update[i] then
                read_result = Pokemon.from_party_memory(i)
                if read_result then
                    player.party[i] = read_result
                    to_update[i] = false
                end
            end
        end

        -- Get the server's update on our neighbors.
        local server_update = secretary.get_neighbors()
        if server_update then
            ActorManager.update_from_secretary(server_update)
        end
    end

    -- POST to the server. 
    if should_update_player then
        secretary.update_player(player)
    end
end

function debug()
    local i = 0
    local current = player.billboard
    pcall(function() gui.text(5, 5, string.format("%d", -1)) end)
    while current.next do
        current = current.next
        i = i + 1
        local index = math.floor((current.addr - Billboard.scratch_base)/Billboard.SIZE)
        if index < 0 or index >= 102 then
            index = 102
        end
        pcall(function() gui.text(5+i*20, 5, string.format("%d", index)) end)
    end
    current = BillboardList.head

    i = 0
    pcall(function() gui.text(5, 20, string.format("%d", 0)) end)
    while current.next and current.next.addr >= 0x23c0000 do
        current = current.next
        i = i + 1
        local index = math.floor((current.addr - Billboard.scratch_base)/Billboard.SIZE)
        if index < 0 or index >= 102 then
            index = 102
        end
        pcall(function() gui.text(5+i*20, 20, string.format("%d", index)) end)
    end

    pcall(function() gui.text(5, 35, string.format("player sprite: %d", ActorManager.player.billboard.sprite)) end)

    pcall(function() gui.text(240, 182, string.format("%d", frame_counter)) end)
end

emu.registerbefore(update)

emu.registerexit(function()
    ActorManager.cull()
    if ActorManager.player.billboard.next == ActorManager.BillboardList.head then
        ActorManager.hide_billboard_list()
    end
end)

local function debug_memory()
    pcall(function() gui.text(5, 5, string.format("mem base: 0x%x", mem_base)) end)
    pcall(function() gui.text(5, 20, string.format("player base: 0x%x", ActorManager.player_addr)) end)
    pcall(function() gui.text(5, 35, string.format("player billboard: 0x%x", ActorManager.player.billboard.addr)) end)

    local menu_cursor = memory.readword(mem_base + 0x2186C)
    pcall(function() gui.text(5, 50, string.format("obstructions addr: 0x%x", Obstructions.addr)) end)
    pcall(function() gui.text(5, 65, string.format("start menu showing: %s", tostring(Obstructions.menus.start_menu.is_showing))) end)
    pcall(function() gui.text(5, 80, string.format("text box showing: %s", tostring(Obstructions.menus.text_box.is_showing))) end)
end

local function display() -- Us drawing on the screen.
    -- Display names of neighbors above their heads.
    if not in_battle and ActorManager.player.billboard.addr ~= 0 then
        for i, neighbor in pairs(ActorManager.neighbors) do
            local nametag = Text:new(neighbor.name)
            local name_coords = neighbor.billboard.pos + Pos:from_tiles({0, 2, -1})
            local display_coords = Camera.project(name_coords)
            nametag:display(display_coords[1], display_coords[2])
        end
    end
end

gui.register(function()
    display()
    debug_memory()
    -- debug()
end)