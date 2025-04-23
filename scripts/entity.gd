@tool
extends Node3D
class_name Entity3D

@export var properties: Dictionary = {}:
	set(value):
		properties = value
		notify_property_list_changed()

func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	for key in properties.keys():
		props.append({
			"name": "properties/" + key,
			"type": TYPE_STRING,
			"usage": PROPERTY_USAGE_DEFAULT,
			"hint": PROPERTY_HINT_NONE
		})
	return props

func _get(property: StringName) -> Variant:
	if property.begins_with("properties/"):
		var key = property.trim_prefix("properties/")
		return properties.get(key, "")
	return null

func _set(property: StringName, value: Variant) -> bool:
	if property.begins_with("properties/"):
		var key = property.trim_prefix("properties/")
		properties[key] = str(value)
		return true
	return false

func _ready():
	if not Engine.is_editor_hint():
		# Initialize runtime behavior if needed
		pass

func _draw_gizmo():
	if Engine.is_editor_hint():
		var gizmo = EditorInterface.get_selection().get_selected_nodes()[0] if EditorInterface.get_selection().get_selected_nodes().size() > 0 else null
		if gizmo == self:
			# Draw target arrow
			if properties.has("target"):
				var target_name = properties.target
				var target_node = find_node_by_name(get_tree().get_edited_scene_root(), target_name)
				if target_node:
					var start = global_position
					var end = target_node.global_position
					var arrow = ImmediateMesh.new()
					arrow.surface_begin(Mesh.PRIMITIVE_LINES)
					arrow.surface_set_color(Color.RED)
					arrow.surface_add_vertex(start)
					arrow.surface_add_vertex(end)
					# Arrowhead
					var dir = (end - start).normalized()
					var perp = dir.cross(Vector3.UP).normalized() * 0.1
					arrow.surface_add_vertex(end)
					arrow.surface_add_vertex(end - dir * 0.2 + perp)
					arrow.surface_add_vertex(end)
					arrow.surface_add_vertex(end - dir * 0.2 - perp)
					arrow.surface_end()
					EditorInterface.get_editor_viewport_3d(0).add_child(arrow)
					arrow.queue_free()
			
			# Draw directional arrow (e.g., angle)
			if properties.has("angle"):
				var angle = float(properties.angle)
				var dir = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(angle))
				var arrow = ImmediateMesh.new()
				arrow.surface_begin(Mesh.PRIMITIVE_LINES)
				arrow.surface_set_color(Color.BLUE)
				arrow.surface_add_vertex(global_position)
				arrow.surface_add_vertex(global_position + dir * 0.5)
				arrow.surface_end()
				EditorInterface.get_editor_viewport_3d(0).add_child(arrow)
				arrow.queue_free()

func find_node_by_name(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for child in node.get_children():
		var found = find_node_by_name(child, name)
		if found:
			return found
	return null
