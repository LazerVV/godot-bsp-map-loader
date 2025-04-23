@tool
extends Node3D

func _draw_line(start: Vector3, end: Vector3, color: Color):
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(start)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(end)
	mesh.surface_end()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "debug_line"
	add_child(mi)
	mi.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else self

func _clear_debug_lines():
	for child in get_children():
		if child.name == "debug_line":
			remove_child(child)
			child.queue_free()
			
func _process(_delta):
	if Engine.is_editor_hint():
		_clear_debug_lines()

		for child in get_children():
			var props = child.get_meta("bsp_property_", {})
			if props.has("target"):
				var target_name = props.target
				var target_node = find_node_by_name(target_name)
				if target_node:
					var start = child.global_position
					var end = target_node.global_position
					_draw_line(start, end, Color.RED)

					var dir = (end - start).normalized()
					var perp = dir.cross(Vector3.UP).normalized() * 0.1
					_draw_line(end, end - dir * 0.2 + perp, Color.RED)
					_draw_line(end, end - dir * 0.2 - perp, Color.RED)
			if props.has("angle"):
				var angle = float(props.angle)
				var dir = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(angle))
				_draw_line(child.global_position, child.global_position + dir * 0.5, Color.BLUE)

func find_node_by_name(name: String) -> Node:
	for child in get_children():
		if child.name == name:
			return child
		var found = find_node_by_name_recursive(child, name)
		if found:
			return found
	return null

func find_node_by_name_recursive(node: Node, name: String) -> Node:
	for child in node.get_children():
		if child.name == name:
			return child
		var found = find_node_by_name_recursive(child, name)
		if found:
			return found
	return null
