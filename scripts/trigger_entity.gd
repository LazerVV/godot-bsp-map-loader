extends StaticBody3D

var properties: Dictionary = {}

func _ready():
	properties = get_meta("bsp_properties", {})
	var classname = properties.get("classname", "")
	
	if classname == "trigger_push":
		# Handle push trigger (e.g., push player toward target)
		var target = properties.get("target", "")
		if target:
			# Find target_position node
			var target_node = get_tree().get_root().find_node(target, true, false)
			if target_node:
				# Example: Apply impulse when player enters
				pass
	elif classname == "trigger_teleport":
		# Handle teleport trigger
		var target = properties.get("target", "")
		if target:
			var target_node = get_tree().get_root().find_node(target, true, false)
			if target_node:
				# Example: Teleport player to target
				pass
	elif classname == "trigger_hurt":
		# Handle hurt trigger
		var damage = properties.get("damage", "100").to_int()
		# Example: Apply damage to player
		pass
	else:
		print("Unsupported trigger type: ", classname)

func _on_area_entered(area: Area3D):
	var parent = area.get_parent()
	if parent.is_in_group("player"):
		var classname = properties.get("classname", "")
		if classname == "trigger_push":
			# Implement push logic
			pass
		elif classname == "trigger_teleport":
			# Implement teleport logic
			pass
		elif classname == "trigger_hurt":
			# Implement hurt logic
			pass
