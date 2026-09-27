extends Node
## Entry point for the two-process multiplayer test. The real work happens in
## net_test_driver.gd, which lives under /root so it survives scene changes.
##
## Run both roles (see tools/run_net_test.sh):
##   godot --headless --path . res://tests/net_test.tscn -- --role=host --port=7788
##   godot --headless --path . res://tests/net_test.tscn -- --role=client --port=7788


func _ready() -> void:
	var driver: Node = load("res://tests/net_test_driver.gd").new()
	driver.name = "NetTestDriver"
	get_tree().root.add_child.call_deferred(driver)
