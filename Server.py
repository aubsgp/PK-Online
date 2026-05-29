"""
Design document:
- The server will maintain four main data structures:
    1. players: a dict of player structs indexed by player ID. each player object will contain the public-facing state of the player, such as their position, map, party, and other information that can be safely shared with other clients.
    2. private_states: a dict of PrivatePlayerState objects indexed by player ID. this contains tokens, approximate locations, timestamps for last communication and last significant update, and IP addresses for each player.
    3. world: a dict of sets of player IDs indexed by approximate location. used to quickly determine which neighbors to send to the player.
    4. tombstones: a dict of dicts {player ID: expiration timer} indexed by approximate location. used to quickly communicate which neighbors have recently left a given location so that clients can remove them from their local view.

Currently, the idea is to have things be client-controlled, where the client will poll at a rate of 5Hz. The server will push nothing unless we run into bottlenecks related to player density.
Whenever the client updates the server, the server will update their info in players. They will also update the corresponding timestamps and apprxoimate locations. if the update has any notable delta (position, party, etc), it'll additionally note that.
    - If the player changes its approximate location, a tombstone is left at their prior location so any clients tracking them will know to cull them.
When the client does its generic poll for neighbors, the server does the following:
    - Asks: where is the client, approximately?
    - Looks up all players with nearby approximate locations in the world dict (i.e. same map header, or else within the 3x3 grid of neighboring chunks in the overworld).
        - These get compiled into a dict indexed by id.
    - Checks the list of tombstones. Any players here, and not in the already-compiled dict, get put into a separate dict of "goners" marked for cleanup.
    - Both are passed to the client through the dll. The client will then update any visible neighbors, rendering appropriate animations for movement as necessary, and delete any neighbors marked for cleanup.

Every 5 seconds, the server will iterate through the players list and check the timestamps in private_states. Any players who have not communicated within TIMEOUT_TIMER ms will be removed from the player list. their approximate location will be grabbed from the 
private info, used to find them in the world, and they'll be removed there as well. then, their private info will be deleted, and a tombstone will be placed at their approximate location.

All tombstones are created with a timestamp. When the server sweeps the player list, it will FIRST sweep through tombstones and delete any tombstones more than TIMEOUT_TIMER ms old. This ought to be sufficient -- any player who hasnt seen the tombstone within
that timer is about to be culled anyway, and will need to reconnect and completely rebuild their list of neighbors from scratch.

When a client moves chunks, or enters a new map, they'll communicate this to the server outside the usual polling rate. 
    - In the overworld, the server will tell them all players in the 3 chunks that have left their 3x3 surroundings, and all players that have entered, for culling and adding.
    - If they enter any non-overworld map, the server will just tell them all players in the map they've entered, and the client should know to fully clear their prior neighbor info and replace it with the new list of neighbors.
"""

#TODO: when initializing, players need to be given a location, even if its just (0, 0, 0). so maybe check for location and if it exists, thats the location, if not, its (0, 0, 0).


from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from operator import add
import random
import time
from collections import defaultdict
import threading
from turtle import width
from pokedex import species, abilities, moves, items

MAX_PLAYERS = 1000
TIMEOUT_TIMER = 5 #seconds

class PrivatePlayerState:
    # Server-only
    location: tuple # (map, chunk_x, chunk_z). note that in-game, y is height.
    token: int
    last_communication: float
    last_significant_update: float
    ip: str

players = {}
private_states = {}

world = defaultdict(set) # dict of lists of player IDs indexed by tuples (map, chunk_x, chunk_z), where map = 0 if overworld, and the map header otherwise. chunk_x and chunk_y are optimizations for pruning display in the overworld, and are 0 if map != 0.
tombstones = defaultdict(dict) # dict of dicts {player ID: expiration timer} indexed by the same (map, chunk_x, chunk_z) tuples as world. 

gender = ["♂", "♀", "Ø", "Ø"]

admin_page_start = """
<html>
<head>
<meta charset="UTF-8">
<title>Admin Page</title>
</head>
<body>
<h1>Admin Page</h1>
"""

