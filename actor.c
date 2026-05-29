#include "actor.h"
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
        actor->billboard.pos[2]/65536.0);
    fprintf(log, "  billboard anim_type: %d\n", actor->billboard.anim_type);
    fprintf(log, "  billboard anim_frame: %d\n", actor->billboard.anim_frame);

    for(int i = 0; i < 6; i++){
        if(actor->party[i].species == 0) break;
        fprintf(log, "  party[%d]:\n", i);
        fprintf(log, "    species: %d\n", actor->party[i].species);
        fprintf(log, "    gender: %d\n", actor->party[i].gender);
        fprintf(log, "    forme: %d\n", actor->party[i].forme);
        fprintf(log, "    ability: %d\n", actor->party[i].ability);
        fprintf(log, "    name: %s\n", actor->party[i].name);
        fprintf(log, "    level: %d\n", actor->party[i].level);
        fprintf(log, "    item: %d\n", actor->party[i].held_item);
        fprintf(log, "    curr_hp: %d\n", actor->party[i].curr_hp);
        fprintf(log, "    stats: %d %d %d %d %d %d\n",
            actor->party[i].stats[0], 
            actor->party[i].stats[1],
            actor->party[i].stats[2], 
            actor->party[i].stats[3],
            actor->party[i].stats[4], 
            actor->party[i].stats[5]);
        fprintf(log, "    moves: %d %d %d %d\n",
            actor->party[i].moves[0], 
            actor->party[i].moves[1],
            actor->party[i].moves[2], 
            actor->party[i].moves[3]);
    }

    fclose(log);
}

cJSON *pokemon_to_json(Pokemon *pkmn){
    cJSON *root = cJSON_CreateObject();

    cJSON_AddNumberToObject(root, "species", pkmn->species);
    cJSON_AddNumberToObject(root, "forme", pkmn->forme);
    cJSON_AddNumberToObject(root, "gender", pkmn->gender);
    cJSON_AddNumberToObject(root, "ability", pkmn->ability);
    cJSON_AddStringToObject(root, "name", pkmn->name);
    cJSON_AddNumberToObject(root, "level", pkmn->level);
    cJSON_AddNumberToObject(root, "held_item", pkmn->held_item);
    cJSON_AddNumberToObject(root, "curr_hp", pkmn->curr_hp);

    cJSON *stats = cJSON_CreateArray();
    for(int i = 0; i < 6; i++)
        cJSON_AddItemToArray(stats, cJSON_CreateNumber(pkmn->stats[i]));
    cJSON_AddItemToObject(root, "stats", stats);

    cJSON *moves = cJSON_CreateArray();
    for(int i = 0; i < 4; i++)
        cJSON_AddItemToArray(moves, cJSON_CreateNumber(pkmn->moves[i]));
    cJSON_AddItemToObject(root, "moves", moves);

    return root;
}

Pokemon json_to_pokemon(cJSON *obj){
    Pokemon pkmn;

    pkmn.species = cJSON_GetObjectItem(obj, "species")->valueint;
    pkmn.forme = cJSON_GetObjectItem(obj, "forme")->valueint;
    pkmn.gender = cJSON_GetObjectItem(obj, "gender")->valueint;
    pkmn.ability = cJSON_GetObjectItem(obj, "ability")->valueint;
    strcpy(pkmn.name, cJSON_GetObjectItem(obj, "name")->valuestring);
    pkmn.level = cJSON_GetObjectItem(obj, "level")->valueint;
    pkmn.held_item = cJSON_GetObjectItem(obj, "held_item")->valueint;
    pkmn.curr_hp = cJSON_GetObjectItem(obj, "curr_hp")->valueint;

    cJSON *stats = cJSON_GetObjectItem(obj, "stats");
    for(int i = 0; i < 6; i++)
        pkmn.stats[i] = cJSON_GetArrayItem(stats, i)->valueint;

    cJSON *moves = cJSON_GetObjectItem(obj, "moves");
    for(int i = 0; i < 4; i++)
        pkmn.moves[i] = cJSON_GetArrayItem(moves, i)->valueint;

    return pkmn;
}

