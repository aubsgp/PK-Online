local PRONOUNS = {
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
local OVERWORLD = {
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

local SPECIES = {
    {"None"},  -- 0 - placeholder
    {"Bulbasaur"},  -- 1
    {"Ivysaur"},  -- 2
    {"Venusaur"},  -- 3
    {"Charmander"},  -- 4
    {"Charmeleon"},  -- 5
    {"Charizard"},  -- 6
    {"Squirtle"},  -- 7
    {"Wartortle"},  -- 8
    {"Blastoise"},  -- 9
    {"Caterpie"},  -- 10
    {"Metapod"},  -- 11
    {"Butterfree"},  -- 12
    {"Weedle"},  -- 13
    {"Kakuna"},  -- 14
    {"Beedrill"},  -- 15
    {"Pidgey"},  -- 16
    {"Pidgeotto"},  -- 17
    {"Pidgeot"},  -- 18
    {"Rattata"},  -- 19
    {"Raticate"},  -- 20
    {"Spearow"},  -- 21
    {"Fearow"},  -- 22
    {"Ekans"},  -- 23
    {"Arbok"},  -- 24
    {"Pikachu"},  -- 25
    {"Raichu"},  -- 26
    {"Sandshrew"},  -- 27
    {"Sandslash"},  -- 28
    {"Nidoran♀"},  -- 29
    {"Nidorina"},  -- 30
    {"Nidoqueen"},  -- 31
    {"Nidoran♂"},  -- 32
    {"Nidorino"},  -- 33
    {"Nidoking"},  -- 34
    {"Clefairy"},  -- 35
    {"Clefable"},  -- 36
    {"Vulpix"},  -- 37
    {"Ninetales"},  -- 38
    {"Jigglypuff"},  -- 39
    {"Wigglytuff"},  -- 40
    {"Zubat"},  -- 41
    {"Golbat"},  -- 42
    {"Oddish"},  -- 43
    {"Gloom"},  -- 44
    {"Vileplume"},  -- 45
    {"Paras"},  -- 46
    {"Parasect"},  -- 47
    {"Venonat"},  -- 48
    {"Venomoth"},  -- 49
    {"Diglett"},  -- 50
    {"Dugtrio"},  -- 51
    {"Meowth"},  -- 52
    {"Persian"},  -- 53
    {"Psyduck"},  -- 54
    {"Golduck"},  -- 55
    {"Mankey"},  -- 56
    {"Primeape"},  -- 57
    {"Growlithe"},  -- 58
    {"Arcanine"},  -- 59
    {"Poliwag"},  -- 60
    {"Poliwhirl"},  -- 61
    {"Poliwrath"},  -- 62
    {"Abra"},  -- 63
    {"Kadabra"},  -- 64
    {"Alakazam"},  -- 65
    {"Machop"},  -- 66
    {"Machoke"},  -- 67
    {"Machamp"},  -- 68
    {"Bellsprout"},  -- 69
    {"Weepinbell"},  -- 70
    {"Victreebel"},  -- 71
    {"Tentacool"},  -- 72
    {"Tentacruel"},  -- 73
    {"Geodude"},  -- 74
    {"Graveler"},  -- 75
    {"Golem"},  -- 76
    {"Ponyta"},  -- 77
    {"Rapidash"},  -- 78
    {"Slowpoke"},  -- 79
    {"Slowbro"},  -- 80
    {"Magnemite"},  -- 81
    {"Magneton"},  -- 82
    {"Farfetch'd"},  -- 83
    {"Doduo"},  -- 84
    {"Dodrio"},  -- 85
    {"Seel"},  -- 86
    {"Dewgong"},  -- 87
    {"Grimer"},  -- 88
    {"Muk"},  -- 89
    {"Shellder"},  -- 90
    {"Cloyster"},  -- 91
    {"Gastly"},  -- 92
    {"Haunter"},  -- 93
    {"Gengar"},  -- 94
    {"Onix"},  -- 95
    {"Drowzee"},  -- 96
    {"Hypno"},  -- 97
    {"Krabby"},  -- 98
    {"Kingler"},  -- 99
    {"Voltorb"},  -- 100
    {"Electrode"},  -- 101
    {"Exeggcute"},  -- 102
    {"Exeggutor"},  -- 103
    {"Cubone"},  -- 104
    {"Marowak"},  -- 105
    {"Hitmonlee"},  -- 106
    {"Hitmonchan"},  -- 107
    {"Lickitung"},  -- 108
    {"Koffing"},  -- 109
    {"Weezing"},  -- 110
    {"Rhyhorn"},  -- 111
    {"Rhydon"},  -- 112
    {"Chansey"},  -- 113
    {"Tangela"},  -- 114
    {"Kangaskhan"},  -- 115
    {"Horsea"},  -- 116
    {"Seadra"},  -- 117
    {"Goldeen"},  -- 118
    {"Seaking"},  -- 119
    {"Staryu"},  -- 120
    {"Starmie"},  -- 121
    {"Mr. Mime"},  -- 122
    {"Scyther"},  -- 123
    {"Jynx"},  -- 124
    {"Electabuzz"},  -- 125
    {"Magmar"},  -- 126
    {"Pinsir"},  -- 127
    {"Tauros"},  -- 128
    {"Magikarp"},  -- 129
    {"Gyarados"},  -- 130
    {"Lapras"},  -- 131
    {"Ditto"},  -- 132
    {"Eevee"},  -- 133
    {"Vaporeon"},  -- 134
    {"Jolteon"},  -- 135
    {"Flareon"},  -- 136
    {"Porygon"},  -- 137
    {"Omanyte"},  -- 138
    {"Omastar"},  -- 139
    {"Kabuto"},  -- 140
    {"Kabutops"},  -- 141
    {"Aerodactyl"},  -- 142
    {"Snorlax"},  -- 143
    {"Articuno"},  -- 144
    {"Zapdos"},  -- 145
    {"Moltres"},  -- 146
    {"Dratini"},  -- 147
    {"Dragonair"},  -- 148
    {"Dragonite"},  -- 149
    {"Mewtwo"},  -- 150
    {"Mew"},  -- 151
    {"Chikorita"},  -- 152
    {"Bayleef"},  -- 153
    {"Meganium"},  -- 154
    {"Cyndaquil"},  -- 155
    {"Quilava"},  -- 156
    {"Typhlosion"},  -- 157
    {"Totodile"},  -- 158
    {"Croconaw"},  -- 159
    {"Feraligatr"},  -- 160
    {"Sentret"},  -- 161
    {"Furret"},  -- 162
    {"Hoothoot"},  -- 163
    {"Noctowl"},  -- 164
    {"Ledyba"},  -- 165
    {"Ledian"},  -- 166
    {"Spinarak"},  -- 167
    {"Ariados"},  -- 168
    {"Crobat"},  -- 169
    {"Chinchou"},  -- 170
    {"Lanturn"},  -- 171
    {"Pichu"},  -- 172
    {"Cleffa"},  -- 173
    {"Igglybuff"},  -- 174
    {"Togepi"},  -- 175
    {"Togetic"},  -- 176
    {"Natu"},  -- 177
    {"Xatu"},  -- 178
    {"Mareep"},  -- 179
    {"Flaaffy"},  -- 180
    {"Ampharos"},  -- 181
    {"Bellossom"},  -- 182
    {"Marill"},  -- 183
    {"Azumarill"},  -- 184
    {"Sudowoodo"},  -- 185
    {"Politoed"},  -- 186
    {"Hoppip"},  -- 187
    {"Skiploom"},  -- 188
    {"Jumpluff"},  -- 189
    {"Aipom"},  -- 190
    {"Sunkern"},  -- 191
    {"Sunflora"},  -- 192
    {"Yanma"},  -- 193
    {"Wooper"},  -- 194
    {"Quagsire"},  -- 195
    {"Espeon"},  -- 196
    {"Umbreon"},  -- 197
    {"Murkrow"},  -- 198
    {"Slowking"},  -- 199
    {"Misdreavus"},  -- 200
    {"Unown A", "Unown B", "Unown C", "Unown D", "Unown E", "Unown F", "Unown G", "Unown H", "Unown I", "Unown J", "Unown K", "Unown L", "Unown M", "Unown N", "Unown O", "Unown P", "Unown Q", "Unown R", "Unown S", "Unown T", "Unown U", "Unown V", "Unown W", "Unown X", "Unown Y", "Unown Z", "Unown !", "Unown ?"},  -- 201,  -- 201
    {"Wobbuffet"},  -- 202
    {"Girafarig"},  -- 203
    {"Pineco"},  -- 204
    {"Forretress"},  -- 205
    {"Dunsparce"},  -- 206
    {"Gligar"},  -- 207
    {"Steelix"},  -- 208
    {"Snubbull"},  -- 209
    {"Granbull"},  -- 210
    {"Qwilfish"},  -- 211
    {"Scizor"},  -- 212
    {"Shuckle"},  -- 213
    {"Heracross"},  -- 214
    {"Sneasel"},  -- 215
    {"Teddiursa"},  -- 216
    {"Ursaring"},  -- 217
    {"Slugma"},  -- 218
    {"Magcargo"},  -- 219
    {"Swinub"},  -- 220
    {"Piloswine"},  -- 221
    {"Corsola"},  -- 222
    {"Remoraid"},  -- 223
    {"Octillery"},  -- 224
    {"Delibird"},  -- 225
    {"Mantine"},  -- 226
    {"Skarmory"},  -- 227
    {"Houndour"},  -- 228
    {"Houndoom"},  -- 229
    {"Kingdra"},  -- 230
    {"Phanpy"},  -- 231
    {"Donphan"},  -- 232
    {"Porygon2"},  -- 233
    {"Stantler"},  -- 234
    {"Smeargle"},  -- 235
    {"Tyrogue"},  -- 236
    {"Hitmontop"},  -- 237
    {"Smoochum"},  -- 238
    {"Elekid"},  -- 239
    {"Magby"},  -- 240
    {"Miltank"},  -- 241
    {"Blissey"},  -- 242
    {"Raikou"},  -- 243
    {"Entei"},  -- 244
    {"Suicune"},  -- 245
    {"Larvitar"},  -- 246
    {"Pupitar"},  -- 247
    {"Tyranitar"},  -- 248
    {"Lugia"},  -- 249
    {"Ho-Oh"},  -- 250
    {"Celebi"},  -- 251
    {"Treecko"},  -- 252
    {"Grovyle"},  -- 253
    {"Sceptile"},  -- 254
    {"Torchic"},  -- 255
    {"Combusken"},  -- 256
    {"Blaziken"},  -- 257
    {"Mudkip"},  -- 258
    {"Marshtomp"},  -- 259
    {"Swampert"},  -- 260
    {"Poochyena"},  -- 261
    {"Mightyena"},  -- 262
    {"Zigzagoon"},  -- 263
    {"Linoone"},  -- 264
    {"Wurmple"},  -- 265
    {"Silcoon"},  -- 266
    {"Beautifly"},  -- 267
    {"Cascoon"},  -- 268
    {"Dustox"},  -- 269
    {"Lotad"},  -- 270
    {"Lombre"},  -- 271
    {"Ludicolo"},  -- 272
    {"Seedot"},  -- 273
    {"Nuzleaf"},  -- 274
    {"Shiftry"},  -- 275
    {"Taillow"},  -- 276
    {"Swellow"},  -- 277
    {"Wingull"},  -- 278
    {"Pelipper"},  -- 279
    {"Ralts"},  -- 280
    {"Kirlia"},  -- 281
    {"Gardevoir"},  -- 282
    {"Surskit"},  -- 283
    {"Masquerain"},  -- 284
    {"Shroomish"},  -- 285
    {"Breloom"},  -- 286
    {"Slakoth"},  -- 287
    {"Vigoroth"},  -- 288
    {"Slaking"},  -- 289
    {"Nincada"},  -- 290
    {"Ninjask"},  -- 291
    {"Shedinja"},  -- 292
    {"Whismur"},  -- 293
    {"Loudred"},  -- 294
    {"Exploud"},  -- 295
    {"Makuhita"},  -- 296
    {"Hariyama"},  -- 297
    {"Azurill"},  -- 298
    {"Nosepass"},  -- 299
    {"Skitty"},  -- 300
    {"Delcatty"},  -- 301
    {"Sableye"},  -- 302
    {"Mawile"},  -- 303
    {"Aron"},  -- 304
    {"Lairon"},  -- 305
    {"Aggron"},  -- 306
    {"Meditite"},  -- 307
    {"Medicham"},  -- 308
    {"Electrike"},  -- 309
    {"Manectric"},  -- 310
    {"Plusle"},  -- 311
    {"Minun"},  -- 312
    {"Volbeat"},  -- 313
    {"Illumise"},  -- 314
    {"Roselia"},  -- 315
    {"Gulpin"},  -- 316
    {"Swalot"},  -- 317
    {"Carvanha"},  -- 318
    {"Sharpedo"},  -- 319
    {"Wailmer"},  -- 320
    {"Wailord"},  -- 321
    {"Numel"},  -- 322
    {"Camerupt"},  -- 323
    {"Torkoal"},  -- 324
    {"Spoink"},  -- 325
    {"Grumpig"},  -- 326
    {"Spinda"},  -- 327
    {"Trapinch"},  -- 328
    {"Vibrava"},  -- 329
    {"Flygon"},  -- 330
    {"Cacnea"},  -- 331
    {"Cacturne"},  -- 332
    {"Swablu"},  -- 333
    {"Altaria"},  -- 334
    {"Zangoose"},  -- 335
    {"Seviper"},  -- 336
    {"Lunatone"},  -- 337
    {"Solrock"},  -- 338
    {"Barboach"},  -- 339
    {"Whiscash"},  -- 340
    {"Corphish"},  -- 341
    {"Crawdaunt"},  -- 342
    {"Baltoy"},  -- 343
    {"Claydol"},  -- 344
    {"Lileep"},  -- 345
    {"Cradily"},  -- 346
    {"Anorith"},  -- 347
    {"Armaldo"},  -- 348
    {"Feebas"},  -- 349
    {"Milotic"},  -- 350
    {"Castform", "Castform Sunny Form", "Castform Rainy Form", "Castform Snowy Form"},  -- 351
    {"Kecleon"},  -- 352
    {"Shuppet"},  -- 353
    {"Banette"},  -- 354
    {"Duskull"},  -- 355
    {"Dusclops"},  -- 356
    {"Tropius"},  -- 357
    {"Chimecho"},  -- 358
    {"Absol"},  -- 359
    {"Wynaut"},  -- 360
    {"Snorunt"},  -- 361
    {"Glalie"},  -- 362
    {"Spheal"},  -- 363
    {"Sealeo"},  -- 364
    {"Walrein"},  -- 365
    {"Clamperl"},  -- 366
    {"Huntail"},  -- 367
    {"Gorebyss"},  -- 368
    {"Relicanth"},  -- 369
    {"Luvdisc"},  -- 370
    {"Bagon"},  -- 371
    {"Shelgon"},  -- 372
    {"Salamence"},  -- 373
    {"Beldum"},  -- 374
    {"Metang"},  -- 375
    {"Metagross"},  -- 376
    {"Regirock"},  -- 377
    {"Regice"},  -- 378
    {"Registeel"},  -- 379
    {"Latias"},  -- 380
    {"Latios"},  -- 381
    {"Kyogre"},  -- 382
    {"Groudon"},  -- 383
    {"Rayquaza"},  -- 384
    {"Jirachi"},  -- 385
    {"Deoxys", "Deoxys Attack Forme", "Deoxys Defense Forme", "Deoxys Speed Forme"},  -- 386
    {"Turtwig"},  -- 387
    {"Grotle"},  -- 388
    {"Torterra"},  -- 389
    {"Chimchar"},  -- 390
    {"Monferno"},  -- 391
    {"Infernape"},  -- 392
    {"Piplup"},  -- 393
    {"Prinplup"},  -- 394
    {"Empoleon"},  -- 395
    {"Starly"},  -- 396
    {"Staravia"},  -- 397
    {"Staraptor"},  -- 398
    {"Bidoof"},  -- 399
    {"Bibarel"},  -- 400
    {"Kricketot"},  -- 401
    {"Kricketune"},  -- 402
    {"Shinx"},  -- 403
    {"Luxio"},  -- 404
    {"Luxray"},  -- 405
    {"Budew"},  -- 406
    {"Roserade"},  -- 407
    {"Cranidos"},  -- 408
    {"Rampardos"},  -- 409
    {"Shieldon"},  -- 410
    {"Bastiodon"},  -- 411
    {"Burmy Plant Cloak", "Burmy Sandy Cloak", "Burmy Trash Cloak"},  -- 412
    {"Wormadam Plant Cloak", "Wormadam Sandy Cloak", "Wormadam Trash Cloak"},  -- 413
    {"Mothim"},  -- 414
    {"Combee"},  -- 415
    {"Vespiquen"},  -- 416
    {"Pachirisu"},  -- 417
    {"Buizel"},  -- 418
    {"Floatzel"},  -- 419
    {"Cherubi"},  -- 420
    {"Cherrim Overcast Form", "Cherrim Sunshine Form"},  -- 421
    {"Shellos West Sea", "Shellos East Sea"},  -- 422
    {"Gastrodon West Sea", "Gastrodon East Sea"},  -- 423
    {"Ambipom"},  -- 424
    {"Drifloon"},  -- 425
    {"Drifblim"},  -- 426
    {"Buneary"},  -- 427
    {"Lopunny"},  -- 428
    {"Mismagius"},  -- 429
    {"Honchkrow"},  -- 430
    {"Glameow"},  -- 431
    {"Purugly"},  -- 432
    {"Chingling"},  -- 433
    {"Stunky"},  -- 434
    {"Skuntank"},  -- 435
    {"Bronzor"},  -- 436
    {"Bronzong"},  -- 437
    {"Bonsly"},  -- 438
    {"Mime Jr."},  -- 439
    {"Happiny"},  -- 440
    {"Chatot"},  -- 441
    {"Spiritomb"},  -- 442
    {"Gible"},  -- 443
    {"Gabite"},  -- 444
    {"Garchomp"},  -- 445
    {"Munchlax"},  -- 446
    {"Riolu"},  -- 447
    {"Lucario"},  -- 448
    {"Hippopotas"},  -- 449
    {"Hippowdon"},  -- 450
    {"Skorupi"},  -- 451
    {"Drapion"},  -- 452
    {"Croagunk"},  -- 453
    {"Toxicroak"},  -- 454
    {"Carnivine"},  -- 455
    {"Finneon"},  -- 456
    {"Lumineon"},  -- 457
    {"Mantyke"},  -- 458
    {"Snover"},  -- 459
    {"Abomasnow"},  -- 460
    {"Weavile"},  -- 461
    {"Magnezone"},  -- 462
    {"Lickilicky"},  -- 463
    {"Rhyperior"},  -- 464
    {"Tangrowth"},  -- 465
    {"Electivire"},  -- 466
    {"Magmortar"},  -- 467
    {"Togekiss"},  -- 468
    {"Yanmega"},  -- 469
    {"Leafeon"},  -- 470
    {"Glaceon"},  -- 471
    {"Gliscor"},  -- 472
    {"Mamoswine"},  -- 473
    {"Porygon-Z"},  -- 474
    {"Gallade"},  -- 475
    {"Probopass"},  -- 476
    {"Dusknoir"},  -- 477
    {"Froslass"},  -- 478
    {"Rotom", "Rotom Heat", "Rotom Wash", "Rotom Frost", "Rotom Fan", "Rotom Mow"},  -- 479
    {"Uxie"},  -- 480
    {"Mesprit"},  -- 481
    {"Azelf"},  -- 482
    {"Dialga"},  -- 483
    {"Palkia"},  -- 484
    {"Heatran"},  -- 485
    {"Regigigas"},  -- 486
    {"Giratina Altered Forme", "Giratina Origin Forme"},  -- 487
    {"Cresselia"},  -- 488
    {"Phione"},  -- 489
    {"Manaphy"},  -- 490
    {"Darkrai"},  -- 491
    {"Shaymin Land Forme", "Shaymin Sky Forme"},  -- 492
    {"Arceus"},  -- 493
}

local ABILITIES = {
	"None", --0
	"Stench", --1
	"Drizzle", --2
	"Speed Boost", --3
	"Battle Armor", --4
	"Sturdy", --5
	"Damp", --6
	"Limber", --7
	"Sand Veil", --8
	"Static", --9
	"Volt Absorb", --10
	"Water Absorb", --11
	"Oblivious", --12
	"Cloud Nine", --13
	"Compound Eyes", --14
	"Insomnia", --15
	"Color Change", --16
	"Immunity", --17
	"Flash Fire", --18
	"Shield Dust", --19
	"Own Tempo", --20
	"Suction Cups", --21
	"Intimidate", --22
	"Shadow Tag", --23
	"Rough Skin", --24
	"Wonder Guard", --25
	"Levitate", --26
	"Effect Spore", --27
	"Synchronize", --28
	"Clear Body", --29
	"Natural Cure", --30
	"Lightning Rod", --31
	"Serene Grace", --32
	"Swift Swim", --33
	"Chlorophyll", --34
	"Illuminate", --35
	"Trace", --36
	"Huge Power", --37
	"Poison Point", --38
	"Inner Focus", --39
	"Magma Armor", --40
	"Water Veil", --41
	"Magnet Pull", --42
	"Soundproof", --43
	"Rain Dish", --44
	"Sand Stream", --45
	"Pressure", --46
	"Thick Fat", --47
	"Early Bird", --48
	"Flame Body", --49
	"Run Away", --50
	"Keen Eye", --51
	"Hyper Cutter", --52
	"Pickup", --53
	"Truant", --54
	"Hustle", --55
	"Cute Charm", --56
	"Plus", --57
	"Minus", --58
	"Forecast", --59
	"Sticky Hold", --60
	"Shed Skin", --61
	"Guts", --62
	"Marvel Scale", --63
	"Liquid Ooze", --64
	"Overgrow", --65
	"Blaze", --66
	"Torrent", --67
	"Swarm", --68
	"Rock Head", --69
	"Drought", --70
	"Arena Trap", --71
	"Vital Spirit", --72
	"White Smoke", --73
	"Pure Power", --74
	"Shell Armor", --75
	"Air Lock", --76
	"Tangled Feet", --77
	"Motor Drive", --78
	"Rivalry", --79
	"Steadfast", --80
	"Snow Cloak", --81
	"Gluttony", --82
	"Anger Point", --83
	"Unburden", --84
	"Heatproof", --85
	"Simple", --86
	"Dry Skin", --87
	"Download", --88
	"Iron Fist", --89
	"Poison Heal", --90
	"Adaptability", --91
	"Skill Link", --92
	"Hydration", --93
	"Solar Power", --94
	"Quick Feet", --95
	"Normalize", --96
	"Sniper", --97
	"Magic Guard", --98
	"No Guard", --99
	"Stall", --100
	"Technician", --101
	"Leaf Guard", --102
	"Klutz", --103
	"Mold Breaker", --104
	"Super Luck", --105
	"Aftermath", --106
	"Anticipation", --107
	"Forewarn", --108
	"Unaware", --109
	"Tinted Lens", --110
	"Filter", --111
	"Slow Start", --112
	"Scrappy", --113
	"Storm Drain", --114
	"Ice Body", --115
	"Solid Rock", --116
	"Snow Warning", --117
	"Honey Gather", --118
	"Frisk", --119
	"Reckless", --120
	"Multitype", --121
	"Flower Gift", --122
	"Bad Dreams", --123
}

local MOVES = {
    "None", --0
	"Pound", --1
	"Karate Chop", --2
	"Double Slap", --3
	"Comet Punch", --4
	"Mega Punch", --5
	"Pay Day", --6
	"Fire Punch", --7
	"Ice Punch", --8
	"Thunder Punch", --9
	"Scratch", --10
	"Vice Grip", --11
	"Guillotine", --12
	"Razor Wind", --13
	"Swords Dance", --14
	"Cut", --15
	"Gust", --16
	"Wing Attack", --17
	"Whirlwind", --18
	"Fly", --19
	"Bind", --20
	"Slam", --21
	"Vine Whip", --22
	"Stomp", --23
	"Double Kick", --24
	"Mega Kick", --25
	"Jump Kick", --26
	"Rolling Kick", --27
	"Sand Attack", --28
	"Headbutt", --29
	"Horn Attack", --30
	"Fury Attack", --31
	"Horn Drill", --32
	"Tackle", --33
	"Body Slam", --34
	"Wrap", --35
	"Take Down", --36
	"Thrash", --37
	"Double Edge", --38
	"Tail Whip", --39
	"Poison Sting", --40
	"Twineedle", --41
	"Pin Missile", --42
	"Leer", --43
	"Bite", --44
	"Growl", --45
	"Roar", --46
	"Sing", --47
	"Supersonic", --48
	"Sonic Boom", --49
	"Disable", --50
	"Acid", --51
	"Ember", --52
	"Flamethrower", --53
	"Mist", --54
	"Water Gun", --55
	"Hydro Pump", --56
	"Surf", --57
	"Ice Beam", --58
	"Blizzard", --59
	"Psybeam", --60
	"Bubble Beam", --61
	"Aurora Beam", --62
	"Hyper Beam", --63
	"Peck", --64
	"Drill Peck", --65
	"Submission", --66
	"Low Kick", --67
	"Counter", --68
	"Seismic Toss", --69
	"Strength", --70
	"Absorb", --71
	"Mega Drain", --72
	"Leech Seed", --73
	"Growth", --74
	"Razor Leaf", --75
	"Solar Beam", --76
	"Poison Powder", --77
	"Stun Spore", --78
	"Sleep Powder", --79
	"Petal Dance", --80
	"String Shot", --81
	"Dragon Rage", --82
	"Fire Spin", --83
	"Thunder Shock", --84
	"Thunderbolt", --85
	"Thunder Wave", --86
	"Thunder", --87
	"Rock Throw", --88
	"Earthquake", --89
	"Fissure", --90
	"Dig", --91
	"Toxic", --92
	"Confusion", --93
	"Psychic", --94
	"Hypnosis", --95
	"Meditate", --96
	"Agility", --97
	"Quick Attack", --98
	"Rage", --99
	"Teleport", --100
	"Night Shade", --101
	"Mimic", --102
	"Screech", --103
	"Double Team", --104
	"Recover", --105
	"Harden", --106
	"Minimize", --107
	"Smoke Screen", --108
	"Confuse Ray", --109
	"Withdraw", --110
	"Defense Curl", --111
	"Barrier", --112
	"Light Screen", --113
	"Haze", --114
	"Reflect", --115
	"Focus Energy", --116
	"Bide", --117
	"Metronome", --118
	"Mirror Move", --119
	"Selfdestruct", --120
	"Egg Bomb", --121
	"Lick", --122
	"Smog", --123
	"Sludge", --124
	"Bone Club", --125
	"Fire Blast", --126
	"Waterfall", --127
	"Clamp", --128
	"Swift", --129
	"Skull Bash", --130
	"Spike Cannon", --131
	"Constrict", --132
	"Amnesia", --133
	"Kinesis", --134
	"Softboiled", --135
	"Hi Jump Kick", --136
	"Glare", --137
	"Dream Eater", --138
	"Poison Gas", --139
	"Barrage", --140
	"Leech Life", --141
	"Lovely Kiss", --142
	"Sky Attack", --143
	"Transform", --144
	"Bubble", --145
	"Dizzy Punch", --146
	"Spore", --147
	"Flash", --148
	"Psywave", --149
	"Splash", --150
	"Acid Armor", --151
	"Crabhammer", --152
	"Explosion", --153
	"Fury Swipes", --154
	"Bonemerang", --155
	"Rest", --156
	"Rock Slide", --157
	"Hyper Fang", --158
	"Sharpen", --159
	"Conversion", --160
	"Tri Attack", --161
	"Super Fang", --162
	"Slash", --163
	"Substitute", --164
	"Struggle", --165
	"Sketch", --166
	"Triple Kick", --167
	"Thief", --168
	"Spider Web", --169
	"Mind Reader", --170
	"Nightmare", --171
	"Flame Wheel", --172
	"Snore", --173
	"Curse", --174
	"Flail", --175
	"Conversion 2", --176
	"Aeroblast", --177
	"Cotton Spore", --178
	"Reversal", --179
	"Spite", --180
	"Powder Snow", --181
	"Protect", --182
	"Mach Punch", --183
	"Scary Face", --184
	"Faint Attack", --185
	"Sweet Kiss", --186
	"Belly Drum", --187
	"Sludge Bomb", --188
	"Mud Slap", --189
	"Octazooka", --190
	"Spikes", --191
	"Zap Cannon", --192
	"Foresight", --193
	"Destiny Bond", --194
	"Perish Song", --195
	"Icy Wind", --196
	"Detect", --197
	"Bone Rush", --198
	"Lock-On", --199
	"Outrage", --200
	"Sandstorm", --201
	"Giga Drain", --202
	"Endure", --203
	"Charm", --204
	"Rollout", --205
	"False Swipe", --206
	"Swagger", --207
	"Milk Drink", --208
	"Spark", --209
	"Fury Cutter", --210
	"Steel Wing", --211
	"Mean Look", --212
	"Attract", --213
	"Sleep Talk", --214
	"Heal Bell", --215
	"Return", --216
	"Present", --217
	"Frustration", --218
	"Safeguard", --219
	"Pain Split", --220
	"Sacred Fire", --221
	"Magnitude", --222
	"Dynamic Punch", --223
	"Megahorn", --224
	"Dragon Breath", --225
	"Baton Pass", --226
	"Encore", --227
	"Pursuit", --228
	"Rapid Spin", --229
	"Sweet Scent", --230
	"Iron Tail", --231
	"Metal Claw", --232
	"Vital Throw", --233
	"Morning Sun", --234
	"Synthesis", --235
	"Moonlight", --236
	"Hidden Power", --237
	"Cross Chop", --238
	"Twister", --239
	"Rain Dance", --240
	"Sunny Day", --241
	"Crunch", --242
	"Mirror Coat", --243
	"Psych Up", --244
	"Extreme Speed", --245
	"Ancient Power", --246
	"Shadow Ball", --247
	"Future Sight", --248
	"Rock Smash", --249
	"Whirlpool", --250
	"Beat Up", --251
	"Fake Out", --252
	"Uproar", --253
	"Stockpile", --254
	"Spit Up", --255
	"Swallow", --256
	"Heat Wave", --257
	"Hail", --258
	"Torment", --259
	"Flatter", --260
	"Will O Wisp", --261
	"Memento", --262
	"Facade", --263
	"Focus Punch", --264
	"Smelling Salt", --265
	"Follow Me", --266
	"Nature Power", --267
	"Charge", --268
	"Taunt", --269
	"Helping Hand", --270
	"Trick", --271
	"Role Play", --272
	"Wish", --273
	"Assist", --274
	"Ingrain", --275
	"Superpower", --276
	"Magic Coat", --277
	"Recycle", --278
	"Revenge", --279
	"Brick Break", --280
	"Yawn", --281
	"Knock Off", --282
	"Endeavor", --283
	"Eruption", --284
	"Skill Swap", --285
	"Imprison", --286
	"Refresh", --287
	"Grudge", --288
	"Snatch", --289
	"Secret Power", --290
	"Dive", --291
	"Arm Thrust", --292
	"Camouflage", --293
	"Tail Glow", --294
	"Luster Purge", --295
	"Mist Ball", --296
	"Feather Dance", --297
	"Teeter Dance", --298
	"Blaze Kick", --299
	"Mud Sport", --300
	"Ice Ball", --301
	"Needle Arm", --302
	"Slack Off", --303
	"Hyper Voice", --304
	"Poison Fang", --305
	"Crush Claw", --306
	"Blast Burn", --307
	"Hydro Cannon", --308
	"Meteor Mash", --309
	"Astonish", --310
	"Weather Ball", --311
	"Aromatherapy", --312
	"Fake Tears", --313
	"Air Cutter", --314
	"Overheat", --315
	"Odor Sleuth", --316
	"Rock Tomb", --317
	"Silver Wind", --318
	"Metal Sound", --319
	"Grass Whistle", --320
	"Tickle", --321
	"Cosmic Power", --322
	"Water Spout", --323
	"Signal Beam", --324
	"Shadow Punch", --325
	"Extrasensory", --326
	"Sky Uppercut", --327
	"Sand Tomb", --328
	"Sheer Cold", --329
	"Muddy Water", --330
	"Bullet Seed", --331
	"Aerial Ace", --332
	"Icicle Spear", --333
	"Iron Defense", --334
	"Block", --335
	"Howl", --336
	"Dragon Claw", --337
	"Frenzy Plant", --338
	"Bulk Up", --339
	"Bounce", --340
	"Mud Shot", --341
	"Poison Tail", --342
	"Covet", --343
	"Volt Tackle", --344
	"Magical Leaf", --345
	"Water Sport", --346
	"Calm Mind", --347
	"Leaf Blade", --348
	"Dragon Dance", --349
	"Rock Blast", --350
	"Shock Wave", --351
	"Water Pulse", --352
	"Doom Desire", --353
	"Psycho Boost", --354
	"Roost", --355
	"Gravity", --356
	"Miracle Eye", --357
	"Wake Up Slap", --358
	"Hammer Arm", --359
	"Gyro Ball", --360
	"Healing Wish", --361
	"Brine", --362
	"Natural Gift", --363
	"Feint", --364
	"Pluck", --365
	"Tailwind", --366
	"Acupressure", --367
	"Metal Burst", --368
	"U-turn", --369
	"Close Combat", --370
	"Payback", --371
	"Assurance", --372
	"Embargo", --373
	"Fling", --374
	"Psycho Shift", --375
	"Trump Card", --376
	"Aqua Cutter", --377
	"Wring Out", --378
	"Power Trick", --379
	"Gastro Acid", --380
	"Lucky Chant", --381
	"Me First", --382
	"Copycat", --383
	"Power Swap", --384
	"Guard Swap", --385
	"Punishment", --386
	"Last Resort", --387
	"Worry Seed", --388
	"Sucker Punch", --389
	"Toxic Spikes", --390
	"Heart Swap", --391
	"Aqua Ring", --392
	"Magnet Rise", --393
	"Flare Blitz", --394
	"Force Palm", --395
	"Aura Sphere", --396
	"Rock Polish", --397
	"Poison Jab", --398
	"Dark Pulse", --399
	"Night Slash", --400
	"Aqua Tail", --401
	"Seed Bomb", --402
	"Air Slash", --403
	"X Scissor", --404
	"Bug Buzz", --405
	"Dragon Pulse", --406
	"Dragon Rush", --407
	"Power Gem", --408
	"Drain Punch", --409
	"Vacuum Wave", --410
	"Focus Blast", --411
	"Energy Ball", --412
	"Brave Bird", --413
	"Earth Power", --414
	"Switcheroo", --415
	"Giga Impact", --416
	"Nasty Plot", --417
	"Bullet Punch", --418
	"Avalanche", --419
	"Ice Shard", --420
	"Shadow Claw", --421
	"Thunder Fang", --422
	"Ice Fang", --423
	"Fire Fang", --424
	"Shadow Sneak", --425
	"Mud Bomb", --426
	"Psycho Cut", --427
	"Zen Headbutt", --428
	"Mirror Shot", --429
	"Flash Cannon", --430
	"Rock Climb", --431
	"Defog", --432
	"Trick Room", --433
	"Draco Meteor", --434
	"Discharge", --435
	"Lava Plume", --436
	"Leaf Storm", --437
	"Power Whip", --438
	"Rock Wrecker", --439
	"Cross Poison", --440
	"Gunk Shot", --441
	"Iron Head", --442
	"Magnet Bomb", --443
	"Stone Edge", --444
	"Captivate", --445
	"Stealth Rock", --446
	"Grass Knot", --447
	"Chatter", --448
	"Judgment", --449
	"Bug Bite", --450
	"Charge Beam", --451
	"Wood Hammer", --452
	"Aqua Jet", --453
	"Attack Order", --454
	"Defend Order", --455
	"Heal Order", --456
	"Head Smash", --457
	"Double Hit", --458
	"Roar Of Time", --459
	"Spacial Rend", --460
	"Lunar Dance", --461
	"Crush Grip", --462
	"Magma Storm", --463
	"Dark Void", --464
	"Seed Flare", --465
	"Ominous Wind", --466
	"Shadow Force", --467
}

local ITEMS = {
	"None", --0
	"Master Ball", --1
	"Ultra Ball", --2
	"Great Ball", --3
	"Poke Ball", --4
	"Safari Ball", --5
	"Net Ball", --6
	"Dive Ball", --7
	"Nest Ball", --8
	"Repeat Ball", --9
	"Timer Ball", --10
	"Luxury Ball", --11
	"Premier Ball", --12
	"Dusk Ball", --13
	"Heal Ball", --14
	"Quick Ball", --15
	"Cherish Ball", --16
	"Potion", --17
	"Antidote", --18
	"Burn Heal", --19
	"Ice Heal", --20
	"Awakening", --21
	"Parlyz Heal", --22
	"Full Restore", --23
	"Max Potion", --24
	"Hyper Potion", --25
	"Super Potion", --26
	"Full Heal", --27
	"Revive", --28
	"Max Revive", --29
	"Fresh Water", --30
	"Soda Pop", --31
	"Lemonade", --32
	"Moomoo Milk", --33
	"Energypowder", --34
	"Energy Root", --35
	"Heal Powder", --36
	"Revival Herb", --37
	"Ether", --38
	"Max Ether", --39
	"Elixir", --40
	"Max Elixir", --41
	"Lava Cookie", --42
	"Berry Juice", --43
	"Sacred Ash", --44
	"Hp Up", --45
	"Protein", --46
	"Iron", --47
	"Carbos", --48
	"Calcium", --49
	"Rare Candy", --50
	"Pp Up", --51
	"Zinc", --52
	"Pp Max", --53
	"Old Gateau", --54
	"Guard Spec", --55
	"Dire Hit", --56
	"X Attack", --57
	"X Defense", --58
	"X Speed", --59
	"X Accuracy", --60
	"X Special", --61
	"X Sp Def", --62
	"Poke Doll", --63
	"Fluffy Tail", --64
	"Blue Flute", --65
	"Yellow Flute", --66
	"Red Flute", --67
	"Black Flute", --68
	"White Flute", --69
	"Shoal Salt", --70
	"Shoal Shell", --71
	"Red Shard", --72
	"Blue Shard", --73
	"Yellow Shard", --74
	"Green Shard", --75
	"Super Repel", --76
	"Max Repel", --77
	"Escape Rope", --78
	"Repel", --79
	"Sun Stone", --80
	"Moon Stone", --81
	"Fire Stone", --82
	"Thunderstone", --83
	"Water Stone", --84
	"Leaf Stone", --85
	"Tinymushroom", --86
	"Big Mushroom", --87
	"Pearl", --88
	"Big Pearl", --89
	"Stardust", --90
	"Star Piece", --91
	"Nugget", --92
	"Heart Scale", --93
	"Honey", --94
	"Growth Mulch", --95
	"Damp Mulch", --96
	"Stable Mulch", --97
	"Gooey Mulch", --98
	"Root Fossil", --99
	"Claw Fossil", --100
	"Helix Fossil", --101
	"Dome Fossil", --102
	"Old Amber", --103
	"Armor Fossil", --104
	"Skull Fossil", --105
	"Rare Bone", --106
	"Shiny Stone", --107
	"Dusk Stone", --108
	"Dawn Stone", --109
	"Oval Stone", --110
	"Odd Keystone", --111
	"Griseous Orb", --112
	"Unused 113", --113
	"Unused 114", --114
	"Unused 115", --115
	"Unused 116", --116
	"Unused 117", --117
	"Unused 118", --118
	"Unused 119", --119
	"Unused 120", --120
	"Unused 121", --121
	"Unused 122", --122
	"Unused 123", --123
	"Unused 124", --124
	"Unused 125", --125
	"Unused 126", --126
	"Unused 127", --127
	"Unused 128", --128
	"Unused 129", --129
	"Unused 130", --130
	"Unused 131", --131
	"Unused 132", --132
	"Unused 133", --133
	"Unused 134", --134
	"Adamant Orb", --135
	"Lustrous Orb", --136
	"Grass Mail", --137
	"Flame Mail", --138
	"Bubble Mail", --139
	"Bloom Mail", --140
	"Tunnel Mail", --141
	"Steel Mail", --142
	"Heart Mail", --143
	"Snow Mail", --144
	"Space Mail", --145
	"Air Mail", --146
	"Mosaic Mail", --147
	"Brick Mail", --148
	"Cheri Berry", --149
	"Chesto Berry", --150
	"Pecha Berry", --151
	"Rawst Berry", --152
	"Aspear Berry", --153
	"Leppa Berry", --154
	"Oran Berry", --155
	"Persim Berry", --156
	"Lum Berry", --157
	"Sitrus Berry", --158
	"Figy Berry", --159
	"Wiki Berry", --160
	"Mago Berry", --161
	"Aguav Berry", --162
	"Iapapa Berry", --163
	"Razz Berry", --164
	"Bluk Berry", --165
	"Nanab Berry", --166
	"Wepear Berry", --167
	"Pinap Berry", --168
	"Pomeg Berry", --169
	"Kelpsy Berry", --170
	"Qualot Berry", --171
	"Hondew Berry", --172
	"Grepa Berry", --173
	"Tamato Berry", --174
	"Cornn Berry", --175
	"Magost Berry", --176
	"Rabuta Berry", --177
	"Nomel Berry", --178
	"Spelon Berry", --179
	"Pamtre Berry", --180
	"Watmel Berry", --181
	"Durin Berry", --182
	"Belue Berry", --183
	"Occa Berry", --184
	"Passho Berry", --185
	"Wacan Berry", --186
	"Rindo Berry", --187
	"Yache Berry", --188
	"Chople Berry", --189
	"Kebia Berry", --190
	"Shuca Berry", --191
	"Coba Berry", --192
	"Payapa Berry", --193
	"Tanga Berry", --194
	"Charti Berry", --195
	"Kasib Berry", --196
	"Haban Berry", --197
	"Colbur Berry", --198
	"Babiri Berry", --199
	"Chilan Berry", --200
	"Liechi Berry", --201
	"Ganlon Berry", --202
	"Salac Berry", --203
	"Petaya Berry", --204
	"Apicot Berry", --205
	"Lansat Berry", --206
	"Starf Berry", --207
	"Enigma Berry", --208
	"Micle Berry", --209
	"Custap Berry", --210
	"Jaboca Berry", --211
	"Rowap Berry", --212
	"Brightpowder", --213
	"White Herb", --214
	"Macho Brace", --215
	"Exp Share", --216
	"Quick Claw", --217
	"Soothe Bell", --218
	"Mental Herb", --219
	"Choice Band", --220
	"Kings Rock", --221
	"Silverpowder", --222
	"Amulet Coin", --223
	"Cleanse Tag", --224
	"Soul Dew", --225
	"Deepseatooth", --226
	"Deepseascale", --227
	"Smoke Ball", --228
	"Everstone", --229
	"Focus Band", --230
	"Lucky Egg", --231
	"Scope Lens", --232
	"Metal Coat", --233
	"Leftovers", --234
	"Dragon Scale", --235
	"Light Ball", --236
	"Soft Sand", --237
	"Hard Stone", --238
	"Miracle Seed", --239
	"Blackglasses", --240
	"Black Belt", --241
	"Magnet", --242
	"Mystic Water", --243
	"Sharp Beak", --244
	"Poison Barb", --245
	"Nevermeltice", --246
	"Spell Tag", --247
	"Twistedspoon", --248
	"Charcoal", --249
	"Dragon Fang", --250
	"Silk Scarf", --251
	"Upgrade", --252
	"Shell Bell", --253
	"Sea Incense", --254
	"Lax Incense", --255
	"Lucky Punch", --256
	"Metal Powder", --257
	"Thick Club", --258
	"Stick", --259
	"Red Scarf", --260
	"Blue Scarf", --261
	"Pink Scarf", --262
	"Green Scarf", --263
	"Yellow Scarf", --264
	"Wide Lens", --265
	"Muscle Band", --266
	"Wise Glasses", --267
	"Expert Belt", --268
	"Light Clay", --269
	"Life Orb", --270
	"Power Herb", --271
	"Toxic Orb", --272
	"Flame Orb", --273
	"Quick Powder", --274
	"Focus Sash", --275
	"Zoom Lens", --276
	"Metronome", --277
	"Iron Ball", --278
	"Lagging Tail", --279
	"Destiny Knot", --280
	"Black Sludge", --281
	"Icy Rock", --282
	"Smooth Rock", --283
	"Heat Rock", --284
	"Damp Rock", --285
	"Grip Claw", --286
	"Choice Scarf", --287
	"Sticky Barb", --288
	"Power Bracer", --289
	"Power Belt", --290
	"Power Lens", --291
	"Power Band", --292
	"Power Anklet", --293
	"Power Weight", --294
	"Shed Shell", --295
	"Big Root", --296
	"Choice Specs", --297
	"Flame Plate", --298
	"Splash Plate", --299
	"Zap Plate", --300
	"Meadow Plate", --301
	"Icicle Plate", --302
	"Fist Plate", --303
	"Toxic Plate", --304
	"Earth Plate", --305
	"Sky Plate", --306
	"Mind Plate", --307
	"Insect Plate", --308
	"Stone Plate", --309
	"Spooky Plate", --310
	"Draco Plate", --311
	"Dread Plate", --312
	"Iron Plate", --313
	"Odd Incense", --314
	"Rock Incense", --315
	"Full Incense", --316
	"Wave Incense", --317
	"Rose Incense", --318
	"Luck Incense", --319
	"Pure Incense", --320
	"Protector", --321
	"Electirizer", --322
	"Magmarizer", --323
	"Dubious Disc", --324
	"Reaper Cloth", --325
	"Razor Claw", --326
	"Razor Fang", --327
	"TM01", --328
	"TM02", --329
	"TM03", --330
	"TM04", --331
	"TM05", --332
	"TM06", --333
	"TM07", --334
	"TM08", --335
	"TM09", --336
	"TM10", --337
	"TM11", --338
	"TM12", --339
	"TM13", --340
	"TM14", --341
	"TM15", --342
	"TM16", --343
	"TM17", --344
	"TM18", --345
	"TM19", --346
	"TM20", --347
	"TM21", --348
	"TM22", --349
	"TM23", --350
	"TM24", --351
	"TM25", --352
	"TM26", --353
	"TM27", --354
	"TM28", --355
	"TM29", --356
	"TM30", --357
	"TM31", --358
	"TM32", --359
	"TM33", --360
	"TM34", --361
	"TM35", --362
	"TM36", --363
	"TM37", --364
	"TM38", --365
	"TM39", --366
	"TM40", --367
	"TM41", --368
	"TM42", --369
	"TM43", --370
	"TM44", --371
	"TM45", --372
	"TM46", --373
	"TM47", --374
	"TM48", --375
	"TM49", --376
	"TM50", --377
	"TM51", --378
	"TM52", --379
	"TM53", --380
	"TM54", --381
	"TM55", --382
	"TM56", --383
	"TM57", --384
	"TM58", --385
	"TM59", --386
	"TM60", --387
	"TM61", --388
	"TM62", --389
	"TM63", --390
	"TM64", --391
	"TM65", --392
	"TM66", --393
	"TM67", --394
	"TM68", --395
	"TM69", --396
	"TM70", --397
	"TM71", --398
	"TM72", --399
	"TM73", --400
	"TM74", --401
	"TM75", --402
	"TM76", --403
	"TM77", --404
	"TM78", --405
	"TM79", --406
	"TM80", --407
	"TM81", --408
	"TM82", --409
	"TM83", --410
	"TM84", --411
	"TM85", --412
	"TM86", --413
	"TM87", --414
	"TM88", --415
	"TM89", --416
	"TM90", --417
	"TM91", --418
	"TM92", --419
	"HM01", --420
	"HM02", --421
	"HM03", --422
	"HM04", --423
	"HM05", --424
	"HM06", --425
	"HM07", --426
	"HM08", --427
	"Explorer Kit", --428
	"Loot Sack", --429
	"Rule Book", --430
	"Poke Radar", --431
	"Point Card", --432
	"Journal", --433
	"Seal Case", --434
	"Fashion Case", --435
	"Seal Bag", --436
	"Pal Pad", --437
	"Works Key", --438
	"Old Charm", --439
	"Galactic Key", --440
	"Red Chain", --441
	"Town Map", --442
	"Vs Seeker", --443
	"Coin Case", --444
	"Old Rod", --445
	"Good Rod", --446
	"Super Rod", --447
	"Sprayduck", --448
	"Poffin Case", --449
	"Bicycle", --450
	"Suite Key", --451
	"Oaks Letter", --452
	"Lunar Wing", --453
	"Member Card", --454
	"Azure Flute", --455
	"S S Ticket", --456
	"Contest Pass", --457
	"Magma Stone", --458
	"Parcel", --459
	"Coupon 1", --460
	"Coupon 2", --461
	"Coupon 3", --462
	"Storage Key", --463
	"Secretpotion", --464
	"Vs Recorder", --465
	"Gracidea", --466
	"Secret Key", --467
}

-- Gen 4 Pokemon character encoding table.
-- Maps 2-byte encoded values to UTF-8 strings.
-- 0x0000 is the null character and 0xFFFF is the string terminator; both are handled externally.
-- Pocket symbol entries 0x113-0x11A are omitted.
local ENCODING = {
    [0x001] = "　",

    -- Hiragana
    [0x002] = "ぁ", [0x003] = "あ", [0x004] = "ぃ", [0x005] = "い",
    [0x006] = "ぅ", [0x007] = "う", [0x008] = "ぇ", [0x009] = "え",
    [0x00A] = "ぉ", [0x00B] = "お", [0x00C] = "か", [0x00D] = "が",
    [0x00E] = "き", [0x00F] = "ぎ",
    [0x010] = "く", [0x011] = "ぐ", [0x012] = "け", [0x013] = "げ",
    [0x014] = "こ", [0x015] = "ご", [0x016] = "さ", [0x017] = "ざ",
    [0x018] = "し", [0x019] = "じ", [0x01A] = "す", [0x01B] = "ず",
    [0x01C] = "せ", [0x01D] = "ぜ", [0x01E] = "そ", [0x01F] = "ぞ",
    [0x020] = "た", [0x021] = "だ", [0x022] = "ち", [0x023] = "ぢ",
    [0x024] = "っ", [0x025] = "つ", [0x026] = "づ", [0x027] = "て",
    [0x028] = "で", [0x029] = "と", [0x02A] = "ど", [0x02B] = "な",
    [0x02C] = "に", [0x02D] = "ぬ", [0x02E] = "ね", [0x02F] = "の",
    [0x030] = "は", [0x031] = "ば", [0x032] = "ぱ", [0x033] = "ひ",
    [0x034] = "び", [0x035] = "ぴ", [0x036] = "ふ", [0x037] = "ぶ",
    [0x038] = "ぷ", [0x039] = "へ", [0x03A] = "べ", [0x03B] = "ぺ",
    [0x03C] = "ほ", [0x03D] = "ぼ", [0x03E] = "ぽ", [0x03F] = "ま",
    [0x040] = "み", [0x041] = "む", [0x042] = "め", [0x043] = "も",
    [0x044] = "ゃ", [0x045] = "や", [0x046] = "ゅ", [0x047] = "ゆ",
    [0x048] = "ょ", [0x049] = "よ", [0x04A] = "ら", [0x04B] = "り",
    [0x04C] = "る", [0x04D] = "れ", [0x04E] = "ろ", [0x04F] = "わ",
    [0x050] = "を", [0x051] = "ん",

    -- Katakana
    [0x052] = "ァ", [0x053] = "ア", [0x054] = "ィ", [0x055] = "イ",
    [0x056] = "ゥ", [0x057] = "ウ", [0x058] = "ェ", [0x059] = "エ",
    [0x05A] = "ォ", [0x05B] = "オ", [0x05C] = "カ", [0x05D] = "ガ",
    [0x05E] = "キ", [0x05F] = "ギ",
    [0x060] = "ク", [0x061] = "グ", [0x062] = "ケ", [0x063] = "ゲ",
    [0x064] = "コ", [0x065] = "ゴ", [0x066] = "サ", [0x067] = "ザ",
    [0x068] = "シ", [0x069] = "ジ", [0x06A] = "ス", [0x06B] = "ズ",
    [0x06C] = "セ", [0x06D] = "ゼ", [0x06E] = "ソ", [0x06F] = "ゾ",
    [0x070] = "タ", [0x071] = "ダ", [0x072] = "チ", [0x073] = "ヂ",
    [0x074] = "ッ", [0x075] = "ツ", [0x076] = "ヅ", [0x077] = "テ",
    [0x078] = "デ", [0x079] = "ト", [0x07A] = "ド", [0x07B] = "ナ",
    [0x07C] = "ニ", [0x07D] = "ヌ", [0x07E] = "ネ", [0x07F] = "ノ",
    [0x080] = "ハ", [0x081] = "バ", [0x082] = "パ", [0x083] = "ヒ",
    [0x084] = "ビ", [0x085] = "ピ", [0x086] = "フ", [0x087] = "ブ",
    [0x088] = "プ", [0x089] = "ヘ", [0x08A] = "ベ", [0x08B] = "ペ",
    [0x08C] = "ホ", [0x08D] = "ボ", [0x08E] = "ポ", [0x08F] = "マ",
    [0x090] = "ミ", [0x091] = "ム", [0x092] = "メ", [0x093] = "モ",
    [0x094] = "ャ", [0x095] = "ヤ", [0x096] = "ュ", [0x097] = "ユ",
    [0x098] = "ョ", [0x099] = "ヨ", [0x09A] = "ラ", [0x09B] = "リ",
    [0x09C] = "ル", [0x09D] = "レ", [0x09E] = "ロ", [0x09F] = "ワ",
    [0x0A0] = "ヲ", [0x0A1] = "ン",

    -- Fullwidth digits
    [0x0A2] = "０", [0x0A3] = "１", [0x0A4] = "２", [0x0A5] = "３",
    [0x0A6] = "４", [0x0A7] = "５", [0x0A8] = "６", [0x0A9] = "７",
    [0x0AA] = "８", [0x0AB] = "９",

    -- Fullwidth uppercase
    [0x0AC] = "Ａ", [0x0AD] = "Ｂ", [0x0AE] = "Ｃ", [0x0AF] = "Ｄ",
    [0x0B0] = "Ｅ", [0x0B1] = "Ｆ", [0x0B2] = "Ｇ", [0x0B3] = "Ｈ",
    [0x0B4] = "Ｉ", [0x0B5] = "Ｊ", [0x0B6] = "Ｋ", [0x0B7] = "Ｌ",
    [0x0B8] = "Ｍ", [0x0B9] = "Ｎ", [0x0BA] = "Ｏ", [0x0BB] = "Ｐ",
    [0x0BC] = "Ｑ", [0x0BD] = "Ｒ", [0x0BE] = "Ｓ", [0x0BF] = "Ｔ",
    [0x0C0] = "Ｕ", [0x0C1] = "Ｖ", [0x0C2] = "Ｗ", [0x0C3] = "Ｘ",
    [0x0C4] = "Ｙ", [0x0C5] = "Ｚ",

    -- Fullwidth lowercase
    [0x0C6] = "ａ", [0x0C7] = "ｂ", [0x0C8] = "ｃ", [0x0C9] = "ｄ",
    [0x0CA] = "ｅ", [0x0CB] = "ｆ", [0x0CC] = "ｇ", [0x0CD] = "ｈ",
    [0x0CE] = "ｉ", [0x0CF] = "ｊ", [0x0D0] = "ｋ", [0x0D1] = "ｌ",
    [0x0D2] = "ｍ", [0x0D3] = "ｎ", [0x0D4] = "ｏ", [0x0D5] = "ｐ",
    [0x0D6] = "ｑ", [0x0D7] = "ｒ", [0x0D8] = "ｓ", [0x0D9] = "ｔ",
    [0x0DA] = "ｕ", [0x0DB] = "ｖ", [0x0DC] = "ｗ", [0x0DD] = "ｘ",
    [0x0DE] = "ｙ", [0x0DF] = "ｚ",

    -- Punctuation and symbols (fullwidth/Japanese set)
    [0x0E1] = "！", [0x0E2] = "？", [0x0E3] = "、", [0x0E4] = "。",
    [0x0E5] = "…", [0x0E6] = "・", [0x0E7] = "／", [0x0E8] = "「",
    [0x0E9] = "」", [0x0EA] = "『", [0x0EB] = "』", [0x0EC] = "（",
    [0x0ED] = "）", [0x0EE] = "♂", [0x0EF] = "♀",
    [0x0F0] = "＋", [0x0F1] = "ー", [0x0F2] = "×", [0x0F3] = "÷",
    [0x0F4] = "＝", [0x0F5] = "～", [0x0F6] = "：", [0x0F7] = "；",
    [0x0F8] = "．", [0x0F9] = "，", [0x0FA] = "♠", [0x0FB] = "♣",
    [0x0FC] = "♥", [0x0FD] = "♦", [0x0FE] = "★", [0x0FF] = "◎",

    -- More symbols
    [0x100] = "○", [0x101] = "□", [0x102] = "△", [0x103] = "◇",
    [0x104] = "＠", [0x105] = "♪", [0x106] = "％",
    [0x107] = "☀", [0x108] = "☁", [0x109] = "☂", [0x10A] = "☃",
    [0x10B] = "😑", [0x10C] = "☺", [0x10D] = "☹", [0x10E] = "😠",
    [0x10F] = "⤴",
    [0x110] = "⤵", [0x111] = "💤", [0x112] = "円",
    -- 0x113-0x11A: pocket symbols, omitted
    [0x11B] = "←", [0x11C] = "↑", [0x11D] = "↓", [0x11E] = "→",
    [0x11F] = "►",

    -- Half-width digits and letters (in-game "plain" ASCII equivalent)
    [0x120] = "＆",
    [0x121] = "0", [0x122] = "1", [0x123] = "2", [0x124] = "3",
    [0x125] = "4", [0x126] = "5", [0x127] = "6", [0x128] = "7",
    [0x129] = "8", [0x12A] = "9",
    [0x12B] = "A", [0x12C] = "B", [0x12D] = "C", [0x12E] = "D",
    [0x12F] = "E", [0x130] = "F", [0x131] = "G", [0x132] = "H",
    [0x133] = "I", [0x134] = "J", [0x135] = "K", [0x136] = "L",
    [0x137] = "M", [0x138] = "N", [0x139] = "O", [0x13A] = "P",
    [0x13B] = "Q", [0x13C] = "R", [0x13D] = "S", [0x13E] = "T",
    [0x13F] = "U", [0x140] = "V", [0x141] = "W", [0x142] = "X",
    [0x143] = "Y", [0x144] = "Z",
    [0x145] = "a", [0x146] = "b", [0x147] = "c", [0x148] = "d",
    [0x149] = "e", [0x14A] = "f", [0x14B] = "g", [0x14C] = "h",
    [0x14D] = "i", [0x14E] = "j", [0x14F] = "k", [0x150] = "l",
    [0x151] = "m", [0x152] = "n", [0x153] = "o", [0x154] = "p",
    [0x155] = "q", [0x156] = "r", [0x157] = "s", [0x158] = "t",
    [0x159] = "u", [0x15A] = "v", [0x15B] = "w", [0x15C] = "x",
    [0x15D] = "y", [0x15E] = "z",

    -- Extended Latin
    [0x15F] = "À",
    [0x160] = "Á", [0x161] = "Â", [0x162] = "Ã", [0x163] = "Ä",
    [0x164] = "Å", [0x165] = "Æ", [0x166] = "Ç", [0x167] = "È",
    [0x168] = "É", [0x169] = "Ê", [0x16A] = "Ë", [0x16B] = "Ì",
    [0x16C] = "Í", [0x16D] = "Î", [0x16E] = "Ï", [0x16F] = "Ð",
    [0x170] = "Ñ", [0x171] = "Ò", [0x172] = "Ó", [0x173] = "Ô",
    [0x174] = "Õ", [0x175] = "Ö", [0x176] = "×", [0x177] = "Ø",
    [0x178] = "Ù", [0x179] = "Ú", [0x17A] = "Û", [0x17B] = "Ü",
    [0x17C] = "Ý", [0x17D] = "Þ", [0x17E] = "ß", [0x17F] = "à",
    [0x180] = "á", [0x181] = "â", [0x182] = "ã", [0x183] = "ä",
    [0x184] = "å", [0x185] = "æ", [0x186] = "ç", [0x187] = "è",
    [0x188] = "é", [0x189] = "ê", [0x18A] = "ë", [0x18B] = "ì",
    [0x18C] = "í", [0x18D] = "î", [0x18E] = "ï", [0x18F] = "ð",
    [0x190] = "ñ", [0x191] = "ò", [0x192] = "ó", [0x193] = "ô",
    [0x194] = "õ", [0x195] = "ö", [0x196] = "÷", [0x197] = "ø",
    [0x198] = "ù", [0x199] = "ú", [0x19A] = "û", [0x19B] = "ü",
    [0x19C] = "ý", [0x19D] = "þ", [0x19E] = "ÿ", [0x19F] = "Œ",
    [0x1A0] = "œ", [0x1A1] = "Ş", [0x1A2] = "ş", [0x1A3] = "ª",
    [0x1A4] = "º", [0x1A5] = "er",[0x1A6] = "re",[0x1A7] = "r",
    [0x1A8] = "$", -- Pokemon Dollar; no standard Unicode equivalent
    [0x1A9] = "¡", [0x1AA] = "¿", [0x1AB] = "!", [0x1AC] = "?",
    [0x1AD] = ",", [0x1AE] = ".", [0x1AF] = "…",

    -- Punctuation (half-width/ASCII set)
    [0x1B0] = "･", [0x1B1] = "/",
    [0x1B2] = "'", [0x1B3] = "'", [0x1B4] = "\"", [0x1B5] = "\"",
    [0x1B6] = "„", [0x1B7] = "«", [0x1B8] = "»",
    [0x1B9] = "(", [0x1BA] = ")",
    [0x1BB] = "♂", [0x1BC] = "♀",
    [0x1BD] = "+", [0x1BE] = "-", [0x1BF] = "*",
    [0x1C0] = "#", [0x1C1] = "=", [0x1C2] = "&", [0x1C3] = "~",
    [0x1C4] = ":", [0x1C5] = ";",
    [0x1C6] = "♠", [0x1C7] = "♣", [0x1C8] = "♥", [0x1C9] = "♦",
    [0x1CA] = "★", [0x1CB] = "◎", [0x1CC] = "○", [0x1CD] = "□",
    [0x1CE] = "△", [0x1CF] = "◇",
    [0x1D0] = "@", [0x1D1] = "♪", [0x1D2] = "%",
    [0x1D3] = "☀", [0x1D4] = "☁", [0x1D5] = "☂", [0x1D6] = "☃",
    [0x1D7] = "😑", [0x1D8] = "☺", [0x1D9] = "☹", [0x1DA] = "😠",
    [0x1DB] = "⤴", [0x1DC] = "⤵", [0x1DD] = "💤",
    [0x1DF] = "e",

    -- Special glyphs
    [0x1E0] = "PK", [0x1E1] = "MN",
    [0x1E8] = "°", [0x1E9] = "_", [0x1EA] = "＿",
    [0x1EB] = "․", [0x1EC] = "‥",
}
setmetatable(ENCODING, {__index = function(t, k) return "?" end})

return {
	PRONOUNS = PRONOUNS,
	OVERWORLD = OVERWORLD,
	SPECIES = SPECIES,
	ABILITIES = ABILITIES,
	MOVES = MOVES,
	ITEMS = ITEMS,
	ENCODING = ENCODING,
}