admin_page_end = """
</body>
</html>
"""

def sweep():
    while True:
        time.sleep(TIMEOUT_TIMER)
        expire_time = time.time() - TIMEOUT_TIMER
        for plyr_id in list(private_states.keys()):
            if private_states[plyr_id].last_communication < expire_time:
                location = private_states[plyr_id].location
                world[location].discard(plyr_id)
                tombstones[location][plyr_id] = time.time()
                del players[plyr_id]
                del private_states[plyr_id]

threading.Thread(target=sweep, daemon=True).start()

def ApproximateLocation(player):
    map = player["map"]
    pos = player["billboard"]["pos"]
    if map == 0:
        return (map, int(pos[0]/(32 * 1<<16)), int(pos[2]/(32 * 1<<16)))
    else:
        return (map, 0, 0)

# This function will, given a list of locations, return a list of players and tombstones in those locations. client_id = "who's asking?"
def SurveyProgram(locations, client_id):
    keep = []
    kick = []
    # Keeping track of seen players makes it so that if a neighbor moves chunks and leaves behind a tombstone, the server correctly communicates to the client that they need to update the position rather than delete them.
    seen = {client_id}

    expire_time = time.time() - TIMEOUT_TIMER;

    for location in locations:
        if location in world:
            for plyr_id in world[location].copy():
                # We can optimize inactivity kicking by doing it here rather than checking constantly, and having a very infrequent check somewhere else.
                if private_states[plyr_id].last_communication < expire_time: # In the future, we will also check to see if we SHOULD update. For now, we update the client on all nearby players.
                    world[location].discard(plyr_id)
                    del players[plyr_id]
                    del private_states[plyr_id]
                    tombstones[location][plyr_id] = time.time()

                elif plyr_id not in seen:
                    keep.append(players[plyr_id])
                    seen.add(plyr_id)

    for location in locations:
        if location in tombstones:
            for goner_id in tombstones[location].copy():

                if tombstones[location][goner_id] < expire_time:
                    del tombstones[location][goner_id]

                elif goner_id not in seen:
                    kick.append(goner_id)
                    seen.add(goner_id) # Nontrivial chance that a player goes from, say, top-left to top-middle and then logs out, leaving two tombstones. This line prevents duplicates in our kick list.

    return {
        "keep": keep,
        "kick": kick
    }

