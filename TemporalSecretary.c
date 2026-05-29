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
#define UPDATE_TIMER 0

static HINTERNET session;
static HINTERNET connection;

CRITICAL_SECTION lock;

static volatile bool running = true;
static volatile bool fatal_error = false;
static volatile bool should_update = false;
HANDLE updating_thread;

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

static bool POST(){

    cJSON *root = cJSON_CreateObject();
    cJSON_AddNumberToObject(root, "token", token);
    EnterCriticalSection(&lock);
    Actor temp = player;
    LeaveCriticalSection(&lock);
    cJSON *player_obj = actor_to_json(&temp);
    cJSON_AddItemToObject(root, "player", player_obj);
    char *json_string = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);

    bool ok;
    HINTERNET request = WinHttpOpenRequest(
        connection,
        L"POST",
        L"/",
        NULL,
        WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        0
    );
    if(request == NULL){
        error_log("In POST: Failed to open HTTP request handle");
        free(json_string);
        return false;
    }

    ok = WinHttpSendRequest(
        request,
        WINHTTP_NO_ADDITIONAL_HEADERS,
        0,
        (LPVOID)json_string,
        strlen(json_string),
        strlen(json_string),
        0
    );
    if(!ok){
        error_log("In POST: Failed to send HTTP request");
        WinHttpCloseHandle(request);
        free(json_string);
        return false;
    }

    ok = WinHttpReceiveResponse(
        request,
        NULL
    );
    if(!ok){
        error_log("In POST: Failed to receive HTTP response");
        WinHttpCloseHandle(request);
        free(json_string);
        return false;
    }
    
    WinHttpCloseHandle(request);
    free(json_string);
    return true;
}

static cJSON *GET(){
    cJSON *signature_root = cJSON_CreateObject();
    cJSON_AddNumberToObject(signature_root, "id", player.id);
    cJSON_AddNumberToObject(signature_root, "token", token);
    char *json_string = cJSON_PrintUnformatted(signature_root);
    cJSON_Delete(signature_root);

    bool ok;

    HINTERNET request = WinHttpOpenRequest(
        connection,
        L"GET",
        L"/",
        NULL,
        WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        0
    );
    if(request == NULL){
        error_log("In GET: Failed to open HTTP request handle");
        free(json_string);
        return NULL;
    }

    ok = WinHttpSendRequest(
        request,
        WINHTTP_NO_ADDITIONAL_HEADERS,
        0,
        (LPVOID)json_string,
        strlen(json_string),
        strlen(json_string),
        0
    );
    if(!ok){
        error_log("In GET: Failed to send HTTP request");
        WinHttpCloseHandle(request);
        free(json_string);
        return NULL;
    }

    ok = WinHttpReceiveResponse(
        request,
        NULL
    );
    if(!ok){
        error_log("In GET: Failed to receive HTTP response");
        WinHttpCloseHandle(request);
        free(json_string);
        return NULL;
    }

    DWORD response_size;
    WinHttpQueryDataAvailable(
        request,
        &response_size
    );

    cJSON *response_root = NULL;
    if(response_size>0){
        char *response = (char *)malloc(response_size + 1);
        DWORD bytes_read;
        WinHttpReadData(
            request,
            (LPVOID)response,
            response_size,
            &bytes_read
        );
        response[bytes_read] = '\0';
        response_root = cJSON_Parse(response);
        free(response);
        if(response_root == NULL){
            error_log("In GET: HTTP response improperly formatted.");
            WinHttpCloseHandle(request);
            free(json_string);
            return NULL;
        }
    }else{
        error_log("In GET: HTTP response empty.");
        WinHttpCloseHandle(request);
        free(json_string);
        return NULL;
    }
    WinHttpCloseHandle(request);
    free(json_string);
    return response_root;
}

