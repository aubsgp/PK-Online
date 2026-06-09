require("ObjectOrientationDay")

Pronouns = {
    [0] = {"they", "them", "their"},
    [1] = {"he", "him", "his"},
    [2] = {"she", "her", "hers"},
    [3] = {"it", "its", "its"},
    [4] = {"xe", "xem", "xyr"},
    [5] = {"e", "em", "eir"},
    [6] = {"ze", "hir", "hirs"},
    [7] = {"fae", "faer", "faers"},
    [8] = {"ey", "em", "eir"},
    [9] = {"ze", "zir", "zirs"},
    [10] = {"ae", "aer", "aers"},
    [11] = {"ve", "ver", "vis"},
    [12] = {"ne", "nem", "nir"}
}

-- In order to read the map data appropriately, we want to have players display together who are nearby in the overworld, or else in the same building/cave.
-- The tricky bit is that the overworld is split up into many different map IDs. We therefore index them here so that we can collect them together into one "overworld."
Overworld = {
    -- Cities and Towns
    [3]   = true, -- JUBILIFE_CITY
    [33]  = true, -- CANALAVE_CITY
    [45]  = true, -- OREBURGH_CITY
    [65]  = true, -- ETERNA_CITY
    [86]  = true, -- HEARTHOME_CITY
    [122] = true, -- PASTORIA_CITY
    [135] = true, -- VEILSTONE_CITY
    [152] = true, -- SUNYSHORE_CITY
    [166] = true, -- SNOWPOINT_CITY
    [190] = true, -- FIGHT_AREA
    [411] = true, -- TWINLEAF_TOWN
    [418] = true, -- SANDGEM_TOWN
    [426] = true, -- FLOAROMA_TOWN
    [433] = true, -- SOLACEON_TOWN
    [442] = true, -- CELESTIC_TOWN
    [450] = true, -- SURVIVAL_AREA
    [457] = true, -- RESORT_AREA

    -- _OUTSIDE areas (contiguous with routes)
    [200] = true, -- VALLEY_WINDWORKS_OUTSIDE
    [202] = true, -- ETERNA_FOREST_OUTSIDE
    [204] = true, -- FUEGO_IRONWORKS_OUTSIDE
    [210] = true, -- MT_CORONET_OUTSIDE_NORTH
    [211] = true, -- MT_CORONET_OUTSIDE_SOUTH
    [261] = true, -- STARK_MOUNTAIN_OUTSIDE
    [334] = true, -- VERITY_LAKEFRONT
    [336] = true, -- VALOR_LAKEFRONT
    [340] = true, -- ACUITY_LAKEFRONT

    -- Routes
    [342] = true, -- ROUTE_201
    [343] = true, -- ROUTE_202
    [344] = true, -- ROUTE_203
    [345] = true, -- ROUTE_204_SOUTH
    [346] = true, -- ROUTE_204_NORTH
    [347] = true, -- ROUTE_205_SOUTH
    [348] = true, -- ROUTE_205_NORTH
    [349] = true, -- ROUTE_206
    [353] = true, -- ROUTE_207
    [354] = true, -- ROUTE_208
    [355] = true, -- ROUTE_209
    [362] = true, -- ROUTE_210_SOUTH
    [363] = true, -- ROUTE_210_NORTH
    [364] = true, -- ROUTE_211_WEST
    [365] = true, -- ROUTE_211_EAST
    [366] = true, -- ROUTE_212_NORTH
    [371] = true, -- ROUTE_212_SOUTH
    [373] = true, -- ROUTE_213
    [380] = true, -- ROUTE_214
    [382] = true, -- ROUTE_215
    [383] = true, -- ROUTE_216
    [385] = true, -- ROUTE_217
    [388] = true, -- ROUTE_218
    [391] = true, -- ROUTE_219
    [392] = true, -- ROUTE_221
    [395] = true, -- ROUTE_222
    [399] = true, -- ROUTE_224
    [400] = true, -- ROUTE_225
    [403] = true, -- ROUTE_227
    [406] = true, -- ROUTE_228
    [407] = true, -- ROUTE_229
    [467] = true, -- ROUTE_220
    [468] = true, -- ROUTE_223
    [469] = true, -- ROUTE_226
    [471] = true, -- ROUTE_230
}