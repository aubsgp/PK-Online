#ifndef ACTOR_H
#define ACTOR_H

#include "cJSON.h"
#include "lua.h"
#include <stdint.h>

#define ACTOR_DIFFERS 0b00000001
#define PARTY_DIFFERS 0b00000010

#define FIELD(type, name) type name;
#define FIELD_ARRAY(type, name, size) type name[size];
#define FIELD_PADDING(size) char padding[size];

#define POKEMON_FIELDS \
    FIELD(uint16_t, species); \
    FIELD_ARRAY(uint16_t, stats, 6); \
    FIELD_ARRAY(uint16_t, moves, 4); \
    FIELD_ARRAY(uint16_t, name, 11); \
    FIELD(uint16_t, held_item); \
    FIELD(uint16_t, curr_hp); \
    FIELD(uint8_t, level); \
    FIELD(uint8_t, forme); \
    FIELD(uint8_t, status); \
    FIELD(uint8_t, gender); \
    FIELD(uint8_t, ability); \
    FIELD_PADDING(1);

#define BILLBOARD_FIELDS \
    FIELD_ARRAY(uint32_t, pos, 3); \
    FIELD(uint8_t, anim_type); \
    FIELD(uint8_t, anim_frame); \
    FIELD(uint8_t, sprite); \
    FIELD_PADDING(1);

#define ACTOR_FIELDS \
    FIELD(uint16_t, id); \
    FIELD(uint16_t, map); \
    FIELD_ARRAY(uint16_t, name, 11); \
    FIELD(uint8_t, pronouns); \
    FIELD_PADDING(1);

typedef struct Pokemon {
    POKEMON_FIELDS
} Pokemon;

typedef struct Billboard {
    BILLBOARD_FIELDS
} Billboard;

typedef struct Actor {
    Pokemon party[6];
    Billboard billboard;
    ACTOR_FIELDS
} Actor;

cJSON *pokemon_to_json(Pokemon *pkmn);
Pokemon pokemon_from_json(cJSON *obj);
lua_State *pokemon_to_lua(Pokemon *pkmn, lua_State *L);
Pokemon pokemon_from_lua(lua_State *L, int index);

cJSON *billboard_to_json(Billboard *bb);
Billboard billboard_from_json(cJSON *obj);
lua_State *billboard_to_lua(Billboard *bb, lua_State *L);
Billboard billboard_from_lua(lua_State *L, int index);

cJSON *actor_to_json(Actor *actor, char include_party);
Actor actor_from_json(cJSON *obj);
lua_State *actor_to_lua(Actor *actor, lua_State *L);
Actor actor_from_lua(lua_State *L, int index);

char compare_actors(Actor *a, Actor *b);

void print_actor(Actor *actor);

#undef FIELD
#undef FIELD_STRING
#undef FIELD_ARRAY
#undef FIELD_PADDING

#endif