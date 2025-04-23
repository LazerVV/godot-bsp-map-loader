@tool
extends Node

func load_map(file_path: String) -> Node3D:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open MAP file: ", file_path)
		return null
	
	var root = Node3D.new()
	root.name = file_path.get_file().get_basename()
	
	var current_entity = null
	var current_brush = null
	var brushes = []
	var line = ""
	
	while not file.eof_reached():
		line = file.get_line().strip_edges()
		if line.begins_with("//") or line.empty():
			continue
		
		if line == "{":
			if not current_entity:
				current_entity = {}
				current_entity.brushes = []
			elif not current_brush:
				current_brush = []
		elif line == "}":
			if current_brush:
				current_entity.brushes.append(current_brush)
				current_brush = null
			elif current_entity:
				if current_entity.brushes.size() > 0:
					brushes.append_array(current_entity.brushes)
				current_entity = null
		elif current_entity and not current_brush:
			var parts = line.split(" ", false)
			if parts.size() >= 2:
				var key = parts[0].strip_edges().replace("\"", "")
				var value = parts[1].strip_edges().replace("\"", "")
				current_entity[key] = value
		elif current_brush:
			if line.begins_with("("):
				var parts = line.split(" ", false)
				var plane = {}
				plane.points = [
					Vector3(float(parts[1]), float(parts[2]), float(parts[3])),
					Vector3(float(parts[6]), float(parts[7]), float(parts[8])),
					Vector3(float(parts[11]), float(parts[12]), float(parts[13]))
				]
				plane.shader = parts[15].strip_edges()
				current_brush.append(plane)
	
	file.close()
	
	# Create meshes for brushes
	for brush in brushes:
		if brush.size() < 4:
			continue
		
		# Skip non-rendering brushes
		var shader = brush[0].shader
		if shader in ["common/caulk", "common/clip", "common/weapclip", "common/nodrop"]:
			continue
		
		var mesh = ArrayMesh.new()
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		var vertex_array = []
		var normal_array = []
		var texcoord_array = []
		var index_array = []
		
		# Simple triangulation (needs improvement for complex brushes)
		for plane in brush:
			var normal = (plane.points[1] - plane.points[0]).cross(plane.points[2] - plane.points[0]).normalized()
			var index_offset = vertex_array.size()
			for point in plane.points:
				vertex_array.append(point)
				normal_array.append(normal)
				texcoord_array.append(Vector2(0, 0))  # Placeholder UVs
			index_array.append_array([index_offset, index_offset + 1, index_offset + 2])
		
		arrays[Mesh.ARRAY_VERTEX] = vertex_array
		arrays[Mesh.ARRAY_NORMAL] = normal_array
		arrays[Mesh.ARRAY_TEX_UV] = texcoord_array
		arrays[Mesh.ARRAY_INDEX] = index_array
		
		if vertex_array.size() == 0:
			continue
		
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Brush_" + shader.replace("/", "_")
		mesh_instance.mesh = mesh
		
		# Create material
		var material = StandardMaterial3D.new()
		var texture_base_path = "/home/l0rd/.xonotic/data/textures/"
		var texture_path = texture_base_path + shader + ".tga"
		if FileAccess.file_exists(texture_path):
			material.albedo_texture = load(texture_path)
		else:
			print("Warning: Texture not found: ", texture_path)
			material.albedo_color = Color(0.5, 0.5, 0.5)
		mesh_instance.set_surface_override_material(0, material)
		
		root.add_child(mesh_instance)
		mesh_instance.owner = root
	
	if root.get_child_count() == 0:
		push_error("No valid geometry found in MAP file")
		root.queue_free()
		return null
	
	return root
