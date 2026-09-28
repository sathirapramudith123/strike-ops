class_name Climb
extends RefCounted
## Climbing (vaulting) onto ledges: press Jump facing a ledge up to
## MAX_HEIGHT high and the player pulls themself up on top. Only objects in
## the "climbable" group can be climbed (crates, cars, sandbags, low walls…,
## marked by tools/greybox.py); everything else is only reachable by
## jumping (up to JUMP_REACH) or by stairs and ramps.
##
## `find_ledge` is also used by the smoke test to check every map for ledges
## that are "sometimes jumpable" (see BORDERLINE_*).

const GROUP := &"climbable"
## Highest ledge that can be climbed (m above the feet).
const MAX_HEIGHT := 2.2
## Lower ledges are just jumped onto.
const MIN_HEIGHT := 0.6
## How far in front of the player (m, from the body's centre) a ledge counts.
const REACH := 0.95
## A plain jump gets onto ledges up to about this high (jump_velocity 5 m/s,
## capsule radius 0.35); between BORDERLINE_LOW and BORDERLINE_HIGH it
## depends on the run-up, so the maps avoid non-climbable ledges there.
const JUMP_REACH := 1.4
const BORDERLINE_LOW := 1.25
const BORDERLINE_HIGH := 1.55
## Room needed on top: a crouched player (height, radius).
const ROOM_HEIGHT := 1.1
const ROOM_RADIUS := 0.35
## How far onto the top the player lands (m past the edge).
const LAND_IN := 0.45


## The ledge in front of `feet` (the player's feet position) looking along
## `dir` (horizontal), or {} if there is none. Returns { "top": landing
## point on the top, "height": m above the feet, "collider": the body,
## "climbable": whether it may be climbed }. `exclude`: RIDs to ignore (the
## player). `need_room`: also require space for a crouched player on top.
static func find_ledge(space: PhysicsDirectSpaceState3D, feet: Vector3, dir: Vector3, exclude: Array[RID] = [],
		need_room: bool = true) -> Dictionary:
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		return {}
	dir = dir.normalized()
	# 1. Something in front, low down (the face of the ledge).
	var knee := feet + Vector3.UP * 0.35
	var face := _ray(space, knee, knee + dir * REACH, exclude)
	if face.is_empty() or absf(face.normal.y) > 0.5:
		return {}
	# 2. Nothing in front higher than MAX_HEIGHT (a tall wall, not a ledge).
	var above := feet + Vector3.UP * (MAX_HEIGHT + 0.15)
	var dist: float = knee.distance_to(face.position)
	if not _ray(space, above, above + dir * (dist + LAND_IN + 0.1), exclude).is_empty():
		return {}
	# 3. The top surface, found from above just past the edge.
	var land_xz: Vector3 = face.position + dir * LAND_IN
	var from := Vector3(land_xz.x, feet.y + MAX_HEIGHT + 0.1, land_xz.z)
	var top := _ray(space, from, Vector3(land_xz.x, feet.y + 0.2, land_xz.z), exclude)
	if top.is_empty() or top.normal.y < 0.7:
		return {}
	var height: float = top.position.y - feet.y
	if height < 0.3 or height > MAX_HEIGHT:
		return {}
	var body: Object = top.collider
	var result := { "top": top.position, "height": height, "collider": body, "normal": top.normal,
		"climbable": body is Node and (body as Node).is_in_group(GROUP) }
	# 4. Room to crouch on top.
	if need_room and not has_room(space, top.position, exclude):
		return {}
	return result


## Whether a crouched player fits standing on `point`.
static func has_room(space: PhysicsDirectSpaceState3D, point: Vector3, exclude: Array[RID] = []) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = ROOM_RADIUS - 0.05
	capsule.height = ROOM_HEIGHT - 0.1
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collision_mask = 1
	q.exclude = exclude
	q.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * (ROOM_HEIGHT * 0.5 + 0.08))
	return space.intersect_shape(q, 1).is_empty()


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, exclude)
	return space.intersect_ray(q)
