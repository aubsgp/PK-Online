"""
Design document:
- The server will maintain four main data structures:
    1. players: A dict of player structs indexed by player ID. Each player object will contain the public-facing state of the player, such as their position, map, party, and other information that can be safely shared with other clients.
    2. private_states: A dict of PrivatePlayerState objects indexed by player ID. This contains tokens, chunk coordinates, timestamps for last communication and last significant update, and IP addresses for each player.
    3. world: A dict of sets of player IDs indexed by chunk coordinates. Used to quickly determine which neighbors to send to the player.

Currently, I'm taking a websockets approach, where the server maintains a persistent connection to each client. This allows for real-time updates and reduces the overhead of establishing connections for each update.
As well, since most people are stationary most of the time, this minimizes the amount of data sent -- players will only receive updates when something changes, rather than polling for updates at a fixed rate.
Most of the logic has been greatly simplified and does not need much explaining. Suffice to say, player state is communicated when it changes to players in a 3x3 chunk area around the player. If the player's chunk changes, or if the player disconnects,
the server will additionally send "kick" notifs to any affected players.
"""

#TODO: when initializing, players need to be given a location, even if its just (0, 0, 0). so maybe check for location and if it exists, thats the location, if not, its (0, 0, 0).


from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from operator import add
import random
from collections import defaultdict
import threading
import http
import asyncio
import websockets
from websockets.http11 import Response
from websockets.datastructures import Headers
from pokedex import ENCODING, SPECIES, ABILITIES, MOVES, ITEMS

MAX_PLAYERS = 1000
TIMEOUT_TIMER = 5 #seconds

# Flags
PLAYER_DIFFERS = 0b00000001
PARTY_DIFFERS  = 0b00000010

class PrivatePlayerState:
    # Server-only
    chunk: tuple # (map, chunk_x, chunk_z). note that in-game, y is height.
    token: int
    connection: websockets.WebSocketServerProtocol

players = {}
private_states = {}

world = defaultdict(set) # dict of lists of player IDs indexed by tuples (map, chunk_x, chunk_z), where map = 0 if overworld, and the map header otherwise. chunk_x and chunk_y are optimizations for pruning display in the overworld, and are 0 if map != 0.

GENDER = ["♂", "♀", "Ø", "Ø"]

def stringify(plat_string):
    result = ""
    for char in plat_string:
        if char == 0xFFFF or char == 0x0000:
            break
        result += ENCODING.get(char, "?")
    return result

def get_chunk(player):
    map = player["map"]
    pos = player["billboard"]["pos"]
    if map == 0:
        return (map, int(pos[0]/(32 * 1<<16)), int(pos[2]/(32 * 1<<16)))
    else:
        return (map, 0, 0)

def neighboring_chunks(chunk):
    neighbors = set()
    neighbors.add(chunk)
    if chunk[0] == 0:
        for i in range(chunk[1]-1, chunk[1]+2):
            for j in range(chunk[2]-1, chunk[2]+2):
               neighbors.add((0, i, j))
    return neighbors

# This function will, given a set of chunks, return a list of players in those chunks. client_id = "who's asking?"
def survey_chunks(chunks, client_id = None):
    seen = []
    for chunk in chunks:
        if chunk in world:
            for plyr_id in world[chunk]:
                if plyr_id != client_id:
                    seen.append(plyr_id)
    return seen


def init_player(websocket):
    i = 0
    for j in range(1, MAX_PLAYERS):
        if j not in players:
            i = j
            break
    if i == 0:
        return None, None
    else:
        players[i] = {"id": i}
        private_states[i] = PrivatePlayerState()
        private_states[i].token = random.randint(0x00000000, 0xFFFFFFFF)
        private_states[i].chunk = (0, 0, 0)
        world[(0, 0, 0)].add(i)
        private_states[i].connection = websocket
        return players[i]["id"], private_states[i].token


async def send_update(plyr_id, delta):
    try:
        if plyr_id in private_states:
            neighbor_socket = private_states[plyr_id].connection
            await neighbor_socket.send(json.dumps(delta))
    except websockets.exceptions.ConnectionClosed:
        pass


