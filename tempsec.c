#include "cJSON.h"
#include "lua.h"
#include "actor.h"
#include <stdio.h>
#include <stdbool.h>
#include <stdarg.h>
#include <windows.h>
#include <winhttp.h>

#define MAX_NEIGHBORS 100
#define MAX_ACTORS 1000
#define UPDATE_TIMER 8 // approximately 1/120 of a second.

static HINTERNET session;
static HINTERNET connection;
static HINTERNET websocket;

CRITICAL_SECTION lock;

static volatile char update_flag = 0; // 0 means no update, 1st bit set means actor update, 2nd bit set means party update.
static volatile bool running = true;
static volatile bool fatal_error = false;
static volatile bool should_update = false;
HANDLE send_thread;
HANDLE receive_thread;

static int lowest_index = 1;
static bool is_alive[MAX_NEIGHBORS+1];
static int8_t delta[MAX_NEIGHBORS+1];
static uint8_t indices[MAX_ACTORS+1];
static Actor neighbors[MAX_NEIGHBORS+1]; //~300 * 100 = 29 kb, probably negligible even in worst-case scenario where all slots are filled and changing every update.
static Actor player;
static unsigned int token;

static void error_log(const char *message){
    FILE *f = fopen("debug.log", "a");
    if(f){
        fprintf(f, "%s\n", message);
        fflush(f);
        fclose(f);
    }
    return;
}

//------------------------
//lua_L functions and structs are missing from the desmume's lua dll, so if we commit to compiling against it, we have to implement them ourselves. 
typedef struct luaL_Reg {
    const char *name;
    lua_CFunction func;
} luaL_Reg;

static int luaL_error(lua_State *L, const char *fmt, ...) {
    va_list argp;
    va_start(argp, fmt);
    lua_pushvfstring(L, fmt, argp);
    va_end(argp);
    return lua_error(L);
}

static lua_Integer luaL_checkinteger(lua_State *L, int idx) {
    if (!lua_isnumber(L, idx)) {
        lua_pushstring(L, "expected number argument");
        lua_error(L);
    }
    return lua_tointeger(L, idx);
}

static char *luaL_checkstring(lua_State *L, int idx) {
    if (!lua_isstring(L, idx)) {
        lua_pushstring(L, "expected string argument");
        lua_error(L);
    }
    return (char *)lua_tostring(L, idx);
}

static void luaL_register(lua_State *L, const char *name, const luaL_Reg *lib) {
    lua_createtable(L, 0, 0);
    for (int i = 0; lib[i].name != NULL; i++) {
        lua_pushcclosure(L, lib[i].func, 0);
        lua_setfield(L, -2, lib[i].name);
    }
    if (name) {
        lua_pushvalue(L, -1);
        lua_setfield(L, -10002, name);  // -10002 is LUA_GLOBALSINDEX in Lua 5.1
    }
}
// End of lua_L implementations.
//------------------------


//------------------------
//Some basic utility bitwise functions, since lua doesn't natively allow bitwise operations.
static int lua_xor(lua_State *L){
    lua_Integer a = luaL_checkinteger(L, 1);
    lua_Integer b = luaL_checkinteger(L, 2);
    lua_pushinteger(L, a ^ b);
    return 1;
}

static int lua_band(lua_State *L){
    lua_Integer a = luaL_checkinteger(L, 1);
    lua_Integer b = luaL_checkinteger(L, 2);
    lua_pushinteger(L, a & b);
    return 1;
}

static int lua_bitshift(lua_State *L){
    lua_Integer value = luaL_checkinteger(L, 1);
    const char *direction = luaL_checkstring(L, 2);
    lua_Integer shift = luaL_checkinteger(L, 3);

    if (strcmp(direction, "<<") == 0) {
        lua_pushinteger(L, value << shift);
    } else if (strcmp(direction, ">>") == 0) {
        lua_pushinteger(L, value >> shift);
    } else {
        luaL_error(L, "Invalid shift direction: %s", direction);
    }

    return 1;
}
//------------------------


