class_name Economy
extends Node
## Bomb Defusal money and buying (child of the Match autoload: /root/Match/Economy).
##
## Everyone starts a half with START_MONEY and earns more for kills, plants,
## defuses and at the end of every round (more for a win, a growing loss
## bonus for a losing streak). Money is spent in the buy menu (X) — guns,
## armour and grenades — while standing near your own team's spawn during the
## freeze time and the first BUY_TIME seconds of the round.
##
## What you carry survives the round if you do: a survivor keeps their gun,
## armour and grenades; anyone who died starts the next round with only the
## pistol and the knife. Sides swapping at halftime resets money and gear.
##
## Server-authoritative. Money lives in NetworkManager.roster[id].money (so
## every peer sees it on the scoreboard); the server keeps each player's gear
## for the next spawn in `_gear`. Buying sends a request; the server checks
## money, buy time and zone and hands out the item to every peer.

## Money shows up on the HUD as "+$300 Kill (AR-7)".
signal money_event(amount: int, text: String)
## A refused buy (local player): why.
signal buy_refused(reason: String)

const START_MONEY := 800
## Everyone's money at the start of each overtime half.
const OVERTIME_MONEY := 10000
const MAX_MONEY := 16000
## Buying stays open this long after the freeze time.
const BUY_TIME := 20.0
## You can buy within this distance (m, flat) of one of your side's spawns.
const BUY_ZONE_RADIUS := 12.0

const WIN_REWARD := 3250
## Winning by the bomb (exploded or defused).
const BOMB_WIN_REWARD := 3500
const LOSS_REWARD := 1400
const LOSS_STEP := 500
const MAX_LOSS_REWARD := 3400
## Every attacker when the bomb was planted but the round lost anyway.
const PLANTED_LOSS_BONUS := 800
const PLANT_REWARD := 300
const DEFUSE_REWARD := 300
const KILL_REWARD := 300
## Kill rewards that differ from KILL_REWARD, by weapon id.
const KILL_REWARDS := { "knife": 1500, "shotgun": 900, "smg": 600, "sniper": 100 }

## Buy menu items: id -> { name, price, kind ("primary" / "armor" / "grenade") }.
const ITEMS := {
	"rifle": { "name": "AR-7 Assault Rifle", "price": 2700, "kind": "primary" },
	"smg": { "name": "V-10 SMG", "price": 1250, "kind": "primary" },
	"shotgun": { "name": "M-12 Shotgun", "price": 1100, "kind": "primary" },
	"sniper": { "name": "LR-50 Sniper", "price": 4750, "kind": "primary" },
	"vest": { "name": "Kevlar Vest", "price": 650, "kind": "armor" },
	"vest_helmet": { "name": "Kevlar + Helmet", "price": 1000, "kind": "armor" },
	"he": { "name": "HE Grenade", "price": 300, "kind": "grenade", "grenade": Throwables.Kind.HE },
	"flash": { "name": "Flashbang", "price": 200, "kind": "grenade", "grenade": Throwables.Kind.FLASH },
	"smoke": { "name": "Smoke Grenade", "price": 300, "kind": "grenade", "grenade": Throwables.Kind.SMOKE },
	"molotov": { "name": "Molotov", "price": 400, "kind": "grenade", "grenade": Throwables.Kind.MOLOTOV },
}
## Buy menu layout: columns of item ids.
const MENU := [
	["rifle", "smg", "shotgun", "sniper"],
	["vest", "vest_helmet"],
	["he", "flash", "smoke", "molotov"],
]
const MENU_TITLES: PackedStringArray = ["Guns", "Armour", "Grenades"]
## Most grenades of one kind (others: 1) and in total.
const GRENADE_LIMITS := { Throwables.Kind.FLASH: 2 }
const MAX_GRENADES := 4
const HELMET_PRICE := 350

## Server: peer_id -> gear for the next spawn (see default_gear()).
var _gear: Dictionary = {}
## Server: rounds lost in a row, per team.
var _loss_streak: PackedInt32Array = [0, 0]


static func default_gear() -> Dictionary:
	return { "primary": "", "armor": 0.0, "helmet": false, "nades": [0, 0, 0, 0] }


static func is_active() -> bool:
	return Match.mode == GameConfig.Mode.BOMB


# -----------------------------------------------------------------------------
# Queries (every peer)
# -----------------------------------------------------------------------------

