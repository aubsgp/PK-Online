#include "actor.h"
#include "lua.h"
#include "cJSON.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

void print_actor(Actor *actor){
    FILE *log = fopen("debug.log", "a");

    fprintf(log, "Actor:\n");
    fprintf(log, "  id: %d\n", actor->id);
    fprintf(log, "  name: %s\n", actor->name);
    fprintf(log, "  pronouns: %d\n", actor->pronouns);
    fprintf(log, "  map: %d\n", actor->map);

    fprintf(log, "  billboard pos: %f %f %f\n",
        actor->billboard.pos[0]/65536.0,
        actor->billboard.pos[1]/65536.0,
        actor->billboard.pos[2]/65536.0
    );
    fprintf(log, "  billboard anim_type: %d\n", actor->billboard.anim_type);
    fprintf(log, "  billboard anim_frame: %d\n", actor->billboard.anim_frame);

    for(int i = 0; i < 6; i++){
        if(actor->party[i].species == 0) break;
        fprintf(log, "  party[%d]:\n", i);
        fprintf(log, "    species: %d\n", actor->party[i].species);
        fprintf(log, "    gender: %d\n", actor->party[i].gender);
        fprintf(log, "    forme: %d\n", actor->party[i].forme);
        fprintf(log, "    ability: %d\n", actor->party[i].ability);
        for(int j = 0; j < 11 && actor->name[j] != 0xFFFF && actor->name[j] != 0; j++)
            fprintf(log, "%04x ", actor->name[j]);
        fprintf(log, "\n");
        fprintf(log, "    level: %d\n", actor->party[i].level);
        fprintf(log, "    item: %d\n", actor->party[i].held_item);
        fprintf(log, "    curr_hp: %d\n", actor->party[i].curr_hp);
        fprintf(log, "    status: %d\n", actor->party[i].status);
        fprintf(log, "    stats: %d %d %d %d %d %d\n",
            actor->party[i].stats[0], 
            actor->party[i].stats[1],
            actor->party[i].stats[2], 
            actor->party[i].stats[3],
            actor->party[i].stats[4], 
            actor->party[i].stats[5]
        );
        fprintf(log, "    moves: %d %d %d %d\n",
            actor->party[i].moves[0], 
            actor->party[i].moves[1],
            actor->party[i].moves[2], 
            actor->party[i].moves[3]
        );
    }

    fclose(log);
}

cJSON *pokemon_to_json(Pokemon *pkmn){
    cJSON *root = cJSON_CreateObject();

    #define FIELD(type, name) cJSON_AddNumberToObject(root, #name, pkmn->name)
    #define FIELD_STRING(name, size) cJSON_AddStringToObject(root, #name, pkmn->name)
    #define FIELD_ARRAY(type, name, size) { \
        cJSON *arr = cJSON_CreateArray(); \
        for(int i = 0; i < size; i++){ \
            cJSON_AddItemToArray(arr, cJSON_CreateNumber(pkmn->name[i])); \
        } \
        cJSON_AddItemToObject(root, #name, arr);\
    }
    #define FIELD_PADDING(size) // ignore padding fields

    POKEMON_FIELDS

    #undef FIELD
    #undef FIELD_STRING
    #undef FIELD_ARRAY
    #undef FIELD_PADDING
    
    return root;
}

Pokemon pokemon_from_json(cJSON *obj){
    Pokemon pkmn;

    #define FIELD(type, name) pkmn.name = cJSON_GetObjectItem(obj, #name)->valueint
    #define FIELD_STRING(name, size) strcpy(pkmn.name, cJSON_GetObjectItem(obj, #name)->valuestring)
    #define FIELD_ARRAY(type, name, size) { \
        cJSON *arr = cJSON_GetObjectItem(obj, #name); \
        for(int i = 0; i < size; i++){ \
            pkmn.name[i] = cJSON_GetArrayItem(arr, i)->valueint; \
        } \
    }
    #define FIELD_PADDING(size) memset(pkmn.padding, 0, size) // zero out any potential padding to ensure memcmp works correctly.

    POKEMON_FIELDS

    #undef FIELD
    #undef FIELD_STRING
    #undef FIELD_ARRAY
    #undef FIELD_PADDING
    return pkmn;
}

