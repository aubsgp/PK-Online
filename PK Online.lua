local secretary = require("TemporalSecretary")
local pid = secretary.HANDSHAKE()
print("Handshake returned player server id: " .. pid)

local Data = require("Data")

local SpriteData = require("SpriteData")
local GfxSequence = SpriteData.GfxSequence
local BillboardAnim = SpriteData.BillboardAnim
local AnimTexture = SpriteData.AnimTexture
local VRAM = SpriteData.VRAM

local ObjectOrientationDay = require("ObjectOrientationDay")
local Pos = ObjectOrientationDay.Pos
local Billboard = ObjectOrientationDay.Billboard
local BillboardList = ObjectOrientationDay.BillboardList
local Actor = ObjectOrientationDay.Actor
local Pokemon = ObjectOrientationDay.Pokemon
local ActorManager = ObjectOrientationDay.ActorManager

local Display = require("Display")
local Camera = Display.Camera
local Obstructions = Display.Obstructions
local Text = Display.Text

local FictionalDictionary = require("FictionalDictionary")
local PRONOUNS = FictionalDictionary.PRONOUNS
local OVERWORLD = FictionalDictionary.OVERWORLD
local SPECIES = FictionalDictionary.SPECIES
local MOVES = FictionalDictionary.MOVES
local ABILITIES = FictionalDictionary.ABILITIES
local ITEMS = FictionalDictionary.ITEMS

local GDStrings = require("GDStrings")
local menu_sprites = GDStrings.menu_sprites
local gender_symbols = GDStrings.gender_symbols
local status_sprites = GDStrings.status_sprites

----------

local mem_base_pointer = memory.readdword(0x2000BA8) + 0x20 -- Although we do a read here, this value should always be fixed across sessions. The read is primarily for future-proofing against the script being ported to other romhacks.
local mem_base = nil
local save_counter_addr = nil
local num_saves = nil
local battlesystem_addr = nil
local battlecontext_addr = nil
local prev_billboard_addr = nil
local deferred_function = nil

local player = Actor:new(pid)
ActorManager.player = player

local timer = 1 -- Timer used for deferred function calls. Setting it amounts to saying "pause the script for this many frames, then run whatever our deferred_function is."" -1 means script is unpaused.
local frame_counter = 0
local in_battle = false
local in_pc_box = false
local done_wait = false
local corruption_detected = false
local player_billboard_changed = false
local default_party_order = {
    {0, 1, 2, 3, 4, 5},
    {0, 1, 2, 3, 4, 5},
    {0, 0, 0, 0, 0, 0},
    {0, 0, 0, 0, 0, 0}
}
local party_order = default_party_order
local to_update = {false, false, false, false, false, false}
local read_result = nil

----------
-- We start with some functions that we'll have to call often throughout the running of the function.

local function inject_gfx_data()
    VRAM.inject_all_sprites()
    GfxSequence:write_to_memory(0x023c8000)
    BillboardAnim:write_to_memory(0x023c9000)
    AnimTexture:write_to_memory(0x023ca000)
end
inject_gfx_data()

local failed_sanity_checks = false
local function sanity_check(addr)
    if addr < 0x02000000 or addr >= 0x02400000 then
        return false
    end
    return true
end

local function update_name()
    local namedata = Data:new(mem_base + 0x7c, 20)
    player.name = namedata:readstring(0)
end

local function get_party_addrs()
    Pokemon.party_addr = mem_base + 0xb4
    battlesystem_addr = mem_base + 0x417fc
    battlecontext_addr = memory.readdword(battlesystem_addr + 0x30)
    if sanity_check(battlecontext_addr) then
        Pokemon.battle_addr = battlecontext_addr + 0x2d40
        return true
    end
    return false
end

local function get_actor_manager_addrs()
    ActorManager.addr = mem_base + 0x23730
    local player_addr_read = memory.readdword(ActorManager.addr + 0x124)
    if sanity_check(player_addr_read) then
        ActorManager.player_addr = player_addr_read
        return true
    end
    return false
end

local function get_graphics_addrs()
    Obstructions.addr = mem_base + 0x217A8
    local fieldsystem_addr = memory.readdword(ActorManager.addr + 0x128)
    if sanity_check(fieldsystem_addr) then
        Camera.addr = memory.readdword(fieldsystem_addr + 0x24)
        if sanity_check(Camera.addr) then
             return true
        end
    end
    return false