static func money_of(peer_id: int) -> int:
	return NetworkManager.roster.get(peer_id, {}).get("money", START_MONEY)


## Seconds of buy time left in this round (0 = closed).
static func buy_time_left() -> float:
	var b: BombRules = Match.bomb
	if not is_active() or b.round_number == 0 or Match.is_ended():
		return 0.0
	if b.phase == BombRules.Phase.FREEZE:
		return b.phase_time_left + BUY_TIME
	if b.phase == BombRules.Phase.LIVE:
		return maxf(BUY_TIME - (b.round_time - b.phase_time_left), 0.0)
	return 0.0


## Whether `p` stands close enough to one of their side's spawns.
static func in_buy_zone(p: PlayerController) -> bool:
	var level: Level = NetworkManager.current_level()
	if level == null or p == null:
		return false
	var spawns: Array[Marker3D] = level.red_spawn_points if Match.bomb.is_attacker(p.peer_id) else level.blue_spawn_points
	if spawns.is_empty():
		spawns = level.spawn_points
	for m: Marker3D in spawns:
		var d := m.global_position - p.global_position
		if Vector2(d.x, d.z).length() <= BUY_ZONE_RADIUS and absf(d.y) < 4.0:
			return true
	return spawns.is_empty()


## "" if `p` may buy right now, else why not.
static func buy_block_reason(p: PlayerController) -> String:
	if not is_active():
		return "Buying is only in Bomb Defusal"
	if p == null or p.health.is_dead:
		return "You are dead"
	if buy_time_left() <= 0.0:
		return "Buy time is over"
	if not in_buy_zone(p):
		return "Go back to your spawn to buy"
	return ""


## Price of `item` for `p` right now (the helmet alone if the vest is full).
static func price_of(item: String, p: PlayerController) -> int:
	var price: int = ITEMS[item].price
	if item == "vest_helmet" and p and p.health.armor >= Health.MAX_ARMOR:
		price = HELMET_PRICE
	return price


## "" if `p` could buy `item` (money aside), else why not.
static func item_block_reason(item: String, p: PlayerController) -> String:
	if not ITEMS.has(item):
		return "Unknown item"
	var info: Dictionary = ITEMS[item]
	match info.kind:
		"primary":
			if p.primary_id == item:
				return "You already have it"
		"armor":
			var full: bool = p.health.armor >= Health.MAX_ARMOR
			if full and (item == "vest" or p.health.helmet):
				return "You already have it"
		"grenade":
			var kind: int = info.grenade
			var have: int = p.throwables.counts.get(kind, 0)
			if have >= GRENADE_LIMITS.get(kind, 1):
				return "You can't carry more"
			var total := 0
			for k: int in p.throwables.counts:
				total += p.throwables.counts[k]
			if total >= MAX_GRENADES:
				return "You can't carry more grenades"
	return ""


# -----------------------------------------------------------------------------
# Buying
# -----------------------------------------------------------------------------

## Local player buys `item` (the server checks everything).
func request_buy(item: String) -> void:
	if multiplayer.is_server():
		_server_buy(multiplayer.get_unique_id(), item)
	elif NetworkManager.is_online():
		_request_buy.rpc_id(1, item)


@rpc("any_peer", "call_remote", "reliable")
func _request_buy(item: String) -> void:
	if multiplayer.is_server():
		_server_buy(multiplayer.get_remote_sender_id(), item)


func _server_buy(peer_id: int, item: String) -> void:
	var level: Level = NetworkManager.current_level()
	var p: PlayerController = level.get_player(peer_id) if level else null
	var reason: String = buy_block_reason(p)
	if reason == "":
		reason = item_block_reason(item, p)
	var price: int = price_of(item, p) if reason == "" else 0
	if reason == "" and money_of(peer_id) < price:
		reason = "Not enough money"
	if reason != "":
		_tell_refused(peer_id, reason)
		return
	var info: Dictionary = ITEMS[item]
	match info.kind:
		"primary":
			p.net_sync.server_give_primary(item)
		"armor":
			p.health.server_set_armor(Health.MAX_ARMOR, p.health.helmet or item == "vest_helmet")
		"grenade":
			var counts: Array = p.throwables.counts_array()
			counts[info.grenade] += 1
			p.throwables.server_set_counts(counts)
	_add_money(peer_id, -price, "")
	NetworkManager.broadcast_roster()