lua_State *pokemon_to_lua(Pokemon *pkmn, lua_State *L){
    lua_newtable(L);

    #define FIELD(type, name) { \
        lua_pushinteger(L, pkmn->name); \
        lua_setfield(L, -2, #name); \
    }
    #define FIELD_STRING(name, size) { \
        lua_pushstring(L, pkmn->name); \
        lua_setfield(L, -2, #name); \
    }
    #define FIELD_ARRAY(type, name, size) { \
        lua_newtable(L); \
        for(int i = 0; i < size; i++){ \
            lua_pushinteger(L, pkmn->name[i]); \
            lua_rawseti(L, -2, i+1); \
        } \
        lua_setfield(L, -2, #name); \
    }
    #define FIELD_PADDING(size)

    POKEMON_FIELDS

    #undef FIELD
    #undef FIELD_STRING
    #undef FIELD_ARRAY
    #undef FIELD_PADDING

    return L;
}

Pokemon pokemon_from_lua(lua_State *L, int index){
    Pokemon pkmn;

    #define FIELD(type, name) { \
        lua_getfield(L, index, #name); \
        pkmn.name = lua_tointeger(L, -1); \
        lua_pop(L, 1); \
    }
    #define FIELD_STRING(name, size) { \
        lua_getfield(L, index, #name); \
        strcpy(pkmn.name, lua_tostring(L, -1)); \
        lua_pop(L, 1); \
    }
    #define FIELD_ARRAY(type, name, size) { \
        lua_getfield(L, index, #name); \
        for(int i = 0; i < size; i++){ \
            lua_rawgeti(L, -1, i+1); \
            pkmn.name[i] = lua_tointeger(L, -1); \
            lua_pop(L, 1); \
        } \
        lua_pop(L, 1); \
    }
    #define FIELD_PADDING(size) memset(pkmn.padding, 0, size)

    POKEMON_FIELDS

    #undef FIELD
    #undef FIELD_STRING
    #undef FIELD_ARRAY
    #undef FIELD_PADDING

    return pkmn;
}

cJSON *billboard_to_json(Billboard *bb){
    cJSON *root = cJSON_CreateObject();

    #define FIELD(type, name) cJSON_AddNumberToObject(root, #name, bb->name)
    #define FIELD_STRING(name, size) cJSON_AddStringToObject(root, #name, bb->name)
    #define FIELD_ARRAY(type, name, size) { \
        cJSON *arr = cJSON_CreateArray(); \
        for(int i = 0; i < size; i++){ \
            cJSON_AddItemToArray(arr, cJSON_CreateNumber(bb->name[i])); \
        } \
        cJSON_AddItemToObject(root, #name, arr);\
    }
    #define FIELD_PADDING(size)

    BILLBOARD_FIELDS

    #undef FIELD
    #undef FIELD_STRING
    #undef FIELD_ARRAY
    #undef FIELD_PADDING
    
    return root;
}

Billboard billboard_from_json(cJSON *obj){
    Billboard bb;

    #define FIELD(type, name) bb.name = cJSON_GetObjectItem(obj, #name)->valueint
    #define FIELD_STRING(name, size) strcpy(bb.name, cJSON_GetObjectItem(obj, #name)->valuestring)
    #define FIELD_ARRAY(type, name, size) { \
        cJSON *arr = cJSON_GetObjectItem(obj, #name); \
        for(int i = 0; i < size; i++){ \
            bb.name[i] = cJSON_GetArrayItem(arr, i)->valueint; \
        } \
    }
    #define FIELD_PADDING(size) memset(bb.padding, 0, size)

    BILLBOARD_FIELDS

    #undef FIELD
    #undef FIELD_STRING
    #undef FIELD_ARRAY
    #undef FIELD_PADDING

    return bb;
}