end

local function get_addresses()
    mem_base = memory.readdword(mem_base_pointer)
    if not get_party_addrs() or not get_actor_manager_addrs() or not get_graphics_addrs() then
        if not failed_sanity_checks then
            print("Warning: failed one or more sanity checks when grabbing addresses. This is normal when changing maps. Will keep attempting until successful.")
        end
        failed_sanity_checks = true
        return false
    else
        if failed_sanity_checks then
            print("Successfully passed sanity checks on a subsequent attempt.")
        end
        failed_sanity_checks = false
        return true
    end
end

while not get_addresses() do
    emu.frameadvance()
end

----------

-- We now set up the billboards for the player and all the potential neighbors.
-- First, we need to grab the player billboard. We won't proceed until we have done so.
local player_billboard_addr = memory.readdword(ActorManager.player_addr + Actor.BILLBOARD_OFFSET)
if not Billboard.sanity_check(player_billboard_addr) then
    print("Waiting for valid player billboard address...")
    while not Billboard.sanity_check(player_billboard_addr) do
        emu.frameadvance()
        player_billboard_addr = memory.readdword(ActorManager.player_addr + Actor.BILLBOARD_OFFSET)
    end
    print("Obtained valid player billboard address: " .. string.format("0x%x", player_billboard_addr))
end
player.billboard = Billboard.from_memory(player_billboard_addr)
BillboardList.addr = memory.readdword(player_billboard_addr + 0x28)

-- Set the template for all neighbor billboards.
local billboard_template = Data:new(ActorManager.player.billboard.addr + Billboard.SIZE, Billboard.SIZE) 
billboard_template:writedwordrange(Billboard.POS_OFFSET, {0, 0, 0})
BillboardList.update_template(billboard_template)

-- Fixed "anchor" billboards make insertion and removal of the whole neighbor billboard list very painless.
BillboardList.head = Billboard.from_memory(Billboard.scratch_base)
BillboardList.tail = Billboard.from_memory(Billboard.scratch_base + 101*Billboard.SIZE)
BillboardList.head:set_next(BillboardList.tail)
BillboardList.tail:set_prev(BillboardList.head)

local function billboard_setup()
    local player_billboard_addr = memory.readdword(ActorManager.player_addr + Actor.BILLBOARD_OFFSET)
    if not sanity_check(player_billboard_addr) then
        timer = 1
        return
    end
    local x_coord = memory.readdword(player_billboard_addr + Billboard.POS_OFFSET)
    if x_coord == 0 then
        timer = 1
        return
    end
    if not Billboard.trace_loop(player_billboard_addr) then
        timer = 1
        return
    end
    if not done_wait then
        timer = 10
        done_wait = true
        return
    end
    print("Setting up billboards with player billboard address: " .. string.format("0x%x", player_billboard_addr))
    ActorManager.update_billboard_list()
    timer = -1
    done_wait = false
end
while timer >= 0 do
    timer = timer - 1
    emu.frameadvance()
    if timer == 0 then
        billboard_setup()
    end
end

-- The game checks if the billboard list is active only when its about to delete it. So we watch for that and hide our insertions whenever that happens to prevent corruption curing cleanup.
memory.registerread(BillboardList.addr, 1, function()
    if player.billboard.addr == 0 and (BillboardList.head.prev or BillboardList.tail.next) then
        error("WARNING NIGHTMARE NIGHTMARE NIGHTMARE")
    end
    ActorManager.hide_billboard_list()
end)

----------