//------------------------
//Our threads for communicating with the server
DWORD WINAPI send_thread_func(LPVOID _){
    Sleep(1000);
    while(running){
        ULONGLONG before = GetTickCount64();
        char update_flag_copy;
        Actor player_copy;
        EnterCriticalSection(&lock);
        update_flag_copy = update_flag;
        update_flag = 0;
        player_copy = player;
        LeaveCriticalSection(&lock);

        if(update_flag_copy){
            cJSON *root = cJSON_CreateObject();
            cJSON_AddNumberToObject(root, "token", token);
            cJSON *actor_obj;

            if (update_flag_copy & ACTOR_DIFFERS){
                actor_obj = actor_to_json(&player_copy, 0);
            }else{
                actor_obj = cJSON_CreateObject();
                cJSON_AddNumberToObject(actor_obj, "id", player_copy.id);
            }

            if (update_flag_copy & PARTY_DIFFERS){
                cJSON *party_obj = party_to_json(&player_copy);
                cJSON_AddItemToObject(actor_obj, "party", party_obj);
            }

            cJSON_AddItemToObject(root, "actor", actor_obj);
            char *json_string = cJSON_PrintUnformatted(root);
            cJSON_Delete(root);

            DWORD result = WinHttpWebSocketSend(websocket, WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE, (const char *)json_string, strlen(json_string));
            free(json_string);
            if(result != ERROR_SUCCESS){
                error_log("In send_thread_func: Failed to send websocket message");
                fatal_error = true;
                return 1;
            }
        }

        ULONGLONG elapsed = GetTickCount64() - before;
        if(elapsed < UPDATE_TIMER){
            Sleep((DWORD)(UPDATE_TIMER - elapsed));
        }
    }
    return 0;
}

DWORD WINAPI receive_thread_func(LPVOID _){
    DWORD buffer_size = 128 * 1024; // 128 kb should be more than enough for 100 neighbors and their parties, but we can increase this if needed.
    char *buffer = (char *)malloc(buffer_size);
    if(!buffer){
        fatal_error = true;
        return 1;
    }

    while(running){
        DWORD bytes_read;
        WINHTTP_WEB_SOCKET_BUFFER_TYPE type;
        DWORD result = WinHttpWebSocketReceive(websocket, buffer, buffer_size, &bytes_read, &type);
        if(result != ERROR_SUCCESS){
            fatal_error = true;
            free(buffer);
            return 1;
        }
        if(type != WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE){
            continue;
        }
        if(type == WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE){
            running = false;
            free(buffer);
            return 0;
        }
        buffer[bytes_read] = '\0';
        cJSON *update_obj = cJSON_Parse(buffer);

        cJSON *keep_obj = cJSON_GetObjectItem(update_obj, "keep");
        cJSON *kick_obj = cJSON_GetObjectItem(update_obj, "kick");
        int player_count = cJSON_GetArraySize(keep_obj);
        int goner_count = cJSON_GetArraySize(kick_obj);

        // We want to spend as little time in the critical section as possible.
        // To facilitate this, we copy down the local indices of all present neighbors, and use those to create updates. Then, we update the actual info under another mutex.
        Actor temp_neighbors[MAX_NEIGHBORS+1];
        uint8_t temp_indices[MAX_ACTORS+1] = {0};
        bool temp_is_alive[MAX_NEIGHBORS+1] = {false};
        int8_t temp_delta[MAX_NEIGHBORS+1] = {0};
        EnterCriticalSection(&lock);
        memcpy(temp_delta, delta, sizeof(delta));
        memcpy(temp_indices, indices, sizeof(indices));
        memcpy(temp_is_alive, is_alive, sizeof(is_alive));
        LeaveCriticalSection(&lock);
        uint8_t to_update[MAX_NEIGHBORS+1] = {0};
        bool something_happened = false;

        // Remove all tombstones from the our array of actors.
        for(int i = 0; i < goner_count; i++){
            int id = cJSON_GetArrayItem(kick_obj, i)->valueint;
            if(id >= 0 && id < MAX_ACTORS && temp_indices[id] != 0xff){
                // There's no need to zero out the actor in memory. Just mark the slot as free so it can be reused.
                int freed_index = temp_indices[id];
                temp_indices[id] = 0xff;
                temp_is_alive[freed_index] = false;
                temp_delta[freed_index] = -1;
                something_happened = true;
                if(freed_index < lowest_index){
                    // lowest_index can only ever decrease when an actor gets kicked from the list.
                    lowest_index = freed_index;
                }
            }
        }

        // Add or update all players with meaningful changes.
        int num_to_update = 0;
        for(int i = 0; i < player_count; i++){
            Actor plyr = json_to_actor(cJSON_GetArrayItem(keep_obj, i));
            // If this player isn't currently in our local array and there's a free slot, add them to the neighbors array and mark the slot as used.
            if(temp_indices[plyr.id] == 0xff && lowest_index < MAX_NEIGHBORS){
                temp_indices[plyr.id] = lowest_index;
                to_update[num_to_update++] = lowest_index;
                temp_neighbors[lowest_index] = plyr;
                temp_is_alive[lowest_index] = true;
                temp_delta[lowest_index++] = 1;
                something_happened = true;
                // This should ensure that lowest_index always points to the next free slot in the local indices array.
                while(lowest_index < MAX_NEIGHBORS && temp_is_alive[lowest_index]){
                    lowest_index++;
                }
            // If this player is already in our local array, just update their data in the neighbors array.
            }else if(temp_indices[plyr.id] != 0xff){
                something_happened = true;
                temp_delta[temp_indices[plyr.id]] = 1;
                temp_neighbors[temp_indices[plyr.id]] = plyr;
                to_update[num_to_update++] = temp_indices[plyr.id];
            }
        }

        EnterCriticalSection(&lock);
        if(something_happened){
            should_update = true;
        }
        memcpy(indices, temp_indices, sizeof(indices));
        memcpy(is_alive, temp_is_alive, sizeof(is_alive));
        memcpy(delta, temp_delta, sizeof(delta));
        for(int i = 0; i < num_to_update; i++){
            neighbors[to_update[i]] = temp_neighbors[to_update[i]];
        }
        LeaveCriticalSection(&lock);
        cJSON_Delete(update_obj);
    }

    free(buffer);
    return 0;
}
//------------------------