lua_State *billboard_to_lua(Billboard *bb, lua_State *L){
    lua_newtable(L);

    #define FIELD(type, name) { \
        lua_pushinteger(L, bb->name); \
        lua_setfield(L, -2, #name); \
    }
    #define FIELD_STRING(name, size) { \
        lua_pushstring(L, bb->name); \
        lua_setfield(L, -2, #name); \
    }
    #define FIELD_ARRAY(type, name, size) { \
        lua_newtable(L); \
        for(int i = 0; i < size; i++){ \
            lua_pushinteger(L, bb->name[i]); \
            lua_rawseti(L, -2, i+1); \
        } \
        lua_setfield(L, -2, #name); \
    }
    #define FIELD_PADDING(size)

    BILLBOARD_FIELDS

    #undef FIELD
    #undef FIELD_STRING
    #undef FIELD_ARRAY
    #undef FIELD_PADDING

    return L;
}

Billboard billboard_from_lua(lua_State *L, int index){
    Billboard bb;

    #define FIELD(type, name) { \
        lua_getfield(L, index, #name); \
        bb.name = lua_tointeger(L, -1); \
        lua_pop(L, 1); \
    }
    #define FIELD_STRING(name, size) { \
        lua_getfield(L, index, #name); \
        strcpy(bb.name, lua_tostring(L, -1)); \
        lua_pop(L, 1); \
    }
    #define FIELD_ARRAY(type, name, size) { \
        lua_getfield(L, index, #name); \
        for(int i = 0; i < size; i++){ \
            lua_rawgeti(L, -1, i+1); \
            bb.name[i] = lua_tointeger(L, -1); \
            lua_pop(L, 1); \
        } \
        lua_pop(L, 1); \
    }
    #define FIELD_PADDING(size) memset(bb.padding, 0, size)

    BILLBOARD_FIELDS

    #undef FIELD
    #undef FIELD_STRING
    #undef FIELD_ARRAY
    #undef FIELD_PADDING

    return bb;
}

cJSON *actor_to_json(Actor *actor, char include_party){
    cJSON *root = cJSON_CreateObject();

    #define FIELD(type, name) cJSON_AddNumberToObject(root, #name, actor->name)
    #define FIELD_STRING(name, size) cJSON_AddStringToObject(root, #name, actor->name)
    #define FIELD_ARRAY(type, name, size) { \
        cJSON *arr = cJSON_CreateArray(); \
        for(int i = 0; i < size; i++){ \
            cJSON_AddItemToArray(arr, cJSON_CreateNumber(actor->name[i])); \
        } \
        cJSON_AddItemToObject(root, #name, arr);\
    }
    #define FIELD_PADDING(size)

    ACTOR_FIELDS

    #undef FIELD
    #undef FIELD_STRING
    #undef FIELD_ARRAY
    #undef FIELD_PADDING

    cJSON *billboard = billboard_to_json(&actor->billboard);
    cJSON_AddItemToObject(root, "billboard", billboard);

    if(include_party){
        cJSON *party = cJSON_CreateArray();
        for(int i = 0; i < 6; i++){
            if(actor->party[i].species == 0) break;
            cJSON *pkmn = pokemon_to_json(&actor->party[i]);
            cJSON_AddItemToArray(party, pkmn);
        }
        cJSON_AddItemToObject(root, "party", party);
    }

    return root;
}