DWORD WINAPI start_thread(LPVOID param){
    error_log("In server-facing thread: Thread started\n");
    int update_timer = (int)(intptr_t)param;
    Sleep(1000); // We do a brief initial sleep so the lua script has time to update us on the player state before we start sending updates. A bit hacky, might fix later teehee.
    while(running){
        ULONGLONG before = GetTickCount64();

        fatal_error = !POST();
        if(fatal_error){
            return 1;
        }
        
        cJSON *update_obj = GET();
        if(update_obj == NULL){
            fatal_error = true;
            error_log("In server-facing thread: GET failed\n");
            return 1;
        }

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

        ULONGLONG after = GetTickCount64();
        ULONGLONG elapsed_time = (after - before);
        if(elapsed_time < update_timer){
            Sleep((DWORD)(update_timer - elapsed_time));
        }
    }
    return 0;
}

static int HANDSHAKE(lua_State *L){
    bool ok;

    session = WinHttpOpen(
        L"TemporalSecretary/0.1",
        WINHTTP_ACCESS_TYPE_NO_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS,
        0
    );
    if(session == NULL){
        error_log("In HANDSHAKE: Failed to open HTTP session handle\n");
        return luaL_error(L, "Failed to open HTTP session handle.");
    }
    connection = WinHttpConnect(
        session,
        L"localhost",
        8080,
        0
    );
    if(connection == NULL){
        error_log("In HANDSHAKE: Failed to open HTTP connection handle\n");
        WinHttpCloseHandle(session);
        return luaL_error(L, "Failed to open HTTP connection handle.");
    }
    
    char *body = "handshake";
    HINTERNET request = WinHttpOpenRequest(
        connection,
        L"POST",
        L"/",
        NULL,
        WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        0
    );
    if(request == NULL){
        error_log("In HANDSHAKE: Failed to open HTTP request handle");
        return luaL_error(L, "Failed to open HTTP request handle.");
    }
    ok = WinHttpSendRequest(
        request,
        WINHTTP_NO_ADDITIONAL_HEADERS,
        0,
        (LPVOID)body,
        strlen(body),
        strlen(body),
        0
    );
    if(!ok){
        WinHttpCloseHandle(request);
        error_log("In HANDSHAKE: Failed to send HTTP request");
        return luaL_error(L, "Failed to send HTTP request.");
    }
    
    ok = WinHttpReceiveResponse(
        request,
        NULL
    );
    if(!ok){
        WinHttpCloseHandle(request);
        error_log("In HANDSHAKE: Failed to receive HTTP response");
        return luaL_error(L, "Failed to receive HTTP response.");
    }
    DWORD response_size;
    WinHttpQueryDataAvailable(
        request,
        &response_size
    );

    if(response_size>0){
        char *response = (char *)malloc(response_size + 1);
        DWORD bytes_read;
        WinHttpReadData(
            request,
            (LPVOID)response,
            response_size,
            &bytes_read
        );
        response[bytes_read] = '\0';
        sscanf(response, "%u %u", &player.id, &token);
        free(response);

        FILE *log = fopen("debug.log", "a");
        fprintf(log, "Handshake returned player id %u and token %u\n", player.id, token);
        fflush(log);
        fclose(log);

        lua_pushinteger(L, player.id);
    }else{
        WinHttpCloseHandle(request);
        error_log("In HANDSHAKE: No handshake response.\n");
        return luaL_error(L, "No handshake response.");
    }

    WinHttpCloseHandle(request);
    
    memset(indices, 0xff, MAX_ACTORS);
    
    InitializeCriticalSection(&lock);
    updating_thread = CreateThread(NULL, 0, start_thread, (LPVOID)UPDATE_TIMER, 0, NULL);

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

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved){
    if(fdwReason == DLL_PROCESS_DETACH){
        running = false;
        if(lpvReserved == NULL){
            WaitForSingleObject(updating_thread, 2000);
            CloseHandle(updating_thread);
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

//gcc -shared -o TemporalSecretary.dll TemporalSecretary.c actor.c cJSON.c -I"include" -L"." -llua51 -lwinhttp -static-libgcc