-- Relevant pokeplatinum github pages: https://github.com/pret/pokeplatinum/blob/main/include/battle/battle_mon.h, https://github.com/pret/pokeplatinum/blob/main/include/battle/battle_context.h
-- Each in-battle Pokemon's battle state is stored as an unencrypted BattleMon struct, which is 0xb4 (=180) bytes long. This includes, for instance, stats, current HP, moves, and so on.
-- The battle context struct includes in-place an array of 4 BattleMon structs, 2 for each side. 
--      - In a double battle, the first two are yours and the second two are the opponent's. (In a tag battle, the second is your partner's.)
--      - In a single battle, the first one is yours and the second one is the opponent's, and the other two are just zeroed out.
-- The tricky bit here is that Pokemon not currently out seem to be encrypted, and its nontrivial to figure out both where and with what key. As such, we use a bit of a workaround:
-- We just track which Pokemon is currently out each turn, and use this to know who to update each frame. This is stored x11c (=284) bytes after the end of the BattleMon array.
-- This means if a Pokemon in the back levels up, we won't know until the next time it is sent out, or once the battle ends. Otherwise, this should be accurate.
local function in_battle_update()
    -- Check if we are in a double battle, and not a single or tag battle.
    local is_double_battle = false
    if memory.readbyte(battlesystem_addr + 0x2c) == 2 then -- See https://github.com/pret/pokeplatinum/blob/main/include/constants/battle.h#L24
        is_double_battle = true
    end

    -- Get the party order for each side. The first (and second, if it's a double battle) pokemon on each side is the one currently out.
    local party_order_read = {}
    for i = 1, 4 do
        local party_order_offset = 4*0xb4 + 0x11c + (i-1)*6
        party_order_read[i] = memory.readbyterange(Pokemon.battle_addr + party_order_offset, 6) -- The party order of the ith participant in battle, as a permutation of the party order going in. The first byte is the currently-out mon. 
        -- TODO: double-check this actually works for double battles!!!!!
    end
    if not Data.deep_compare(party_order_read, {{0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0, 0}}) then
        for i = 1, 4 do
            for j = 1, 6 do
                if not (party_order_read[i][j] >= 0 and party_order_read[i][j] < 6) then
                    return
                end
            end
        end
        if not Data.deep_compare(party_order_read, party_order) then
            party_order = party_order_read
            timer = 300
            return
        end
    end

    local currently_out = {party_order[1][1] + 1, party_order[1][2] + 1}
    read_result = Pokemon.from_battle_memory(1)
    if read_result and player.party[currently_out[1]].curr_hp ~= 0 then
        player.party[currently_out[1]] = read_result
    end
    if is_double_battle then
        read_result = Pokemon.from_battle_memory(2)
        if read_result and player.party[currently_out[2]].curr_hp ~= 0 then
            player.party[currently_out[2]] = read_result
        end
    end
end

local function overworld_update()
    -- Update graphical info.
    update_name()
    Camera.update_from_memory()
    Obstructions.update_from_memory()
    local map = memory.readdword(mem_base + 0x1294)
    if OVERWORLD[map] then
        player.map = 0
    else
        player.map = map
    end

    -- Keep an eye on the Player's Billboard struct to make sure it hasn't recently changed, i.e. getting on a bike or using the poketch.
    local billboard_addr = memory.readdword(ActorManager.player_addr + Actor.BILLBOARD_OFFSET)
    if billboard_addr == 0 then
        if not player_billboard_changed then
            prev_billboard_addr = player.billboard.addr
            player.billboard.addr = billboard_addr
            player_billboard_changed = true
            return
        end
    else
        player.billboard.addr = billboard_addr
        player.billboard:update_from_memory()
        if player_billboard_changed then
            if Billboard.trace_loop(player.billboard.addr) then
                player_billboard_changed = false
                if player.billboard.addr ~= prev_billboard_addr then
                    print("Player billboard address changed from " .. string.format("0x%x", prev_billboard_addr) .. " to " .. string.format("0x%x", player.billboard.addr))
                    local bbl_addr_read = memory.readdword(player.billboard.addr + 0x28)
                    if bbl_addr_read ~= BillboardList.addr then
                        memory.registerread(BillboardList.addr, 1, nil) -- unregister the old function, since the old address is no longer relevant.
                        print("Player billboard's billboard list address changed from " .. string.format("0x%x", BillboardList.addr) .. " to " .. string.format("0x%x", bbl_addr_read))
                        BillboardList.addr = bbl_addr_read
                        memory.registerread(BillboardList.addr, 1, function()
                            ActorManager.hide_billboard_list()
                        end)
                    end
                    deferred_function = billboard_setup
                else
                    deferred_function = ActorManager.show_billboard_list
                end
                timer = 20
            end
            return
        end
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

    -- Check for memory corruption. This is neither comprehensive nor fully accurate, but it's a good warning point.
    local free_billboards_addr = memory.readdword(BillboardList.addr + Billboard.SIZE + 0x0c)
    if sanity_check(free_billboards_addr) then
        local free_billboards = Data:new(free_billboards_addr, 0x40*0x04)
        for i = 1, 0x40 do
            local offset = (i-1)*0x04
            local addr = free_billboards:readdword(offset)
            if addr ~= 0 and ((addr >= 0x023c0000 and addr <= 0x023c4d54) or (addr < 0x02200000 or addr >= 0x02400000)) then
                corruption_detected = true
                print(string.format("0x%x, 0x%x", free_billboards_addr, addr))
            end
        end
    end

    -- Get the server's update on our neighbors.
    local server_update = secretary.get_neighbors()
    if server_update then
        ActorManager.update_from_secretary(server_update)
    end
end

local function update()
    if not get_addresses() then
        return
    end
    -- Keep track of timer nonsense. We don't go past this block if the timer is nonzero.
    if timer == 0 then
        if deferred_function then
            deferred_function()
            if timer <= 0 then -- Some functions will say "go again" and set the timer to a positive value. In that case, we want to keep the function on the stack. But if it says we're done, we want to pop it.
                deferred_function = nil
            end
        end
    end
    if timer >= 0 then
        timer = timer - 1
        return
    end
    frame_counter = (frame_counter+1)%60

    -- Update our knowledge of if we are in battle.
    if memory.readbyte(0x02197910) == 1 then
        if not in_battle then
            in_battle = true
            timer = 1000 -- To prevent us from reading garbage when we enter battle, we set a very generous timer of 1000 frames to give the game some time to get its affairs in order.
            return
        end
    else
        if in_battle then
            in_battle = false
            deferred_function = function()
                party_order = default_party_order
                inject_gfx_data()
                billboard_setup()
            end
            timer = 20
            return
        end
    end

    -- Update our knowledge of the player/party and pass that info to our secretary dll.
    if in_battle then
        in_battle_update()
    else
        overworld_update()
    end

    local temp = player:copy()
    for i = 1, 6 do
        local index = party_order[1][i] + 1
        if(player.party[index]) then
            temp.party[i] = player.party[index]:copy()
        end
    end
    secretary.update_player(temp)
end

emu.registerbefore(update)

emu.registerexit(function()
    ActorManager.cull()
    if ActorManager.player.billboard.next == ActorManager.BillboardList.head then
        ActorManager.hide_billboard_list()
    end
end)



local function debug_gfx()
    -- Display the billboard linked list from player (-1) to head (0) to neighbors (1-100) to tail (101) to whatever originally came after the player (102).
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

    -- Ditto, but ignoring the player and the post-player billboards, for when the billboard list is hidden from the game.
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
    pcall(function() gui.text(5, 50, string.format("start menu showing: %s", tostring(Obstructions.menus.start_menu.is_showing))) end)
    pcall(function() gui.text(5, 65, string.format("text box showing: %s", tostring(Obstructions.menus.text_box.is_showing))) end)
    pcall(function() gui.text(5, 80, string.format("in battle: %s", tostring(in_battle))) end)

    pcall(function() gui.text(240, 182, string.format("%d", frame_counter)) end)
end

local function debug_memory()
    pcall(function() gui.text(5, 5, string.format("mem base: 0x%x", mem_base)) end)
    pcall(function() gui.text(5, 20, string.format("player base: 0x%x", ActorManager.player_addr)) end)
    pcall(function() gui.text(5, 35, string.format("player billboard: 0x%x", ActorManager.player.billboard.addr)) end)

    -- local menu_cursor = memory.readword(mem_base + 0x2186C)
    pcall(function() gui.text(5, 65, string.format("obstructions addr: 0x%x", Obstructions.addr)) end)
end

function gui.drawcircle(x, y, radius, color)
    local pixels = {}
    for i = 0, 90, 5 do
        local radian = math.rad(i)
        local x_offset = math.floor(radius*math.cos(radian))
        local y_offset = math.floor(radius*math.sin(radian))
        pixels[{x_offset, y_offset}] = true
    end
    for coords, _ in pairs(pixels) do
        gui.pixel(x + coords[1], y + coords[2], color)
        gui.pixel(x - coords[1], y + coords[2], color)
        gui.pixel(x + coords[1], y - coords[2], color)
        gui.pixel(x - coords[1], y - coords[2], color)
    end
end

local function draw_poison_bubble(x, y, radius)
    local purple = 0xd000d0b0
    gui.drawcircle(x, y, radius + 1, 0xffffffb0)
    gui.drawcircle(x, y, radius, purple)
    gui.drawcircle(x, y, radius - 1, 0xffffffb0)
    gui.pixel(x - radius + 2, y, purple - 0x00000040)
    gui.pixel(x - radius + 3, y + 1, purple - 0x00000040)
end

local function draw_paralysis_carat(x, y, orientation)
    if orientation%2 == 0 then
        gui.line(x, y, x + 3, y - 3, 0xffff00ff)
        gui.line(x + 3, y - 3, x, y - 6, 0xffff00ff)
    else
        gui.line(x, y, x - 3, y - 3, 0xffff00ff)
        gui.line(x - 3, y - 3, x, y - 6, 0xffff00ff)
    end
end

local function display_neighbor_party(x, y, neighbor)
    local WIDTH = 138
    local HEIGHT = 155
    gui.drawbox(x, y, x + WIDTH, y + HEIGHT, 0xfffffff0, 0x00000000)
    gui.drawline(x + 2, y, x + WIDTH - 2, y, 0x000000ff)
    gui.drawline(x + WIDTH - 2, y, x + WIDTH, y + 2, 0x000000ff)
    gui.drawline(x + WIDTH, y + 2, x + WIDTH, y + HEIGHT - 2, 0x000000ff)
    gui.drawline(x + WIDTH, y + HEIGHT - 2, x + WIDTH - 2, y + HEIGHT, 0x000000ff)
    gui.drawline(x + WIDTH - 2, y + HEIGHT, x + 2, y + HEIGHT, 0x000000ff)
    gui.drawline(x + 2, y + HEIGHT, x, y + HEIGHT - 2, 0x000000ff)
    gui.drawline(x, y + HEIGHT - 2, x, y + 2, 0x000000ff)
    gui.drawline(x, y + 2, x + 2, y, 0x000000ff)
    
    for i = 1, 6 do
        local mon = neighbor.party[i]
        if mon then
            local y_offset = (i-1)*25

            local anim_speed = 1
            if secretary.band(mon.status, 0x27) ~= 0 or mon.curr_hp == 0 then -- 0b00100111, Sleep, Freeze, and Faint.
                anim_speed = 0
            elseif secretary.band(mon.status, 0x40) ~= 0 then -- 0b01000000, Paralysis
                anim_speed = 0.25
            elseif mon.status ~= 0 then -- 0b10001000, Poison, Toxic, and Burn.
                anim_speed = 0.5
            end
            local frame = math.floor(frame_counter*anim_speed/8)%2
            gui.gdoverlay(x, y + y_offset - 5, menu_sprites.get_sprite(mon, frame))

            if mon.curr_hp ~= 0 then
                frame = math.floor(frame_counter / 15)
                if secretary.band(mon.status, 0x07) ~= 0 and frame ~= 0  then -- 0b00000111, Sleep
                    local offsets = {
                        {0, 4},
                        {5, 1},
                        {10, 0}
                    }
                    gui.text(x + 15 + offsets[frame][1], y + y_offset + offsets[frame][2], "z")
                
                elseif secretary.band(mon.status, 0x88) ~= 0 and frame ~= 0 then -- 0b10001000, Poison and Toxic.
                    if frame == 1 then
                        draw_poison_bubble(x + 20, y + y_offset + 9, 3)
                    elseif frame == 2 then
                        draw_poison_bubble(x + 7, y + y_offset + 6, 2)
                    elseif frame == 3 then
                        draw_poison_bubble(x + 14, y + y_offset + 3, 3)
                    end
                
                elseif secretary.band(mon.status, 0x10) ~= 0 and frame ~= 0 then -- 0b00010000, Burn
                    gui.gdoverlay(x + 4, y + y_offset + 16, status_sprites.burn[frame])

                elseif secretary.band(mon.status, 0x20) ~= 0 then -- 0b00100000, Freeze
                    if math.floor(frame_counter / 6) <= 4 then
                        gui.gdoverlay(x + 10, y + y_offset + 10, status_sprites.sparkle[math.floor(frame_counter / 6) + 1])
                    end

                elseif secretary.band(mon.status, 0x40) ~= 0 and frame ~= 0 then -- 0b01000000, Paralysis
                    if frame == 1 then
                        draw_paralysis_carat(x + 10, y + y_offset + 10, 0)
                        draw_paralysis_carat(x + 10, y + y_offset + 16, 1)

                        draw_paralysis_carat(x + 20, y + y_offset + 20, 1)
                        draw_paralysis_carat(x + 20, y + y_offset + 26, 0)
                    elseif frame == 2 then
                        draw_paralysis_carat(x + 15, y + y_offset + 10, 1)
                        draw_paralysis_carat(x + 15, y + y_offset + 16, 0)
                    elseif frame == 3 then
                        draw_paralysis_carat(x + 5, y + y_offset + 12, 1)
                        draw_paralysis_carat(x + 5, y + y_offset + 18, 0)
                    end
                end
            end

            gui.text(x + 31, y + y_offset + 7, "l")
            gui.text(x + 35, y + y_offset + 7, "v")
            pcall(function() gui.text(x + 42, y + y_offset + 7, string.format("%d", mon.level)) end)
            pcall(function() gui.text(x + 63, y + y_offset + 7, Data.encode_string(mon.name)) end)
            if mon.gender < 2 then
                gui.gdoverlay(x + 125, y + y_offset + 6, gender_symbols[mon.gender + 1])
            end
            
            -- HP Bars. The color changes based on how much HP is left.
            local color = 0x00ff00ff
            local hp_ratio = mon.curr_hp/mon.stats[1]
            if math.floor(48*hp_ratio)/48 <= 0.2 then
                color = 0xff0000ff
            elseif math.floor(48*hp_ratio)/48 <= 0.5 then
                color = 0xffff00ff
            end
            gui.drawline(x + 31, y + y_offset + 17, x + 31, y + y_offset + 22, 0x000000ff)
            gui.drawline(x + 32, y + y_offset + 17, x + 32, y + y_offset + 21, 0x000000ff)
            gui.drawline(x + 33, y + y_offset + 20, x + 36, y + y_offset + 20, 0x000000ff)
            gui.drawline(x + 37, y + y_offset + 20, x + 38, y + y_offset + 20, 0x00000080)
            gui.drawbox(x + 32, y + y_offset + 17, x + 32 + 100, y + y_offset + 19, 0xffffffff, 0x000000ff)
            gui.drawbox(x + 32, y + y_offset + 17, x + 32 + 100*hp_ratio, y + y_offset + 19, color, 0x000000ff)
            gui.drawline(x + 32 + 101, y + y_offset + 17, x + 32 + 101, y + y_offset + 19, 0x000000ff)
        end
    end
end

local function display() -- Us drawing on the screen.
    -- Display names of neighbors above their heads.
    if not in_battle and ActorManager.player.billboard.addr ~= 0 and not player_billboard_changed then
        for i, neighbor in pairs(ActorManager.neighbors) do
            local nametag = Text:new(Data.encode_string(neighbor.name))
            local name_coords = neighbor.billboard.pos + Pos:from_tiles({0, 2, -1})
            local display_coords = Camera.project(name_coords)
            nametag:display(display_coords[1], display_coords[2])
        end
    end

    if(joypad.get(1)["R"]) then
        debug_memory()
    elseif joypad.get(1)["L"] then
        debug_gfx()
    end

    if(joypad.get(1)["A"]) and not Obstructions.menus.start_menu.is_showing and not Obstructions.menus.text_box.is_showing then
        local looking_at = ActorManager:player_looking_at()
        local neighbor = looking_at[1]
        if neighbor then
            display_neighbor_party(2, -190, neighbor)
        end
    end

    if(corruption_detected) then
        pcall(function() gui.text(5, 100, "Potential memory corruption detected!") end)
        pcall(function() gui.text(5, 115, "Savestate and send it to Aubs.") end)
    end
end

gui.register(display)