#The meat of it.
class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args): # We overload this method to suppress the default logging behavior, which tends to clutter things.
        pass
    def do_POST(self):
        length = int(self.headers["Content-Length"])
        body = self.rfile.read(length)
        # Handshake handling. Should run once per user, will run again if they ctrl+r. This WILL give them a new ID, which is fine, because ID tracking is mainly for the purposes of rendering movement.
        if len(body) == 9 and body.decode() == "handshake":
            i = 0
            for j in range(1, MAX_PLAYERS):
                if j not in players:
                    i = j
                    break
            if i == 0:
                self.send_response(503)
                self.end_headers()
            else:
                players[i] = {"id": i}
                private_states[i] = PrivatePlayerState()
                private_states[i].token = random.randint(0x00000000, 0xFFFFFFFF)
                private_states[i].location = (0, 0, 0)
                world[(0, 0, 0)].add(i)
                private_states[i].last_communication = time.time()
                private_states[i].last_significant_update = time.time()
                private_states[i].ip = self.client_address[0]
                self.send_response(200)
                self.end_headers()
                print("Handshake returned player id: " + str(i) + " with token: " + str(private_states[i].token))
                self.wfile.write((str(i) + " " + str(private_states[i].token)).encode("utf-8"))
        # Handle normal player update. These requests should basically be coming in constantly.
        else:
            try:
                data = json.loads(body)
            except:
                print(body)
                self.send_response(400)
                self.end_headers()
                return
            plyr = data["player"]
            client_id = plyr["id"]
            if "map" not in plyr:
                return
            elif client_id <= 0 or client_id > MAX_PLAYERS or client_id not in players or client_id not in private_states or data["token"] != private_states[client_id].token:
                self.send_response(401)
                self.end_headers()
                return
            else:
                location = ApproximateLocation(plyr)
                old_location = private_states[client_id].location

                if location != private_states[client_id].location:
                    private_states[client_id].location = location
                    world[old_location].discard(client_id)
                    tombstones[old_location][client_id] = time.time()
                    world.setdefault(location, set()).add(client_id)

                private_states[client_id].location = location

                private_states[client_id].last_communication = time.time()
                if plyr != players[client_id]:
                    private_states[client_id].last_significant_update = time.time()

                players[client_id] = plyr

            self.send_response(200)
            self.end_headers()
        return
    
    def do_GET(self):
        if self.path == "/admin":
            self.send_response(200)
            response = admin_page_start
            for i, (key, plyr) in enumerate(players.items()):
                if "billboard" not in plyr:
                    continue
                response += f"""
                    <details style ="border: 1px solid black; padding: 5px;">
                    <summary>{key}: {plyr.get("name")}</summary>
                    <div>
                        Position: {plyr.get("billboard").get("pos")[0]/65536.0}, {plyr.get("billboard").get("pos")[1]/65536.0}, {plyr.get("billboard").get("pos")[2]/65536.0}<br>
                        Map: {plyr.get("map")}<br>
                """
                party = plyr.get("party", [])
                for j, mon in enumerate(party):
                    mon_moves = mon.get("moves", [])
                    mon_moves = [moves[move] for move in mon_moves]
                    response += f"""
                        <details style ="border: 1px solid gray; padding: 5px; margin: 5px;">
                        <summary>{mon.get("name")} the {species[mon.get("species")][mon.get("forme")]} {gender[mon.get("gender")]}</summary>
                        <div>
                            Ability: {abilities[mon.get("ability")]}<br>
                            Level: {mon.get("level")}<br>
                            Current HP: {mon.get("curr_hp")}/{mon.get("stats")[0]}<br>
                            Stats: {mon.get("stats")}<br>
                            Moves: {mon_moves}<br>
                            Held Item: {items[mon.get("held_item")]}<br>
                        </div>
                        </details>
                    """
                response += """
                    </div>
                    </details>
                """
            response += """
                <div>
                    Map of Player Density:
                </div>
                <style>table td { width: 32px; height: 32px; overflow: hidden; border: 1px solid black; }</style>
                <table style="table-layout:fixed; width:1024px; height:1024px; border-collapse:collapse">
            """
            response += ""
            response += f""
            for i in range(32):
                response += "<tr>"
                for j in range(32):
                    if (0, j, i) in world and len(world[(0, j, i)]) > 0:
                        print(world[(0, j, i)])
                        color = 0xffffff
                        delta = (len(world[(0, j, i)]) / len(players))*0xff
                        delta = int(delta)
                        delta = delta*0x010000 + delta*0x000100 + delta*0x000001
                        color = color - delta
                        response += f"<td style=\"background-color:#{color:06x};\"></td>"
                    else:
                        response += "<td></td>"
                response += "</tr>"
            response += "</table>"
            response += admin_page_end
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(response.encode("utf-8"))
            return

        else:
            length = int(self.headers["Content-Length"])
            body = self.rfile.read(length)
            data = json.loads(body)
            client_id = data.get("id")
            token = data.get("token")
            if client_id not in players or client_id not in private_states or token != private_states[client_id].token:
                self.send_response(403)
                self.end_headers()
                return
            elif private_states[client_id].location is None:
                self.send_response(400)
                self.end_headers()
                return
            private_states[client_id].last_communication = time.time()

            location = private_states[client_id].location
            to_search = set()
            if location[0] != 0:
                to_search.add(location)
            else:
                for i in range(location[1]-1, location[1]+2):
                    for j in range(location[2]-1, location[2]+2):
                        to_search.add((0, i, j))

            response = SurveyProgram(to_search, client_id)

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(response).encode("utf-8"))

Server = HTTPServer(("localhost", 8080), Handler)
print("Server starting on http://localhost:8080")
Server.serve_forever()