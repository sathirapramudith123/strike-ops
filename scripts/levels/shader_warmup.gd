class_name ShaderWarmup
extends Node3D
## Avoids first-use stutter: the Compatibility (OpenGL) renderer compiles a
## shader the first time a material is drawn, which can freeze a frame for
## tens of milliseconds — typically the first shot (muzzle flash, decal) or
## the first enemy on screen. This draws one of each right in front of the
## camera, hidden inside the loading frames, then removes itself.

const FRAMES := 3


func _ready() -> void:
	name = "ShaderWarmup"
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		queue_free()
		return
	global_transform = cam.global_transform.translated_local(Vector3(0, 0, -1.5))
	# One of every weapon (viewmodel + muzzle flash + light) and a player body.
	var x := -0.6
	for path: String in GameConfig.WEAPONS.values():
		var w := (load(path) as PackedScene).instantiate() as Node3D
		w.set_script(null) # visuals only, no weapon logic
		w.position = Vector3(x, 0, 0)
		w.scale = Vector3.ONE * 0.3
		add_child(w)
		var flash := w.get_node_or_null("Muzzle/Flash") as Node3D
		if flash:
			flash.visible = true
		x += 0.3
	var body := MeshInstance3D.new()
	body.mesh = CapsuleMesh.new()
	body.scale = Vector3.ONE * 0.2
	body.position = Vector3(0, -0.3, 0)
	add_child(body)
	ImpactDecals.get_for(self).add(global_position, global_basis.z)
	for i in FRAMES:
		await get_tree().process_frame
	ImpactDecals.get_for(self).clear() # remove the warm-up decal
	queue_free()