async def handler(websocket):
    id, token = init_player(websocket)
    if id is None:
        await websocket.send(json.dumps({"error": "Server full"}))
        return
    else:
        await websocket.send(json.dumps({"id": id, "token": token}))

    try:
        while True:
            message = await websocket.recv()
            data = json.loads(message)
            if id != data["plyr"]["id"] or token != data["token"]:
                await websocket.close(code = 1008, reason = "Invalid token or ID.")
                break
            flags = data["flags"]

            old_chunk = private_states[id].chunk
            if flags & PLAYER_DIFFERS: # Just update the non-party info.
                old_party = players[id].get("party", [])
                players[id] = data["plyr"].copy()
                players[id]["party"] = old_party

            if flags & PARTY_DIFFERS: # Just update the party info.
                players[id]["party"] = data["plyr"]["party"]

            try: # Sometimes, the client might not have the position info properly set up at the start.
                new_chunk = get_chunk(players[id])
                if new_chunk != old_chunk:
                    private_states[id].chunk = new_chunk
                    world[old_chunk].discard(id)
                    world[new_chunk].add(id)
                    old_neighboring_chunks = neighboring_chunks(old_chunk)
                    new_neighboring_chunks = neighboring_chunks(new_chunk)

                    farewell = old_neighboring_chunks - new_neighboring_chunks
                    kick = survey_chunks(farewell, id)
                    for plyr_id in kick:
                        await send_update(plyr_id, {"keep": [], "kick": [id]})

                    hello = new_neighboring_chunks - old_neighboring_chunks
                    new_neighbors = survey_chunks(hello, id)
                    keep = [players[plyr_id] for plyr_id in new_neighbors]

                    delta = {
                        "keep": keep,
                        "kick": kick
                    }
                    await websocket.send(json.dumps(delta))
                
                current_neighbors = survey_chunks(neighboring_chunks(get_chunk(players[id])), id)
                for plyr_id in current_neighbors:
                    await send_update(plyr_id, {"keep": [players[id]], "kick": []})

            except KeyError:
                pass

                
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        if id in players:
            chunk = private_states[id].chunk
            world[chunk].discard(id)
            neighbors = survey_chunks(neighboring_chunks(chunk), id)
            for plyr_id in neighbors:
                await send_update(plyr_id, {"keep": [], "kick": [id]})
            del players[id]
            del private_states[id]

def generate_admin_page():
    try:
        response = """
        <html>
        <head>
        <meta charset="UTF-8">
        <title>Admin Page</title>
        </head>
        <body>
        <h1>Admin Page</h1>
        """
        for i, (key, plyr) in enumerate(players.items()):
            if "billboard" not in plyr:
                continue
            response += f"""
                <details style ="border: 1px solid black; padding: 5px;">
                <summary>{key}: {stringify(plyr.get("name"))}</summary>
                <div>
                    Position: {plyr.get("billboard").get("pos")[0]/65536.0}, {plyr.get("billboard").get("pos")[1]/65536.0}, {plyr.get("billboard").get("pos")[2]/65536.0}<br>
                    Map: {plyr.get("map")}<br>
            """
            party = plyr.get("party", [])
            for j, mon in enumerate(party):
                mon_moves = mon.get("moves", [])
                mon_moves = [MOVES[move] for move in mon_moves]

                status = mon.get("status", 0)
                status_str = []
                if status:
                    if status & 0b00000111:
                        status_str.append("Asleep")
                    if status & 0b00001000:
                        status_str.append("Poisoned")
                    if status & 0b00010000:
                        status_str.append("Burned")
                    if status & 0b00100000:
                        status_str.append("Frozen")
                    if status & 0b01000000:
                        status_str.append("Paralyzed")
                    if status & 0b10000000:
                        status_str.append("Badly Poisoned")
                else:
                    status_str.append("None")
                
                response += f"""
                    <details style ="border: 1px solid gray; padding: 5px; margin: 5px;">
                    <summary>{stringify(mon.get("name"))} the {SPECIES[mon.get("species")][mon.get("forme")]} {GENDER[mon.get("gender")]}</summary>
                    <div>
                        Ability: {ABILITIES[mon.get("ability")]}<br>
                        Level: {mon.get("level")}<br>
                        Current HP: {mon.get("curr_hp")}/{mon.get("stats")[0]}<br>
                        Status: {" and ".join(status_str)}<br>
                        Stats: {mon.get("stats")}<br>
                        Moves: {mon_moves}<br>
                        Held Item: {ITEMS[mon.get("held_item")]}<br>
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
                if (0, j, i) in world and len(world[(0, j, i)]) > 0 and len(players) > 0:
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
        response += """
        </body>
        </html>
        """

        return response

    except Exception as e:
        return f"<html><body><h1>Error generating admin page</h1><p>{str(e)}</p></body></html>"


def process_request(connection, request):
    if request.path == "/admin":
        body = generate_admin_page().encode()
        headers = Headers([
            ("Content-Type", "text/html; charset=utf-8"),
            ("Content-Length", str(len(body))),
        ])
        return Response(http.HTTPStatus.OK, "OK", headers, body)
    return None


async def main():
    ip = "192.168.0.6"
    port = 6868
    server = await websockets.serve(handler, ip, port, process_request=process_request)
    print(f"Server started on ws://{ip}:{port}")
    try:
        await asyncio.Future()  # Hand control to the event loop and run forever
    finally:
        for id, state in list(private_states.items()):
            try:
                await state.connection.close(code=1001, reason="Server shutting down")
            except:
                pass
        server.close()
        await server.wait_closed()


asyncio.run(main())