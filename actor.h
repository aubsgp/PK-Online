#ifndef ACTOR_H
#define ACTOR_H

#include "cJSON.h"
#include <stdint.h>

#define ACTOR_DIFFERS 0b00000001
#define PARTY_DIFFERS 0b00000010

typedef struct Pokemon {
    uint16_t species; //2
    uint8_t forme; //1 -> 3
    char gender; //1 -> 4
    uint8_t ability; //1 -> 5
    char name[11]; //11 -> 16
    uint8_t level; //1 -> 17
    int16_t stats[6]; //12 -> 29
    int16_t moves[4]; //8 -> 37
    int16_t held_item; //2 -> 39
    int16_t curr_hp; //2 -> 41
} Pokemon;

typedef struct Billboard {
    uint32_t pos[3]; //12
    uint8_t anim_type; //1 -> 13
    uint8_t anim_frame; //1 -> 14
    uint8_t sprite; //1 -> 15
} Billboard;

typedef struct Actor {
    uint16_t id; //2
    char name[11]; //11 -> 13
    char pronouns; //1 -> 14
    uint16_t map; //2 -> 16
    Billboard billboard; //15 -> 31
    Pokemon party[6]; //6*41=246 -> 277 bytes
} Actor;

cJSON *pokemon_to_json(Pokemon *pkmn);
Pokemon json_to_pokemon(cJSON *obj);
char compare_pokemon(Pokemon *a, Pokemon *b);

cJSON *party_to_json(Actor *actor);
cJSON *actor_to_json(Actor *actor, char include_party);
Actor json_to_actor(cJSON *obj);
char compare_actors(Actor *a, Actor *b);

void print_actor(Actor *actor);

#endif