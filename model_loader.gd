class_name ModelLoader
extends RefCounted

static func load_md3(path: String) -> Mesh:
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		push_error("Cannot open MD3: " + path)
		return null
	
	var ident = f.get_buffer(4).get_string_from_ascii()
	if ident != "IDP3":
		push_error("Invalid MD3 file")
		return null
	
	var version = f.get_32()
	if version != 15:
		push_error("Unsupported MD3 version " + str(version))
		return null
	
	f.get_buffer(64) # name
	var flags = f.get_32()
	var num_frames = f.get_32()
	var num_tags = f.get_32()
	var num_surfaces = f.get_32()
	var num_skins = f.get_32()
	var ofs_frames = f.get_32()
	var ofs_tags = f.get_32()
	var ofs_surfaces = f.get_32()
	var ofs_eof = f.get_32()
	
	# For basic, load first frame/surface
	f.seek(ofs_surfaces)
	var mesh = ArrayMesh.new()
	for s in num_surfaces:
		var surf_ident = f.get_buffer(4).get_string_from_ascii()
		if surf_ident != "IDP3":
			continue
		f.get_buffer(64) # name
		f.get_32() # flags
		var num_surf_frames = f.get_32()
		var num_shaders = f.get_32()
		var num_verts = f.get_32()
		var num_tris = f.get_32()
		var ofs_tris = f.get_32()
		var ofs_shaders = f.get_32()
		var ofs_st = f.get_32()
		var ofs_xyznormal = f.get_32()
		var ofs_end = f.get_32()
		
		# Triangles
		f.seek(f.get_position() - 104 + ofs_tris) # relative
		var indices = PackedInt32Array()
		for t in num_tris:
			indices.append(f.get_32())
			indices.append(f.get_32())
			indices.append(f.get_32())
		
		# UVs
		f.seek(f.get_position() - ofs_tris + ofs_st)
		var uvs = PackedVector2Array()
		for v in num_verts:
			uvs.append(Vector2(f.get_float(), f.get_float()))
		
		# Verts/normals (first frame)
		f.seek(f.get_position() - ofs_st + ofs_xyznormal)
		var vertices = PackedVector3Array()
		var normals = PackedVector3Array()
		for v in num_verts:
			vertices.append(Vector3(f.get_16(), f.get_16(), f.get_16()) * 1.0 / 64.0)
			var lat = f.get_8() * (2 * PI / 255.0)
			var lng = f.get_8() * (2 * PI / 255.0)
			normals.append(Vector3(cos(lat) * sin(lng), sin(lat) * sin(lng), cos(lng)))
		
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	return mesh if mesh.get_surface_count() > 0 else null

static func load_iqm(path: String) -> Mesh:
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		push_error("Cannot open IQM: " + path)
		return null
	
	var magic = f.get_buffer(16).get_string_from_ascii()
	if magic != "INTERQUAKEMODEL":
		push_error("Invalid IQM file")
		return null
	
	var version = f.get_32()
	if version != 2:
		push_error("Unsupported IQM version " + str(version))
		return null
	
	var filesize = f.get_32()
	f.get_32() # flags
	var num_text = f.get_32()
	var ofs_text = f.get_32()
	var num_meshes = f.get_32()
	var ofs_meshes = f.get_32()
	var num_vertexarrays = f.get_32()
	var num_vertexes = f.get_32()
	var ofs_vertexarrays = f.get_32()
	var num_triangles = f.get_32()
	var ofs_triangles = f.get_32()
	var ofs_neighbors = f.get_32()
	var num_joints = f.get_32()
	var ofs_joints = f.get_32()
	var num_poses = f.get_32()
	var ofs_poses = f.get_32()
	var num_anims = f.get_32()
	var ofs_anims = f.get_32()
	var num_frames = f.get_32()
	var num_framechannels = f.get_32()
	var ofs_frames = f.get_32()
	var ofs_bounds = f.get_32()
	var num_comment = f.get_32()
	var ofs_comment = f.get_32()
	var num_extensions = f.get_32()
	var ofs_extensions = f.get_32()
	
	# For basic static mesh, load first mesh
	f.seek(ofs_meshes)
	var mesh = ArrayMesh.new()
	for m in num_meshes:
		var name_ofs = f.get_32()
		var material_ofs = f.get_32()
		var first_vert = f.get_32()
		var num_verts = f.get_32()
		var first_tri = f.get_32()
		var num_tris = f.get_32()
		
		# Positions
		f.seek(ofs_vertexarrays)
		var pos_ofs = 0
		var pos_format = 0
		var pos_size = 0
		for va in num_vertexarrays:
			var type = f.get_32()
			f.get_32() # flags
			var format = f.get_32()
			var size = f.get_32()
			var offset = f.get_32()
			if type == 0:  # IQM_POSITION
				pos_ofs = offset
				pos_format = format
				pos_size = size
				break
		
		f.seek(pos_ofs)
		var vertices = PackedVector3Array()
		for v in num_verts:
			vertices.append(Vector3(f.get_float(), f.get_float(), f.get_float()))
		
		# Triangles
		f.seek(ofs_triangles)
		var indices = PackedInt32Array()
		for t in num_tris:
			indices.append(f.get_32())
			indices.append(f.get_32())
			indices.append(f.get_32())
		
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	return mesh if mesh.get_surface_count() > 0 else null