func _tell_refused(peer_id: int, reason: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		buy_refused.emit(reason)
	elif NetworkManager.is_online():
		_buy_refused.rpc_id(peer_id, reason)


@rpc("authority", "call_remote", "reliable")
func _buy_refused(reason: String) -> void:
	buy_refused.emit(reason)


# -----------------------------------------------------------------------------
# Server: money
# -----------------------------------------------------------------------------

## Adds (or with a negative amount, takes) money; `text` != "" also shows
## the player a "+$300 Kill" line.
func _add_money(peer_id: int, amount: int, text: String) -> void:
	if not NetworkManager.roster.has(peer_id):
		return
	var before: int = money_of(peer_id)
	var after := clampi(before + amount, 0, MAX_MONEY)
	NetworkManager.roster[peer_id].money = after
	if text != "" and after != before:
		if peer_id == multiplayer.get_unique_id():
			money_event.emit(after - before, text)
		elif NetworkManager.is_online():
			_money_event.rpc_id(peer_id, after - before, text)


@rpc("authority", "call_remote", "reliable")
func _money_event(amount: int, text: String) -> void:
	money_event.emit(amount, text)


## Server: a new half (match start, halftime, overtime halves) — money and
## gear back to the start (`money` each).
func server_reset(money: int = START_MONEY) -> void:
	_gear.clear()
	_loss_streak = [0, 0]
	for id: int in NetworkManager.roster:
		NetworkManager.roster[id].money = money


## Server, at the start of each round before everyone respawns: survivors
## keep what they carry, the dead start over.
func server_prepare_round() -> void:
	_gear.clear()
	var level: Level = NetworkManager.current_level()
	if level == null:
		return
	for p in level.get_players():
		if p.health.is_dead:
			continue
		_gear[p.peer_id] = {
			"primary": p.primary_id,
			"armor": p.health.armor,
			"helmet": p.health.helmet and p.health.armor > 0.0,
			"nades": p.throwables.counts_array(),
		}


## Server: what `peer_id` spawns with in Bomb Defusal.
func gear_for(peer_id: int) -> Dictionary:
	return _gear.get(peer_id, default_gear())


## Server: called by Match.on_kill (Bomb Defusal).
func on_kill(killer_id: int, victim_id: int) -> void:
	if killer_id <= 0 or killer_id == victim_id or Match.is_friendly(killer_id, victim_id):
		return
	var level: Level = NetworkManager.current_level()
	var killer: PlayerController = level.get_player(killer_id) if level else null
	var victim: PlayerController = level.get_player(victim_id) if level else null
	var reward := KILL_REWARD
	var what := ""
	if victim and victim.health.last_cause in Throwables.NAMES.values():
		what = victim.health.last_cause
	elif killer and killer.current_weapon:
		reward = KILL_REWARDS.get(killer.current_weapon.data.weapon_id, KILL_REWARD)
		what = killer.current_weapon.data.display_name.get_slice(" ", 0)
	_add_money(killer_id, reward, "Kill" + (" (%s)" % what if what != "" else ""))


func on_plant(peer_id: int) -> void:
	_add_money(peer_id, PLANT_REWARD, "Bomb planted")
	NetworkManager.broadcast_roster()


func on_defuse(peer_id: int) -> void:
	_add_money(peer_id, DEFUSE_REWARD, "Bomb defused")


## Server: round rewards for both teams.
func on_round_end(winner: int, reason: String, planted: bool) -> void:
	var loser := 1 - winner
	_loss_streak[winner] = 0
	_loss_streak[loser] += 1
	var win := BOMB_WIN_REWARD if reason == "Bomb exploded" or reason == "Bomb defused" else WIN_REWARD
	var loss := mini(LOSS_REWARD + LOSS_STEP * (_loss_streak[loser] - 1), MAX_LOSS_REWARD)
	for id: int in NetworkManager.roster:
		var team: int = Match.get_team(id)
		if team == winner:
			_add_money(id, win, "Round won")
		elif team == loser:
			var bonus := PLANTED_LOSS_BONUS if planted and team == Match.bomb.attacking_team else 0
			_add_money(id, loss + bonus, "Round lost" + (" (bomb planted)" if bonus > 0 else ""))
	NetworkManager.broadcast_roster()