Actor actor_from_json(cJSON *obj){
    Actor actor;

    #define FIELD(type, name) actor.name = cJSON_GetObjectItem(obj, #name)->valueint
    #define FIELD_STRING(name, size) strcpy(actor.name, cJSON_GetObjectItem(obj, #name)->valuestring)
    #define FIELD_ARRAY(type, name, size) { \
        cJSON *arr = cJSON_GetObjectItem(obj, #name); \
        for(int i = 0; i < size; i++){ \
            actor.name[i] = cJSON_GetArrayItem(arr, i)->valueint; \
        } \
    }
    #define FIELD_PADDING(size) memset(actor.padding, 0, size) // zero out any potential padding to ensure memcmp works correctly.

    ACTOR_FIELDS

    #undef FIELD
    #undef FIELD_STRING
    #undef FIELD_ARRAY
    #undef FIELD_PADDING

    cJSON *billboard = cJSON_GetObjectItem(obj, "billboard");
    actor.billboard = billboard_from_json(billboard);

    memset(actor.party, 0, sizeof(actor.party));
    cJSON *party = cJSON_GetObjectItem(obj, "party");
    for(int i = 0; i < 6; i++){
        cJSON *pkmn_json = cJSON_GetArrayItem(party, i);
        if(!pkmn_json) break;
        actor.party[i] = pokemon_from_json(pkmn_json);
    }

    return actor;
}

lua_State *actor_to_lua(Actor *actor, lua_State *L){
    lua_newtable(L);

    #define FIELD(type, name) { \
        lua_pushinteger(L, actor->name); \
        lua_setfield(L, -2, #name); \
    }
    #define FIELD_STRING(name, size) { \
        lua_pushstring(L, actor->name); \
        lua_setfield(L, -2, #name); \
    }
    #define FIELD_ARRAY(type, name, size) { \
        lua_newtable(L); \
        for(int i = 0; i < size; i++){ \
            lua_pushinteger(L, actor->name[i]); \
            lua_rawseti(L, -2, i+1); \
        } \
        lua_setfield(L, -2, #name); \
    }
    #define FIELD_PADDING(size)

    ACTOR_FIELDS

    #undef FIELD
    #undef FIELD_STRING
    #undef FIELD_ARRAY
    #undef FIELD_PADDING

    billboard_to_lua(&actor->billboard, L);
    lua_setfield(L, -2, "billboard");

    lua_newtable(L);
    for(int i = 0; i < 6; i++){
        if(actor->party[i].species == 0) break;
        pokemon_to_lua(&actor->party[i], L);
        lua_rawseti(L, -2, i+1);
    }
    lua_setfield(L, -2, "party");

    return L;
}

Actor actor_from_lua(lua_State *L, int index){
    Actor actor;

    #define FIELD(type, name) { \
        lua_getfield(L, index, #name); \
        actor.name = lua_tointeger(L, -1); \
        lua_pop(L, 1); \
    }
    #define FIELD_STRING(name, size) { \
        lua_getfield(L, index, #name); \
        strcpy(actor.name, lua_tostring(L, -1)); \
        lua_pop(L, 1); \
    }
    #define FIELD_ARRAY(type, name, size) { \
        lua_getfield(L, index, #name); \
        for(int i = 0; i < size; i++){ \
            lua_rawgeti(L, -1, i+1); \
            actor.name[i] = lua_tointeger(L, -1); \
            lua_pop(L, 1); \
        } \
        lua_pop(L, 1); \
    }
    #define FIELD_PADDING(size) memset(actor.padding, 0, size)

    ACTOR_FIELDS

    #undef FIELD
    #undef FIELD_STRING
    #undef FIELD_ARRAY
    #undef FIELD_PADDING

    lua_getfield(L, index, "billboard");
    actor.billboard = billboard_from_lua(L, -1);
    lua_pop(L, 1);

    memset(actor.party, 0, sizeof(actor.party));
    lua_getfield(L, index, "party");
    for(int i = 0; i < 6; i++){
        lua_rawgeti(L, -1, i+1);
        if(lua_isnil(L, -1)){
            lua_pop(L, 1);
            break;
        } 
        actor.party[i] = pokemon_from_lua(L, -1);
        lua_pop(L, 1);
    }
    lua_pop(L, 1);

    return actor;
}

char compare_actors(Actor *a, Actor*b){
    char res = 0;
    if(memcmp(&(a->party), &(b->party), sizeof(a->party)) != 0){
        res |= PARTY_DIFFERS;
    }
    if(memcmp(&(a->billboard), &(b->billboard), sizeof(Actor) - offsetof(Actor, billboard)) != 0){
        res |= ACTOR_DIFFERS;
    }
    return res;
}