//------------------------
//Open a connection with the server and get a persistent websocket handle. Also get the player's assigned id and session token, which will be needed for future requests.
static int HANDSHAKE(lua_State *L){
    bool ok;

    session = WinHttpOpen(L"TemporalSecretary/0.1", WINHTTP_ACCESS_TYPE_NO_PROXY, WINHTTP_NO_PROXY_NAME,WINHTTP_NO_PROXY_BYPASS,0);
    if(session == NULL){
        error_log("In HANDSHAKE: Failed to open HTTP session handle\n");
        return luaL_error(L, "Failed to open HTTP session handle.");
    }

    connection = WinHttpConnect(session, L"localhost", 8080, 0);
    if(connection == NULL){
        error_log("In HANDSHAKE: Failed to open HTTP connection handle\n");
        WinHttpCloseHandle(session);
        return luaL_error(L, "Failed to open HTTP connection handle.");
    }
    
    //Send a blank "GET" and update to a persisten websocket connection. 
    HINTERNET request = WinHttpOpenRequest(connection, L"GET", L"/", NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
    if(request == NULL){
        error_log("In HANDSHAKE: Failed to open HTTP request handle");
        return luaL_error(L, "Failed to open HTTP request handle.");
    }
    WinHttpSetOption(request, WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET, NULL, 0);

    ok = WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, NULL, 0, 0, 0);
    if(!ok){
        WinHttpCloseHandle(request);
        error_log("In HANDSHAKE: Failed to send HTTP request");
        return luaL_error(L, "Failed to send HTTP request.");
    }
    
    ok = WinHttpReceiveResponse(request, NULL);
    if(!ok){
        WinHttpCloseHandle(request);
        error_log("In HANDSHAKE: Failed to receive HTTP response");
        return luaL_error(L, "Failed to receive HTTP response.");
    }


    websocket = WinHttpWebSocketCompleteUpgrade(request, NULL);
    if(websocket == NULL){
        WinHttpCloseHandle(request);
        error_log("In HANDSHAKE: Failed to upgrade to websocket");
        return luaL_error(L, "Failed to upgrade to websocket.");
    }
     WinHttpCloseHandle(request);

    char response[64];
    DWORD bytes_read;
    WINHTTP_WEB_SOCKET_BUFFER_TYPE type;
    DWORD result = WinHttpWebSocketReceive(websocket, response, sizeof(response), &bytes_read, &type);
    if (result != ERROR_SUCCESS){
        WinHttpCloseHandle(websocket);
        error_log("In HANDSHAKE: Failed to receive websocket response");
        return luaL_error(L, "Failed to receive websocket response.");
    }
    response[bytes_read] = '\0';
    sscanf(response, "%u %u", &player.id, &token);
    lua_pushinteger(L, player.id);

    FILE *log = fopen("debug.log", "a");
    fprintf(log, "Handshake returned player id %u and token %u\n", player.id, token);
    fflush(log);
    fclose(log);

    
    memset(indices, 0xff, MAX_ACTORS+1);
    
    InitializeCriticalSection(&lock);
    send_thread = CreateThread(NULL, 0, send_thread_func, NULL, 0, NULL);
    receive_thread = CreateThread(NULL, 0, receive_thread_func, NULL, 0, NULL);

    return 1;
}

