extends Node3D

func _ready():
	if not Engine.is_editor_hint():
		var props = get_meta("bsp_property_", {})
		if props.get("classname") == "func_door":
			var angle = props.get("angle", "0").to_float()
			var speed = props.get("speed", "100").to_float()
			var dir = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(angle)) * 100 * 0.015625
			# Placeholder: Move door
		elif props.get("classname") == "func_button":
			var target = props.get("target", "")
			# Placeholder: Activate target
		elif props.get("classname") == "func_rotating":
			var speed = props.get("speed", "100").to_float()
			# Placeholder: Rotate
