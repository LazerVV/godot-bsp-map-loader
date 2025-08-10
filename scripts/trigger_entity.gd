extends Area3D

var properties: Dictionary = {}

func _ready():
	properties = get_meta("bsp_properties", {})
	var classname = properties.get("classname", "")
	
	if classname == "trigger_push":
		# Handle push trigger (e.g., push player toward target)
		var target = properties.get("target", "")
		if target:
			# TODO: write proper target finding based on metadata search for all Character3D derivatives
			#if target_node:
			#	# Example: Apply impulse when player enters
			#	pass
			pass
	elif classname == "trigger_teleport":
		# Handle teleport trigger
		var target = properties.get("target", "")
		if target:
			# TODO: write proper target finding based on metadata search for all Character3D derivatives
			#if target_node:
			#	# Example: Teleport player to target
			#	pass
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