static int update_player(lua_State *L){
    Actor temp;

    lua_getfield(L, 1, "id");
    temp.id = lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, 1, "name");
    strcpy(temp.name, lua_tostring(L, -1));
    lua_pop(L, 1);

    lua_getfield(L, 1, "pronouns");
    temp.pronouns = lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, 1, "map");
    temp.map = lua_tointeger(L, -1);
    lua_pop(L, 1);

    // BILLBOARD PROCESSING
    lua_getfield(L, 1, "billboard");

    lua_getfield(L, -1, "pos");
    for(int i = 0; i < 3; i++){
        lua_rawgeti(L, -1, i+1);
        temp.billboard.pos[i] = lua_tointeger(L, -1);
        lua_pop(L, 1);
    }
    lua_pop(L, 1);

    lua_getfield(L, -1, "sprite");
    temp.billboard.sprite = lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, -1, "anim_type");
    temp.billboard.anim_type = lua_tointeger(L, -1);
    lua_pop(L, 1);
    
    lua_getfield(L, -1, "anim_frame");
    temp.billboard.anim_frame = lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_pop(L, 1);

    // PARTY PROCESSING
    lua_getfield(L, 1, "party");
    memset(&temp.party, 0, sizeof(temp.party));
    for(int i = 0; i < 6; i++){
        Pokemon pkmn;
        lua_rawgeti(L, -1, i+1);
        if(lua_isnil(L, -1)){
            break;
        }

        lua_getfield(L, -1, "species");
        pkmn.species = lua_tointeger(L, -1);
        lua_pop(L, 1);

        lua_getfield(L, -1, "forme");
        pkmn.forme = lua_tointeger(L, -1);
        lua_pop(L, 1);

        lua_getfield(L, -1, "gender");
        pkmn.gender = lua_tointeger(L, -1);
        lua_pop(L, 1);

        lua_getfield(L, -1, "ability");
        pkmn.ability = lua_tointeger(L, -1);
        lua_pop(L, 1);

        lua_getfield(L, -1, "name");
        strcpy(pkmn.name, lua_tostring(L, -1));
        lua_pop(L, 1);

        lua_getfield(L, -1, "level");
        pkmn.level = lua_tointeger(L, -1);
        lua_pop(L, 1);

        lua_getfield(L, -1, "curr_hp");
        pkmn.curr_hp = lua_tointeger(L, -1);
        lua_pop(L, 1);

        lua_getfield(L, -1, "stats");
        for(int j = 0; j < 6; j++){
            lua_rawgeti(L, -1, j+1);
            pkmn.stats[j] = lua_tointeger(L, -1);
            lua_pop(L, 1);
        }
        lua_pop(L, 1);

        lua_getfield(L, -1, "held_item");
        pkmn.held_item = lua_tointeger(L, -1);
        lua_pop(L, 1);

        lua_getfield(L, -1, "moves");
        for(int j = 0; j < 4; j++){
            lua_rawgeti(L, -1, j+1);
            pkmn.moves[j] = lua_tointeger(L, -1);
            lua_pop(L, 1);
        }
        lua_pop(L, 1);

        temp.party[i] = pkmn;
        lua_pop(L, 1);
    }
    lua_pop(L, 1);

    EnterCriticalSection(&lock);
    update_flag |= compare_actors(&player, &temp);
    player = temp;
    LeaveCriticalSection(&lock);

    return 0;
}

