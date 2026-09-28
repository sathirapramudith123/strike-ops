class_name LagCompensation
extends RefCounted
## Server-side hit detection with lag compensation.
##
## A client sees remote players INTERPOLATION_DELAY + ping in the past. When it
## fires, it sends the (estimated) server time it was looking at. The server
## rewinds every other player to that moment using their state history and
## tests the shot against analytic head/body shapes, so what the shooter saw
## is what counts — within MAX_REWIND to limit abuse.
##
## World geometry and non-player hitboxes (target dummies) use a normal
## physics raycast; the closest hit wins.

## World (1) + hitbox (3) layers.
const HIT_MASK := (1 << 0) | (1 << 2)
const BODY_RADIUS := 0.35
const HEAD_RADIUS := 0.2
## Head centre is this far below the top of the capsule.
const HEAD_DROP := 0.2


## Returns {} on miss, otherwise { position, normal, distance, hitbox, zone }
## (zone: &"head" / &"chest" / &"stomach" / &"legs", see Hitbox.zone_at).
## `players` must contain every player (their hitboxes are removed from the
## physics query and tested analytically instead); players in `ignore`
## (teammates) are not hit at all — bullets pass through them.
static func trace(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, max_range: float,
		shooter: PlayerController, players: Array, rewind_time: float, ignore: Array = []) -> Dictionary:
	dir = dir.normalized()
	var best := {}
	var best_distance := max_range

	# 1) World + non-player hitboxes via physics.
	var exclude: Array[RID] = []
	for p: PlayerController in players:
		exclude.append(p.get_rid())
		for hb: Hitbox in p.hitboxes:
			exclude.append(hb.get_rid())
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range, HIT_MASK, exclude)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		best_distance = origin.distance_to(hit.position)
		best = {
			"position": hit.position,
			"normal": hit.normal,
			"distance": best_distance,
			"hitbox": hit.collider as Hitbox,
			# Non-player hitboxes (target dummies) have no body zones.
			"zone": &"head" if hit.collider is Hitbox and (hit.collider as Hitbox).is_head else &"chest",
		}

	# 2) Players, rewound to what the shooter saw.
	for p: PlayerController in players:
		if p == shooter or p.health.is_dead or p in ignore:
			continue
		var state: Dictionary = p.net_sync.get_state_at(rewind_time)
		var feet: Vector3 = state.pos
		var height: float = state.height
		var head_center := feet + Vector3.UP * (height - HEAD_DROP)
		# Leaning moves the head sideways (PlayerController.LEAN_OFFSET).
		var flags: int = state.get("flags", 0)
		var lean_dir := (1.0 if flags & PlayerNetSync.Flags.LEAN_RIGHT else 0.0) \
			- (1.0 if flags & PlayerNetSync.Flags.LEAN_LEFT else 0.0)
		if lean_dir != 0.0:
			var yaw: float = state.get("yaw", 0.0)
			head_center += Vector3(cos(yaw), 0.0, -sin(yaw)) * lean_dir * PlayerController.LEAN_OFFSET

		var t := ray_sphere(origin, dir, head_center, HEAD_RADIUS)
		var hitbox: Hitbox = p.head_hitbox
		# Capsule segment end-points (sphere centres): the body's top surface
		# stops where the head sphere starts, so headshots aren't eaten by it.
		var body_top := feet + Vector3.UP * maxf(height - HEAD_DROP - HEAD_RADIUS - BODY_RADIUS, BODY_RADIUS)
		var body_bottom := feet + Vector3.UP * BODY_RADIUS
		var t_body := ray_capsule(origin, dir, body_bottom, body_top, BODY_RADIUS)
		if t_body >= 0.0 and (t < 0.0 or t_body < t):
			t = t_body
			hitbox = p.body_hitbox
		if t >= 0.0 and t < best_distance:
			best_distance = t
			var pos := origin + dir * t
			best = {
				"position": pos,
				"normal": -dir,
				"distance": t,
				"hitbox": hitbox,
				"zone": &"head" if hitbox == p.head_hitbox else Hitbox.zone_at(pos.y, feet.y, height),
			}
	return best


## Distance along the ray to a sphere, or -1.
static func ray_sphere(ro: Vector3, rd: Vector3, center: Vector3, radius: float) -> float:
	var oc := ro - center
	var b := oc.dot(rd)
	var c := oc.dot(oc) - radius * radius
	var h := b * b - c
	if h < 0.0:
		return -1.0
	var t := -b - sqrt(h)
	return t if t >= 0.0 else -1.0


## Distance along the ray to a capsule (segment pa–pb, radius ra), or -1.
## Based on Inigo Quilez' capsule intersection.
static func ray_capsule(ro: Vector3, rd: Vector3, pa: Vector3, pb: Vector3, ra: float) -> float:
	var ba := pb - pa
	var oa := ro - pa
	var baba := ba.dot(ba)
	var bard := ba.dot(rd)
	var baoa := ba.dot(oa)
	var rdoa := rd.dot(oa)
	var oaoa := oa.dot(oa)
	var a := baba - bard * bard
	var b := baba * rdoa - baoa * bard
	var c := baba * oaoa - baoa * baoa - ra * ra * baba
	var h := b * b - a * c
	if a > 0.000001 and h >= 0.0:
		var t := (-b - sqrt(h)) / a
		var y := baoa + t * bard
		if y > 0.0 and y < baba and t >= 0.0:
			return t
	# Caps (also handles rays parallel to the axis).
	var t_a := ray_sphere(ro, rd, pa, ra)
	var t_b := ray_sphere(ro, rd, pb, ra)
	if t_a < 0.0:
		return t_b
	if t_b < 0.0:
		return t_a
	return minf(t_a, t_b)