char compare_pokemon(Pokemon *a, Pokemon *b){
    if(a->species != b->species) return PARTY_DIFFERS;
    if(a->forme != b->forme) return PARTY_DIFFERS;
    if(a->gender != b->gender) return PARTY_DIFFERS;
    if(a->ability != b->ability) return PARTY_DIFFERS;
    if(strcmp(a->name, b->name) != 0) return PARTY_DIFFERS;
    if(a->level != b->level) return PARTY_DIFFERS;
    if(a->held_item != b->held_item) return PARTY_DIFFERS;
    if(a->curr_hp != b->curr_hp) return PARTY_DIFFERS;

    for(int i = 0; i < 6; i++){
        if(a->stats[i] != b->stats[i]) return PARTY_DIFFERS;
    }

    for(int i = 0; i < 4; i++){
        if(a->moves[i] != b->moves[i]) return PARTY_DIFFERS;
    }

    return 0;
}

cJSON *party_to_json(Actor *actor){
    cJSON *party = cJSON_CreateArray();
    for(int i = 0; i < 6; i++){
        if(actor->party[i].species == 0) break;
        cJSON_AddItemToArray(party, pokemon_to_json( &(actor->party[i]) ));
    }
    return party;
}

cJSON *actor_to_json(Actor *actor, char include_party){
    cJSON *root = cJSON_CreateObject();

    cJSON_AddNumberToObject(root, "id", actor->id);
    cJSON_AddStringToObject(root, "name", actor->name);
    cJSON_AddNumberToObject(root, "pronouns", actor->pronouns);
    cJSON_AddNumberToObject(root, "map", actor->map);

    cJSON *billboard = cJSON_CreateObject();
    cJSON *pos = cJSON_CreateIntArray((int*)actor->billboard.pos, 3);
    cJSON_AddItemToObject(billboard, "pos", pos);
    cJSON_AddNumberToObject(billboard, "sprite", actor->billboard.sprite);
    cJSON_AddNumberToObject(billboard, "anim_type", actor->billboard.anim_type);
    cJSON_AddNumberToObject(billboard, "anim_frame", actor->billboard.anim_frame);
    cJSON_AddItemToObject(root, "billboard", billboard);

    if (include_party){
        cJSON *party = party_to_json(actor);
        cJSON_AddItemToObject(root, "party", party);
    }

    return root;
}

Actor json_to_actor(cJSON *obj){
    Actor actor;

    actor.id = cJSON_GetObjectItem(obj, "id")->valueint;
    strcpy(actor.name, cJSON_GetObjectItem(obj, "name")->valuestring);
    actor.pronouns = cJSON_GetObjectItem(obj, "pronouns")->valueint;
    actor.map = cJSON_GetObjectItem(obj, "map")->valueint;

    cJSON *billboard = cJSON_GetObjectItem(obj, "billboard");
    cJSON *pos = cJSON_GetObjectItem(billboard, "pos");
    for(int i = 0; i < 3; i++){
        actor.billboard.pos[i] = cJSON_GetArrayItem(pos, i)->valuedouble;
    }
    actor.billboard.sprite = cJSON_GetObjectItem(billboard, "sprite")->valueint;
    actor.billboard.anim_type = cJSON_GetObjectItem(billboard, "anim_type")->valueint;
    actor.billboard.anim_frame = cJSON_GetObjectItem(billboard, "anim_frame")->valueint;

    cJSON *party = cJSON_GetObjectItem(obj, "party");
    memset(actor.party, 0, sizeof(actor.party));
    for(int i = 0; i < 6; i++){
        cJSON *pkmn = cJSON_GetArrayItem(party, i);
        if(!pkmn) break;
        actor.party[i] = json_to_pokemon(pkmn);
    }

    return actor;
}

char compare_actors(Actor *a, Actor*b){
    char res = 0;
    for(int i = 0; i < 6; i++){
        res |= compare_pokemon(&(a->party[i]), &(b->party[i]));
    }

    if(a->id != b->id) res |= ACTOR_DIFFERS;
    if(strcmp(a->name, b->name) != 0) res |= ACTOR_DIFFERS;
    if(a->pronouns != b->pronouns) res |= ACTOR_DIFFERS;
    if(a->map != b->map) res |= ACTOR_DIFFERS;
    if(a->billboard.sprite != b->billboard.sprite) res |= ACTOR_DIFFERS;
    if(a->billboard.anim_type != b->billboard.anim_type) res |= ACTOR_DIFFERS;
    if(a->billboard.anim_frame != b->billboard.anim_frame) res |= ACTOR_DIFFERS;
    for(int i = 0; i < 3; i++){
        if(a->billboard.pos[i] != b->billboard.pos[i]) res |= ACTOR_DIFFERS;
    }

    return res;
}