static int get_neighbors(lua_State *L){
    if(fatal_error){
        luaL_error(L, "Fatal server-related error. Consult debug.log for details.");
        return 1;
    }

    Actor temp_neighbors[MAX_NEIGHBORS+1];
    int8_t temp_delta[MAX_NEIGHBORS+1];
    EnterCriticalSection(&lock);
    if(!should_update){
        lua_pushboolean(L, 0);
        LeaveCriticalSection(&lock);
        return 1;
    }
    memcpy(temp_neighbors, neighbors, sizeof(neighbors));
    memcpy(temp_delta, delta, sizeof(delta));
    memset(delta, 0, sizeof(delta));
    should_update = false;
    LeaveCriticalSection(&lock);

    lua_newtable(L); // stack: return table (RT)
    lua_newtable(L); // stack: update table (UT)
    lua_newtable(L); // stack: update table (UT), kick table (KT)

    int update_index = 1;
    int kick_index = 1;
    for(int i = 0; i < MAX_NEIGHBORS; i++){
        if(temp_delta[i] == 1){
            lua_newtable(L); // stack: return table (RT), update table (UT), kick table (KT), neighbor table (NT)

            lua_pushinteger(L, i); // RT, UT, KT, NT, (local) id
            lua_setfield(L, -2, "id"); // RT, UT, KT, NT <- id field added

            lua_pushstring(L, temp_neighbors[i].name); // RT, UT, KT, NT, name
            lua_setfield(L, -2, "name"); // RT, UT, KT, NT <- name field added

            lua_pushinteger(L, temp_neighbors[i].pronouns); // RT, UT, KT, NT <- pronouns index added
            lua_setfield(L, -2, "pronouns"); // RT, UT, KT, NT <- pronouns field added

            lua_pushinteger(L, temp_neighbors[i].map); // RT, UT, KT, NT, map
            lua_setfield(L, -2, "map"); // RT, UT, KT, NT <- map field added

            // BILLBOARD PROCESSING
            lua_newtable(L); // RT, UT, KT, NT, billboard table (BT)

            lua_newtable(L); // UT, KT, NT, BT, pos table (PoT)
            for(int j = 0; j < 3; j++){
                lua_pushinteger(L, temp_neighbors[i].billboard.pos[j]); // RT, UT, KT, NT, BT, PoT, coordinate j
                lua_rawseti(L, -2, j+1); // RT, UT, KT, NT, BT, PoT <- coordinate j added
            }
            lua_setfield(L, -2, "pos"); // RT, UT, KT, NT, BT <- pos field added

            lua_pushinteger(L, temp_neighbors[i].billboard.sprite); // RT, UT, KT, NT, BT, sprite
            lua_setfield(L, -2, "sprite"); // RT, UT, KT, NT, BT <- sprite field added

            lua_pushinteger(L, temp_neighbors[i].billboard.anim_type); // RT, UT, KT, NT, BT, anim_type
            lua_setfield(L, -2, "anim_type"); // RT, UT, KT, NT, BT <- anim_type field added

            lua_pushinteger(L, temp_neighbors[i].billboard.anim_frame); // RT, UT, KT, NT, BT, anim_frame
            lua_setfield(L, -2, "anim_frame"); // RT, UT, KT, NT, BT <- anim_frame field added

            lua_setfield(L, -2, "billboard"); // RT, UT, KT, NT <- billboard field added
            
            // PARTY PROCESSING
            lua_newtable(L); // UT, KT, NT, party table (PaT)
            for(int j = 0; j < 6; j++){
                if(temp_neighbors[i].party[j].species == 0){
                    break;
                }

                lua_newtable(L); // UT, KT, NT, PaT, Pokemon table (PkT)

                lua_pushinteger(L, temp_neighbors[i].party[j].species); // RT, UT, KT, NT, PaT, PkT, species
                lua_setfield(L, -2, "species"); // UT, KT, NT, PaT, PkT <- species field added

                lua_pushinteger(L, temp_neighbors[i].party[j].forme); // RT, UT, KT, NT, PaT, PkT, forme
                lua_setfield(L, -2, "forme"); // UT, KT, NT, PaT, PkT <- forme field added

                lua_pushinteger(L, temp_neighbors[i].party[j].gender); // RT, UT, KT, NT, PaT, PkT, gender
                lua_setfield(L, -2, "gender"); // UT, KT, NT, PaT, PkT <- gender field added

                lua_pushinteger(L, temp_neighbors[i].party[j].ability); // RT, UT, KT, NT, PaT, PkT, ability
                lua_setfield(L, -2, "ability"); // UT, KT, NT, PaT, PkT <- ability field added

                lua_pushstring(L, temp_neighbors[i].party[j].name); // RT, UT, KT, NT, PaT, PkT, name
                lua_setfield(L, -2, "name"); // UT, KT, NT, PaT, PkT <- name field added

                lua_pushinteger(L, temp_neighbors[i].party[j].level); // RT, UT, KT, NT, PaT, PkT, level
                lua_setfield(L, -2, "level"); // UT, KT, NT, PaT, PkT <- level field added

                lua_newtable(L); // UT, KT, NT, PaT, PkT, stats table (StT)
                for(int k = 0; k < 6; k++){
                    lua_pushinteger(L, temp_neighbors[i].party[j].stats[k]); // RT, UT, KT, NT, PaT, PkT, StT, stat k
                    lua_rawseti(L, -2, k+1); // UT, KT, NT, PaT, PkT, StT <- stat k added
                }
                lua_setfield(L, -2, "stats"); // UT, KT, NT, PaT, PkT <- stats field added

                lua_newtable(L); // UT, KT, NT, PaT, PkT, moves table (MvT)
                for(int k = 0; k < 4; k++){
                    lua_pushinteger(L, temp_neighbors[i].party[j].moves[k]); // RT, UT, KT, NT, PaT, PkT, MvT, move k
                    lua_rawseti(L, -2, k+1); // UT, KT, NT, PaT, PkT, MvT <- move k added
                }
                lua_setfield(L, -2, "moves"); // UT, KT, NT, PaT, PkT <- moves field added
                
                lua_pushinteger(L, temp_neighbors[i].party[j].held_item); // RT, UT, KT, NT, PaT, PkT, held_item
                lua_setfield(L, -2, "held_item"); // UT, KT, NT, PaT, PkT <- held_item field added

                lua_pushinteger(L, temp_neighbors[i].party[j].curr_hp); // RT, UT, KT, NT, PaT, PkT, curr_hp
                lua_setfield(L, -2, "curr_hp"); // UT, KT, NT, PaT, PkT <- curr_hp field added

                lua_rawseti(L, -2, j+1); // UT, KT, NT, PaT <- Pokemon added at index j+1
            }
            lua_setfield(L, -2, "party"); // RT, UT, KT, NT <- party field added
            
            lua_rawseti(L, -3, update_index++); // RT, UT <- NT added at index i+1, KT
        }else if(temp_delta[i] == -1){
            lua_pushinteger(L, i); // RT, UT, KT, (local) id.
            lua_rawseti(L, -2, kick_index++); // RT, UT, KT <- id added at index i+1.
        }
    }
    
    lua_setfield(L, -3, "kick"); // RT <- KT added as field "kick", UT
    lua_setfield(L, -2, "keep"); // RT <- UT added as field "update"

    return 1; //We want to get down to 1 return value so that Lua can more easily check the more common case where "false" gets returned.
}

static const luaL_Reg secretarylib[] = {
    {"xor", lua_xor},
    {"band", lua_band},
    {"shift", lua_bitshift},
    {"HANDSHAKE", HANDSHAKE},
    {"update_player", update_player},
    {"get_neighbors", get_neighbors},
    {NULL, NULL}
};

__declspec(dllexport) int luaopen_TemporalSecretary(lua_State *L){
    FILE *log = fopen("debug.log", "w");
    fprintf(log, "TemporalSecretary loaded\n");
    fflush(log);
    fclose(log);

    luaL_register(L, "secretary", secretarylib);
    return 1;
}

//If we fail, we don't want to make the game crash as well, which means cleaning up after ourselves.
BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved){
    if(fdwReason == DLL_PROCESS_DETACH){
        running = false;
        if(lpvReserved == NULL){
            WaitForSingleObject(send_thread, 2000);
            CloseHandle(send_thread);

            WaitForSingleObject(receive_thread, 2000);
            CloseHandle(receive_thread);

            WinHttpWebSocketClose(websocket, WINHTTP_WEB_SOCKET_SUCCESS_CLOSE_STATUS, NULL, 0);
            WinHttpCloseHandle(websocket);

            if(connection != NULL){
                WinHttpCloseHandle(connection);
            }

            if(session != NULL){
                WinHttpCloseHandle(session);
            }
        }
        DeleteCriticalSection(&lock);
    }
    return TRUE;
}

//gcc -shared -o TemporalSecretary.dll tempsec.c actor.c cJSON.c -I"include" -L"." -llua51 -lwinhttp -static-libgcc