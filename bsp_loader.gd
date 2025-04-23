class_name BSPLoader
extends BSPCommon

var scale_factor: float = 0.0254
var lightmap_path: String = ""
var player_model_path: String = ""
var include_patch_collision: bool = false
var patch_tessellation_level: int = 8
var debug_logging: bool = true
var shader_uv_scales: Dictionary = {
	"exx/base-crete01red": Vector2(0.25, 0.25),
	"exx/base-crete01": Vector2(0.25, 0.25),
	"exx/base-crete01blue": Vector2(0.25, 0.25),
	"exx/floor-clang01b": Vector2(0.5, 0.5),
	"exx/floor-crete01": Vector2(0.5, 0.5),
	"exx/panel-grate01-cull": Vector2(1.0, 1.0),
	"exx/base-metal01": Vector2(1.0, 1.0),
	"base/mgrate": Vector2(1.0, 1.0)
}

signal progress_updated(stage: String, pct: float)

func _get_import_options(path: String, preset: int) -> Array[Dictionary]:
	return [
		{
			"name": "include_patch_collision",
			"default_value": false,
			"type": TYPE_BOOL,
			"hint_string": "Include Bezier patch surfaces in collision shapes."
		},
		{
			"name": "patch_tessellation_level",
			"default_value": 8,
			"type": TYPE_INT,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": "2,4,8,16"
		}
	]

func load_bsp(path: String) -> Node3D:
	emit_signal("progress_updated", "Opening file", 0.0)
	
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not f:
		push_error("Cannot open BSP: ", path)
		return null
	
	# Header
	var ident: String = f.get_buffer(4).get_string_from_ascii()
	var ver: int = f.get_32()
	if ident != "IBSP" or ver != BSP_VERSION_QUAKE3:
		push_error("Unsupported BSP (%s v%d)" % [ident, ver])
		return null
	
	# Lumps
	var lumps: Array[Dictionary] = []
	for i in range(EXPECTED_LUMP_COUNT):
		lumps.append({"offset": f.get_32(), "length": f.get_32()})
	
	# Entities
	emit_signal("progress_updated", "Entities", 10.0)
	f.seek(lumps[LUMP_ENTITIES].offset)
	var entity_data: String = read_null_terminated_string(f, lumps[LUMP_ENTITIES].length)
	var entities: Array[Dictionary] = parse_entities(entity_data)
	if entities.is_empty():
		print("Warning: No entities parsed from BSP. Raw data: ", entity_data.substr(0, 200))
	
	# Shaders
	emit_signal("progress_updated", "Shaders", 20.0)
	f.seek(lumps[LUMP_SHADERS].offset)
	var n_shaders: int = lumps[LUMP_SHADERS].length / 72
	var shaders: Array[Dictionary] = []
	for i in range(n_shaders):
		var raw_bytes = f.get_buffer(64)
		var raw = ""
		for b in raw_bytes:
			if b == 0:
				break
			if b >= 32 and b <= 126:
				raw += char(b)
		f.get_32() # sflags
		f.get_32() # cflags
		if raw.strip_edges() != "":
			var shader_name = raw.replace("textures/", "").strip_edges()
			shaders.append({
				"name": shader_name,
				"sflags": 0,
				"cflags": 0
			})
		else:
			print("Skipping empty/invalid shader at index ", i)
	
	# Planes
	emit_signal("progress_updated", "Planes", 30.0)
	f.seek(lumps[LUMP_PLANES].offset)
	var n_planes: int = lumps[LUMP_PLANES].length / 16
	var planes: Array[Dictionary] = []
	for i in range(n_planes):
		planes.append({
			"normal": transform_vector(Vector3(f.get_float(), f.get_float(), f.get_float())),
			"dist": f.get_float() * scale_factor
		})
	
	# Vertices
	emit_signal("progress_updated", "Vertices", 40.0)
	f.seek(lumps[LUMP_VERTICES].offset)
	var n_verts: int = lumps[LUMP_VERTICES].length / 44
	var verts: Array[Dictionary] = []
	for i in range(n_verts):
		var pos = transform_vector(Vector3(f.get_float(), f.get_float(), f.get_float()))
		var uv_x = f.get_float()
		var uv_y = f.get_float()
		# Sanitize UVs to prevent overflow
		if not is_finite(uv_x) or abs(uv_x) > 1000.0:
			if debug_logging:
				print("Invalid uv_x for vertex %d: %s, clamping to 0.0" % [i, uv_x])
			uv_x = 0.0
		if not is_finite(uv_y) or abs(uv_y) > 1000.0:
			if debug_logging:
				print("Invalid uv_y for vertex %d: %s, clamping to 0.0" % [i, uv_y])
			uv_y = 0.0
		var luv_x = f.get_float()
		var luv_y = f.get_float()
		var normal = transform_vector(Vector3(f.get_float(), f.get_float(), f.get_float()))
		verts.append({
			"pos": pos * scale_factor,
			"uv": Vector2(uv_x, uv_y),
			"luv": Vector2(luv_x, luv_y),
			"normal": normal,
			"color": Color(f.get_8()/255.0, f.get_8()/255.0, f.get_8()/255.0, f.get_8()/255.0)
		})
	
	# Meshverts
	emit_signal("progress_updated", "MeshVerts", 50.0)
	f.seek(lumps[LUMP_MESHVERTS].offset)
	var n_mv: int = lumps[LUMP_MESHVERTS].length / 4
	var meshverts: PackedInt32Array = PackedInt32Array()
	meshverts.resize(n_mv)
	for i in range(n_mv):
		meshverts[i] = f.get_32()
	
	# Brushes
	emit_signal("progress_updated", "Brushes", 55.0)
	f.seek(lumps[LUMP_BRUSHES].offset)
	var n_brushes: int = lumps[LUMP_BRUSHES].length / 12
	var brushes: Array[Dictionary] = []
	for i in range(n_brushes):
		brushes.append({
			"first_side": f.get_32(),
			"num_sides": f.get_32(),
			"shader_num": f.get_32()
		})
	
	# Brushsides
	f.seek(lumps[LUMP_BRUSHSIDES].offset)
	var n_brushsides: int = lumps[LUMP_BRUSHSIDES].length / 8
	var brushsides: Array[Dictionary] = []
	for i in range(n_brushsides):
		brushsides.append({
			"plane_num": f.get_32(),
			"shader_num": f.get_32()
		})
	
	# Models
	f.seek(lumps[LUMP_MODELS].offset)
	var n_models: int = lumps[LUMP_MODELS].length / 40
	var models: Array[Dictionary] = []
	for i in range(n_models):
		var mins = transform_vector(Vector3(f.get_float(), f.get_float(), f.get_float())) * scale_factor
		var maxs = transform_vector(Vector3(f.get_float(), f.get_float(), f.get_float())) * scale_factor
		models.append({
			"mins": mins,
			"maxs": maxs,
			"first_face": f.get_32(),
			"num_faces": f.get_32(),
			"first_brush": f.get_32(),
			"num_brushes": f.get_32()
		})
	
	# Faces
	emit_signal("progress_updated", "Faces", 60.0)
	f.seek(lumps[LUMP_SURFACES].offset)
	const FACE_BYTES: int = 104
	var n_faces: int = lumps[LUMP_SURFACES].length / FACE_BYTES
	var faces: Array[Dictionary] = []
	for i in range(n_faces):
		var face: Dictionary = {
			"shader_num": f.get_32(),
			"effect_num": f.get_32(),
			"surface_type": f.get_32(),
			"first_vert": f.get_32(),
			"num_verts": f.get_32(),
			"first_mv": f.get_32(),
			"num_mv": f.get_32(),
			"lm_index": f.get_32()
		}
		f.get_32(); f.get_32(); f.get_32(); f.get_32() # lm x,y,w,h
		face.lm_origin = transform_vector(Vector3(f.get_float(), f.get_float(), f.get_float())) * scale_factor
		f.get_float(); f.get_float(); f.get_float() # lm_vec_s
		f.get_float(); f.get_float(); f.get_float() # lm_vec_t
		face.normal = transform_vector(Vector3(f.get_float(), f.get_float(), f.get_float()))
		face.size_u = f.get_32()
		face.size_v = f.get_32()
		faces.append(face)
	
	# Build Scene
	emit_signal("progress_updated", "Build scene", 80.0)
	
	var root := Node3D.new()
	root.name = path.get_file().get_basename()
	root.set_script(load("res://addons/bsp_loader/scripts/root_gizmo.gd"))
	
	# Load textures and materials
	var texture_loader = BSPTextureLoader.new()
	var texture_cache = texture_loader.load_textures(shaders, faces)
	var materials = texture_loader.create_materials(shaders, texture_cache)
	var non_solid_shaders = texture_loader.get_non_solid_shaders()
	var lightmap_textures: Dictionary = {}
	for i in range(100):
		var lm_path = lightmap_path + "lm_%04d.jpg" % i
		if FileAccess.file_exists(lm_path):
			lightmap_textures[i] = load(lm_path)
	
	# Entity Processing
	if debug_logging:
		print("Processing %d entities..." % entities.size())
	for ent_idx in range(entities.size()):
		var ent = entities[ent_idx]
		var classname = ent.get("classname", "unknown")
		var node_name = "%d-%s" % [ent_idx, classname]
		var model_idx = ent.get("model", "").replace("*", "").to_int() if ent.has("model") else -1
		var has_geometry = (classname == "worldspawn" or (classname in COLLIDABLE_FUNC_ENTITIES and model_idx >= 0 and model_idx < models.size()))
		
		var node: Node
		if classname == "worldspawn":
			node = StaticBody3D.new()
			node.collision_layer = 1
			node.collision_mask = 0
		elif classname in TRIGGER_ENTITIES or classname in GOAL_ENTITIES:
			node = Area3D.new()
			node.collision_layer = 2
			node.collision_mask = 1
		elif classname in COLLIDABLE_FUNC_ENTITIES:
			node = StaticBody3D.new()
			node.collision_layer = 3
			node.collision_mask = 0
		elif classname in ITEM_ENTITIES or classname in WEAPON_ENTITIES:
			node = StaticBody3D.new()
			node.collision_layer = 4
			node.collision_mask = 1
		elif classname.begins_with("info_player"):
			node = StaticBody3D.new()
			node.collision_layer = 0
			node.collision_mask = 1
		elif classname == "light" or classname == "lightJunior":
			node = OmniLight3D.new()
			node.light_energy = ent.get("light", "300").to_float() / 300.0
			if ent.has("_color") or ent.has("color"):
				var col = parse_vector3(ent.get("_color", ent.get("color", "1 1 1")))
				node.light_color = Color(col.x, col.y, col.z)
		else:
			node = Node3D.new()
		
		node.name = node_name
		if ent.has("origin") and not (classname in TRIGGER_ENTITIES or classname in GOAL_ENTITIES):
			var origin = parse_vector3(ent.origin)
			node.position = transform_vector(origin) * scale_factor
		if ent.has("angles") and not (classname in TRIGGER_ENTITIES or classname in GOAL_ENTITIES):
			var angles = parse_vector3(ent.angles)
			node.rotation_degrees = transform_vector(angles)
		
		node.set_meta("bsp_properties", ent)
		root.add_child(node)
		node.owner = root
		if debug_logging:
			print("Added node: ", node_name)
		
		if classname in COLLIDABLE_FUNC_ENTITIES:
			var area = Area3D.new()
			area.name = "InteractionArea"
			area.collision_layer = 2
			area.collision_mask = 1
			node.add_child(area)
			area.owner = root
		
		# Add collision and geometry
		var is_collidable = true
		if has_geometry:
			if debug_logging:
				print("Processing geometry for entity: ", node_name)
			var model = models[model_idx] if model_idx >= 0 and model_idx < models.size() else models[0]
			if classname in COLLIDABLE_FUNC_ENTITIES:
				is_collidable = is_brush_collidable(model, brushes, brushsides, shaders)
			var ent_mesh = ArrayMesh.new()
			var ent_by_mat: Dictionary = {}
			var col_vertices: PackedVector3Array = []
			var patch_number: int = 0
			for face_idx in range(model.first_face, model.first_face + model.num_faces):
				var face = faces[face_idx]
				if face.surface_type not in [MST_PLANAR, MST_TRIANGLE_SOUP, MST_PATCH]:
					continue
				var sh_name = shaders[face.shader_num].name if face.shader_num >= 0 and face.shader_num < shaders.size() else ""
				if sh_name in NON_RENDER_SHADERS and sh_name != "common/invisible":
					continue
				if not ent_by_mat.has(sh_name):
					ent_by_mat[sh_name] = {
						"v": PackedVector3Array(),
						"n": PackedVector3Array(),
						"uv": PackedVector2Array(),
						"luv": PackedVector2Array(),
						"color": PackedColorArray(),
						"id": PackedInt32Array(),
						"lm_index": face.lm_index
					}
				var mat_data = ent_by_mat[sh_name]
				var v_ofs = mat_data.v.size()
				if face.surface_type == MST_PATCH:
					if debug_logging:
						print(">>> START processing PATCH face index: %d, shader: %s" % [face_idx, sh_name])
					var w: int = face.size_u
					var h: int = face.size_v
					if w < 2 or h < 2 or face.num_verts != w * h:
						if debug_logging:
							print("Invalid patch dimensions for face %d: w=%d, h=%d, num_verts=%d" % [face_idx, w, h, face.num_verts])
						continue
					# Validate control point UVs
					var valid_patch = true
					for j in range(h):
						for i in range(w):
							var idx = face.first_vert + j * w + i
							if idx >= 0 and idx < verts.size():
								var vert = verts[idx]
								if not vert.uv.is_finite() or abs(vert.uv.x) > 1000.0 or abs(vert.uv.y) > 1000.0:
									if debug_logging:
										print("Invalid UV for control point face %d [%d,%d]: uv=%s, skipping patch" % [face_idx, i, j, vert.uv])
									valid_patch = false
									break
								if debug_logging:
									print("Control point face %d [%d,%d]: uv=%s, luv=%s" % [face_idx, i, j, vert.uv, vert.luv])
						if not valid_patch:
							break
					if not valid_patch:
						if debug_logging:
							print("Skipping patch face %d due to invalid UVs" % face_idx)
						continue
					var tess: int = patch_tessellation_level
					# Temporary arrays for patch data
					var patch_vertices = PackedVector3Array()
					var patch_normals = PackedVector3Array()
					var patch_uvs = PackedVector2Array()
					var patch_luvs = PackedVector2Array()
					var patch_colors = PackedColorArray()
					var patch_indices = PackedInt32Array()
					# Timeout to prevent hangs
					var start_time = Time.get_ticks_msec()
					var timeout_ms = 5000
					var vertex_count = 0
					for vy in range(tess + 1):
						for vx in range(tess + 1):
							# Check for timeout
							if Time.get_ticks_msec() - start_time > timeout_ms:
								if debug_logging:
									print("Timeout processing patch face %d at vx=%d, vy=%d, aborting" % [face_idx, vx, vy])
								valid_patch = false
								break
							var u: float = vx / float(tess)
							var v: float = vy / float(tess)
							var pos := Vector3()
							var nor := Vector3()
							var uv := Vector2()
							var luv := Vector2()
							var col := Color()
							var sum: float = 0.0
							# Partial derivatives for normal
							var du_pos := Vector3()
							var dv_pos := Vector3()
							var du_sum: float = 0.0
							var dv_sum: float = 0.0
							for j in range(h):
								for i in range(w):
									var idx: int = face.first_vert + j * w + i
									if idx < 0 or idx >= verts.size():
										if debug_logging:
											push_error("Invalid vertex index %d for patch face %d (Max: %d)" % [idx, face_idx, verts.size() - 1])
										continue
									var wgt: float = BezierMesh.bernstein(u, i, w - 1) * BezierMesh.bernstein(v, j, h - 1)
									var du_wgt: float = BezierMesh.bernstein(u, i, w - 1) * BezierMesh.bernstein(v, j, h - 1)
									var dv_wgt: float = BezierMesh.bernstein(u, i, w - 1) * BezierMesh.bernstein(v, j, h - 1)
									if i < w - 1:
										du_wgt *= float(w - 1) * (BezierMesh.bernstein(u, i + 1, w - 2) - BezierMesh.bernstein(u, i, w - 2)) if w > 2 else 0.0
									else:
										du_wgt = 0.0
									if j < h - 1:
										dv_wgt *= float(h - 1) * (BezierMesh.bernstein(v, j + 1, h - 2) - BezierMesh.bernstein(v, j, h - 2)) if h > 2 else 0.0
									else:
										dv_wgt = 0.0
									var vert = verts[idx]
									pos += vert.pos * wgt
									uv += vert.uv * wgt
									luv += vert.luv * wgt
									col += vert.color * wgt
									du_pos += vert.pos * du_wgt
									dv_pos += vert.pos * dv_wgt
									sum += wgt
									du_sum += du_wgt
									dv_sum += dv_wgt
							if sum > 0.0001:
								pos /= sum
								uv /= sum
								luv /= sum
								col /= sum
								du_pos /= sum
								dv_pos /= sum
								# Apply shader-specific UV scaling
								var uv_scale = shader_uv_scales.get(sh_name, Vector2(1.0, 1.0))
								uv = Vector2(uv.x * uv_scale.x, uv.y * uv_scale.y)
								luv = luv / Vector2(128, 128)
								# Validate UVs
								if not uv.is_finite() or abs(uv.x) > 1000.0 or abs(uv.y) > 1000.0:
									if debug_logging:
										print("Invalid computed UV for face %d at vx=%d, vy=%d: uv=%s, skipping vertex" % [face_idx, vx, vy, uv])
									continue
								# Calculate normal
								nor = du_pos.cross(dv_pos).normalized()
								if nor.is_zero_approx() or not nor.is_finite():
									nor = face.normal
							else:
								nor = face.normal
								if debug_logging:
									print("Near-zero sum for face %d at vx=%d, vy=%d: sum=%f" % [face_idx, vx, vy, sum])
							# Validate data
							if not pos.is_finite() or not nor.is_finite() or not uv.is_finite() or not luv.is_finite():
								if debug_logging:
									print("Invalid data for face %d at vx=%d, vy=%d: pos=%s, nor=%s, uv=%s, luv=%s" % [face_idx, vx, vy, pos, nor, uv, luv])
								continue
							patch_vertices.append(pos)
							patch_normals.append(nor)
							patch_uvs.append(uv)
							patch_luvs.append(luv)
							patch_colors.append(col)
							vertex_count += 1
							if vertex_count == 1 and debug_logging:
								print("Patch face %d vertex[0,0]: pos=%s, nor=%s, uv=%s, luv=%s" % [face_idx, pos, nor, uv, luv])
						if not valid_patch:
							break
					if not valid_patch:
						if debug_logging:
							print("Aborted patch face %d due to timeout or invalid data" % face_idx)
						continue
					# Generate CCW indices
					var triangle_count = 0
					for tess_vy in range(tess):
						for tess_vx in range(tess):
							var b: int = tess_vy * (tess + 1) + tess_vx
							var idx00 = b
							var idx10 = b + 1
							var idx01 = b + tess + 1
							var idx11 = b + tess + 2
							if idx11 >= patch_vertices.size():
								if debug_logging:
									print("Invalid index for face %d at vx=%d, vy=%d: idx11=%d, vertices=%d" % [face_idx, tess_vx, tess_vy, idx11, patch_vertices.size()])
								continue
							var v00 = patch_vertices[idx00]
							var v10 = patch_vertices[idx10]
							var v01 = patch_vertices[idx01]
							var v11 = patch_vertices[idx11]
							var area1 = (v10 - v00).cross(v01 - v00).length()
							var area2 = (v01 - v10).cross(v11 - v10).length()
							if area1 < 0.0001 or area2 < 0.0001:
								if debug_logging:
									print("Degenerate triangle for face %d at vx=%d, vy=%d: area1=%f, area2=%f" % [face_idx, tess_vx, tess_vy, area1, area2])
								continue
							# Add indices with v_ofs
							patch_indices.append_array([
								v_ofs + idx00, v_ofs + idx01, v_ofs + idx10,
								v_ofs + idx10, v_ofs + idx01, v_ofs + idx11
							])
							triangle_count += 2
					# Append to material data
					mat_data.v.append_array(patch_vertices)
					mat_data.n.append_array(patch_normals)
					mat_data.uv.append_array(patch_uvs)
					mat_data.luv.append_array(patch_luvs)
					mat_data.color.append_array(patch_colors)
					mat_data.id.append_array(patch_indices)
					if debug_logging:
						print("Processed patch face %d: w=%d, h=%d, vertices=%d, triangles=%d" % [face_idx, w, h, patch_vertices.size(), triangle_count])
					if include_patch_collision and sh_name not in non_solid_shaders:
						for j in range(0, h - 2, 2):
							for i in range(0, w - 2, 2):
								var control: Array[Vector3] = []
								for jj in range(3):
									for ii in range(3):
										var idx = face.first_vert + (j + jj) * w + (i + ii)
										if idx < verts.size():
											var vert = verts[idx]
											control.append(vert.pos)
								if control.size() == 9:
									var collider = node if node is CollisionObject3D else null
									if collider:
										var owner_shape_id = collider.create_shape_owner(collider)
										BezierMesh.bezier_collider_mesh(owner_shape_id, collider, face_idx, patch_number, control)
										patch_number += 1
					if debug_logging:
						print("<<< END processing PATCH face index: %d" % face_idx)
				else:
					# Non-patch faces
					var normal = face.normal
					var up_vector = Vector3.UP
					if abs(normal.dot(Vector3.UP)) > 0.99:
						up_vector = Vector3.FORWARD
					var tangent = normal.cross(up_vector).normalized()
					var binormal = normal.cross(tangent).normalized()
					for i_idx in range(0, face.num_mv, 3):
						var a_idx = meshverts[face.first_mv + i_idx]
						var b_idx = meshverts[face.first_mv + i_idx + 1]
						var c_idx = meshverts[face.first_mv + i_idx + 2]
						var vertex_indices = [a_idx, b_idx, c_idx]
						for mv_idx in vertex_indices:
							if mv_idx < 0 or mv_idx >= face.num_verts:
								continue
							var v_idx = face.first_vert + mv_idx
							if v_idx >= verts.size():
								if debug_logging:
									print("Invalid vertex index %d for face %d" % [v_idx, face_idx])
								continue
							var vert = verts[v_idx]
							mat_data.id.append(mat_data.v.size())
							mat_data.v.append(vert.pos)
							mat_data.n.append(vert.normal)
							var uv_scale = shader_uv_scales.get(sh_name, Vector2(1.0, 1.0))
							var scaled_uv = Vector2(vert.uv.x * uv_scale.x, vert.uv.y * uv_scale.y)
							if not scaled_uv.is_finite() or abs(scaled_uv.x) > 1000.0 or abs(scaled_uv.y) > 1000.0:
								if debug_logging:
									print("Invalid scaled UV for face %d, vertex %d: uv=%s, using (0,0)" % [face_idx, v_idx, scaled_uv])
								scaled_uv = Vector2(0.0, 0.0)
							if sh_name in ["map_boil/frogg", "map_boil/brush", "map_boil/credit"]:
								scaled_uv = Vector2(-scaled_uv.x, scaled_uv.y) # Flip U for graffiti
							mat_data.uv.append(scaled_uv)
							mat_data.luv.append(vert.luv / Vector2(128, 128))
							mat_data.color.append(vert.color)
							if sh_name not in non_solid_shaders:
								col_vertices.append(vert.pos)
							if i_idx == 0 and mv_idx == vertex_indices[0] and debug_logging:
								print("Face %d UV: pos=%s, uv=%s" % [face_idx, vert.pos, scaled_uv])
			var surface_idx = 0
			for sh_name in ent_by_mat.keys():
				var data = ent_by_mat[sh_name]
				if data.v.is_empty() or data.id.is_empty():
					continue
				var arr = []
				arr.resize(Mesh.ARRAY_MAX)
				arr[Mesh.ARRAY_VERTEX] = data.v
				arr[Mesh.ARRAY_NORMAL] = data.n
				arr[Mesh.ARRAY_TEX_UV] = data.uv
				arr[Mesh.ARRAY_TEX_UV2] = data.luv
				arr[Mesh.ARRAY_COLOR] = data.color
				arr[Mesh.ARRAY_INDEX] = data.id
				ent_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				ent_mesh.surface_set_name(surface_idx, sh_name)
				if materials.has(sh_name):
					var mat = materials[sh_name]
					if data.lm_index >= 0 and lightmap_textures.has(data.lm_index):
						var lm_mat = mat.duplicate()
						lm_mat.set_texture(BaseMaterial3D.TEXTURE_ALBEDO, lightmap_textures[data.lm_index])
						lm_mat.uv2_scale = Vector3(1.0, 1.0, 1.0)
						ent_mesh.surface_set_material(surface_idx, lm_mat)
					else:
						ent_mesh.surface_set_material(surface_idx, mat)
					if debug_logging:
						print("Applied material %s to surface %d with name %s" % [sh_name, surface_idx, sh_name])
				else:
					if debug_logging:
						print("No material found for shader %s, using fallback" % sh_name)
					var fallback_mat = StandardMaterial3D.new()
					fallback_mat.albedo_color = Color(0.5, 0.5, 0.5)
					fallback_mat.metallic = 0.0
					fallback_mat.roughness = 1.0
					fallback_mat.anisotropy_enabled = false
					fallback_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					ent_mesh.surface_set_material(surface_idx, fallback_mat)
					ent_mesh.surface_set_name(surface_idx, sh_name + "_missing")
				surface_idx += 1
			if ent_mesh.get_surface_count() > 0:
				var ent_mi = MeshInstance3D.new()
				ent_mi.mesh = ent_mesh
				ent_mi.name = "Geometry"
				node.add_child(ent_mi)
				ent_mi.owner = root
				if debug_logging:
					print("Added geometry for entity: %s with %d surfaces" % [node_name, ent_mesh.get_surface_count()])
				if not col_vertices.is_empty() and (classname == "worldspawn" or is_collidable):
					if debug_logging:
						print("Creating collision for entity: ", node_name)
					var col_shape = CollisionShape3D.new()
					var concave_shape = ConcavePolygonShape3D.new()
					var faces_array = []
					for i in range(0, col_vertices.size() - 2, 3):
						var v0 = col_vertices[i]
						var v1 = col_vertices[i + 1]
						var v2 = col_vertices[i + 2]
						if v0.distance_to(v1) > 0.001 and v1.distance_to(v2) > 0.001 and v2.distance_to(v0) > 0.001:
							faces_array.append(v0)
							faces_array.append(v1)
							faces_array.append(v2)
					if faces_array.size() > 0 and faces_array.size() % 3 == 0:
						concave_shape.set_faces(faces_array)
						col_shape.shape = concave_shape
						col_shape.name = "Collision"
						node.add_child(col_shape)
						col_shape.owner = root
						if debug_logging:
							print("Collision vertices: %d for entity: %s" % [faces_array.size(), node_name])
					else:
						if debug_logging:
							print("Invalid collision vertices (%d, mod 3 = %d) for entity: %s" % [faces_array.size(), faces_array.size() % 3, node_name])
				else:
					if debug_logging:
						print("No collision vertices or non-collidable entity: %s" % node_name)
			else:
				if debug_logging:
					print("No geometry generated for entity: %s" % node_name)
		
		if classname in ITEM_ENTITIES or classname in WEAPON_ENTITIES:
			var col_shape = CollisionShape3D.new()
			col_shape.name = "Collision"
			col_shape.shape = BoxShape3D.new()
			col_shape.shape.extents = Vector3(0.25, 0.25, 0.25)
			node.add_child(col_shape)
			col_shape.owner = root
			if debug_logging:
				print("Added collision for item/weapon: %s" % node_name)
		
		if classname.begins_with("info_player"):
			if player_model_path and FileAccess.file_exists(player_model_path):
				var model = load(player_model_path)
				var model_instance = MeshInstance3D.new()
				model_instance.mesh = model
				model_instance.scale = Vector3(scale_factor, scale_factor, scale_factor)
				node.add_child(model_instance)
				model_instance.owner = root
			var col_shape = CollisionShape3D.new()
			col_shape.name = "Collision"
			col_shape.shape = BoxShape3D.new()
			col_shape.shape.extents = Vector3(0.25, 1.0, 0.25)
			node.add_child(col_shape)
			col_shape.owner = root
			if debug_logging:
				print("Added collision for info_player: %s" % node_name)
		
		if classname in TRIGGER_ENTITIES or classname in GOAL_ENTITIES:
			var model = models[model_idx] if model_idx >= 0 and model_idx < models.size() else null
			if model:
				var center = (model.mins + model.maxs) / 2.0
				node.position = center
				var faces_array = extract_brush_vertices(model, brushes, brushsides, planes, shaders)
				if faces_array.size() > 0 and faces_array.size() % 3 == 0:
					# Only apply rotation if entity has angles
					if ent.has("angles"):
						var rotation = parse_vector3(ent.angles)
						var transform = Transform3D.IDENTITY
						transform = transform.rotated(Vector3.RIGHT, deg_to_rad(rotation.x))
						transform = transform.rotated(Vector3.UP, deg_to_rad(rotation.y))
						transform = transform.rotated(Vector3.FORWARD, deg_to_rad(rotation.z))
						var rotated_faces = PackedVector3Array()
						for v in faces_array:
							rotated_faces.append(transform.basis * v)
						faces_array = rotated_faces
					# Create collision shape
					var col_shape = CollisionShape3D.new()
					var concave_shape = ConcavePolygonShape3D.new()
					concave_shape.set_faces(faces_array)
					col_shape.shape = concave_shape
					col_shape.name = "TriggerShape"
					node.add_child(col_shape)
					col_shape.owner = root
					# Create debug mesh
					var debug_mesh = MeshInstance3D.new()
					var debug_array_mesh = ArrayMesh.new()
					var arr = []
					arr.resize(Mesh.ARRAY_MAX)
					arr[Mesh.ARRAY_VERTEX] = faces_array
					debug_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
					var debug_mat = StandardMaterial3D.new()
					debug_mat.albedo_color = Color(1, 0, 0, 0.5)
					debug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					debug_array_mesh.surface_set_material(0, debug_mat)
					debug_mesh.mesh = debug_array_mesh
					debug_mesh.name = "DebugTriggerMesh"
					node.add_child(debug_mesh)
					debug_mesh.owner = root
					# Update AABB
					var aabb = AABB()
					for v in faces_array:
						aabb = aabb.expand(v)
					debug_array_mesh.custom_aabb = aabb
					if debug_logging:
						print("Added trigger shape for entity: %s with %d vertices, center: %s" % [node_name, faces_array.size(), center])
				else:
					if debug_logging:
						print("Failed to generate trigger vertices (%d, mod 3 = %d) for entity: %s" % [faces_array.size(), faces_array.size() % 3, node_name])
			else:
				if debug_logging:
					print("No model found for trigger entity: %s" % node_name)
		
		if classname in COLLIDABLE_FUNC_ENTITIES and is_collidable:
			var model = models[model_idx] if model_idx >= 0 and model_idx < models.size() else null
			if model:
				var area = node.get_node("InteractionArea")
				if area:
					var col_shape = CollisionShape3D.new()
					col_shape.name = "InteractionShape"
					var concave_shape = ConcavePolygonShape3D.new()
					var faces_array = extract_brush_vertices(model, brushes, brushsides, planes, shaders)
					if faces_array.size() > 0 and faces_array.size() % 3 == 0:
						concave_shape.set_faces(faces_array)
						col_shape.shape = concave_shape
						col_shape.position = (model.mins + model.maxs) / 2.0
						area.add_child(col_shape)
						col_shape.owner = root
						if debug_logging:
							print("Added interaction shape for func entity: %s with %d vertices" % [node_name, faces_array.size()])
			node.set_script(load("res://addons/bsp_loader/scripts/func_entity.gd"))
		
		if classname in TRIGGER_ENTITIES:
			node.set_script(load("res://addons/bsp_loader/scripts/trigger_entity.gd"))
	
	emit_signal("progress_updated", "Done", 100.0)
	if debug_logging:
		print("Faces:%d  Surfaces:%d  Entities:%d" % [faces.size(), root.get_child_count(), entities.size()])
	return root

func transform_vector(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)

func read_null_terminated_string(file: FileAccess, max_length: int) -> String:
	var bytes: PackedByteArray = []
	var count: int = 0
	while count < max_length:
		var byte = file.get_8()
		if byte == 0:
			break
		bytes.append(byte)
		count += 1
	return bytes.get_string_from_utf8()

func parse_entities(data: String) -> Array[Dictionary]:
	var entities: Array[Dictionary] = []
	var current: Dictionary = {}
	var in_entity := false
	var key: String = ""
	var value: String = ""
	var parsing_key := true
	var in_quotes := false
	var i: int = 0
	
	while i < data.length():
		var c = data[i]
		
		if c == "{" and not in_quotes:
			current = {}
			in_entity = true
			parsing_key = true
			key = ""
			value = ""
			i += 1
			continue
		
		if c == "}" and not in_quotes:
			if in_entity:
				if key != "":
					current[key] = value.strip_edges()
				if not current.is_empty():
					entities.append(current)
			current = {}
			in_entity = false
			parsing_key = true
			key = ""
			value = ""
			i += 1
			continue
		
		if c == "\"" and in_entity:
			in_quotes = not in_quotes
			if not in_quotes and parsing_key:
				parsing_key = false
			elif not in_quotes and not parsing_key:
				current[key] = value.strip_edges()
				key = ""
				value = ""
				parsing_key = true
			i += 1
			continue
		
		if in_entity and in_quotes:
			if parsing_key:
				key += c
			else:
				value += c
			i += 1
			continue
		
		i += 1
	
	if in_entity and not current.is_empty():
		if key != "":
			current[key] = value.strip_edges()
		entities.append(current)
	
	if entities.is_empty():
		if debug_logging:
			print("Entity parsing failed. Raw data: ", data.substr(0, 200), "...")
	else:
		if debug_logging:
			print("Parsed %d entities" % entities.size())
	
	return entities

func parse_vector3(s: String) -> Vector3:
	var parts = s.split(" ", false)
	if parts.size() >= 3:
		return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	return Vector3()

func is_brush_collidable(model: Dictionary, brushes: Array[Dictionary], brushsides: Array[Dictionary], shaders: Array[Dictionary]) -> bool:
	var solid_count = 0
	var total_sides = 0
	for brush_idx in range(model.first_brush, model.first_brush + model.num_brushes):
		var brush = brushes[brush_idx]
		for side_idx in range(brush.first_side, brush.first_side + brush.num_sides):
			var side = brushsides[side_idx]
			var shader_num = side.shader_num
			if shader_num >= 0 and shader_num < shaders.size():
				var shader_name = shaders[shader_num].name
				if shader_name in SOLID_SHADERS:
					solid_count += 1
				elif shader_name in NON_RENDER_SHADERS and shader_name != "common/invisible":
					solid_count -= 1
			total_sides += 1
	if debug_logging:
		print("Brush collidability: solid_count=%d, total_sides=%d" % [solid_count, total_sides])
	return solid_count > total_sides / 2

func extract_brush_vertices(model: Dictionary, brushes: Array[Dictionary], brushsides: Array[Dictionary], planes: Array[Dictionary], shaders: Array[Dictionary]) -> PackedVector3Array:
	var vertices: PackedVector3Array = []
	for brush_idx in range(model.first_brush, model.first_brush + model.num_brushes):
		if brush_idx < 0 or brush_idx >= brushes.size():
			if debug_logging:
				print("Invalid brush index %d for model, range %d-%d" % [brush_idx, model.first_brush, model.first_brush + model.num_brushes])
			continue
		var brush = brushes[brush_idx]
		var brush_planes: Array[Dictionary] = []
		var is_valid_brush = true
		for side_idx in range(brush.first_side, brush.first_side + brush.num_sides):
			if side_idx < 0 or side_idx >= brushsides.size():
				if debug_logging:
					print("Invalid brushside index %d for brush %d" % [side_idx, brush_idx])
				is_valid_brush = false
				break
			var side = brushsides[side_idx]
			if side.plane_num < 0 or side.plane_num >= planes.size():
				if debug_logging:
					print("Invalid plane_num %d for brush %d, side %d" % [side.plane_num, brush_idx, side_idx])
				is_valid_brush = false
				break
			brush_planes.append(planes[side.plane_num])
		if not is_valid_brush:
			if debug_logging:
				print("Skipping invalid brush %d: valid=%s, planes=%d" % [brush_idx, is_valid_brush, brush_planes.size()])
			continue
		if brush_planes.size() < 4:
			if debug_logging:
				print("Skipping brush %d with insufficient planes: %d" % [brush_idx, brush_planes.size()])
			continue
		var brush_vertices = intersect_planes(brush_planes)
		if brush_vertices.size() == 0:
			if debug_logging:
				print("No vertices for brush %d, planes: %s" % [brush_idx, brush_planes])
			continue
		var hull_vertices = convex_hull(brush_vertices)
		for i in range(0, hull_vertices.size() - 2, 3):
			var v0 = transform_vector(hull_vertices[i]) * scale_factor
			var v1 = transform_vector(hull_vertices[i + 1]) * scale_factor
			var v2 = transform_vector(hull_vertices[i + 2]) * scale_factor
			if v0.distance_to(v1) > 0.001 and v1.distance_to(v2) > 0.001 and v2.distance_to(v0) > 0.001:
				vertices.append(v0)
				vertices.append(v1)
				vertices.append(v2)
	if vertices.size() == 0:
		if debug_logging:
			print("No valid vertices for model, brushes %d-%d" % [model.first_brush, model.first_brush + model.num_brushes])
	elif vertices.size() % 3 != 0:
		if debug_logging:
			print("Invalid vertex count (%d) for brush, adjusting to multiple of 3" % vertices.size())
		var new_size = (vertices.size() / 3) * 3
		var new_vertices = PackedVector3Array()
		for i in range(new_size):
			new_vertices.append(vertices[i])
		vertices = new_vertices
	return vertices

func intersect_planes(brush_planes: Array[Dictionary]) -> PackedVector3Array:
	var vertices: PackedVector3Array = []
	var max_vertices: int = 1000
	var vertex_count: int = 0
	
	for i in range(brush_planes.size()):
		for j in range(i + 1, brush_planes.size()):
			for k in range(j + 1, brush_planes.size()):
				var p1 = brush_planes[i]
				var p2 = brush_planes[j]
				var p3 = brush_planes[k]
				var n1 = p1.normal
				var n2 = p2.normal
				var n3 = p3.normal
				var d1 = p1.dist
				var d2 = p2.dist
				var d3 = p3.dist
				
				var denom = n1.dot(n2.cross(n3))
				if abs(denom) < 0.0001:
					continue
				
				var v = (
					d1 * (n2.cross(n3)) +
					d2 * (n3.cross(n1)) +
					d3 * (n1.cross(n2))
				) / denom
				
				var valid = true
				for p in brush_planes:
					if p1 == p or p2 == p or p3 == p:
						continue
					var dist = p.normal.dot(v) - p.dist
					if dist > 0.001:
						valid = false
						break
				if valid:
					vertices.append(v)
					vertex_count += 1
					if vertex_count >= max_vertices:
						if debug_logging:
							print("Max vertices reached for brush")
						return vertices
	
	if vertices.size() == 0:
		if debug_logging:
			print("No vertices generated from plane intersections")
	return vertices

func convex_hull(points: PackedVector3Array) -> PackedVector3Array:
	if points.size() < 4:
		if debug_logging:
			print("Convex hull: too few points (%d), returning original" % points.size())
		return points
	
	# Use Geometry3D.compute_convex_mesh_points to get hull points
	var hull_points = Geometry3D.compute_convex_mesh_points(points)
	if hull_points.size() < 4:
		if debug_logging:
			print("Failed to generate convex hull, falling back to raw vertices")
		var fallback = PackedVector3Array()
		for i in range(0, min(points.size(), 9), 3):
			if i + 2 < points.size():
				fallback.append(points[i])
				fallback.append(points[i + 1])
				fallback.append(points[i + 2])
		return fallback
	
	# Triangulate the hull points into faces for ConcavePolygonShape3D
	var hull_vertices = PackedVector3Array()
	# Simple triangulation: assume points form a convex polyhedron and use a fan
	for i in range(1, hull_points.size() - 1):
		hull_vertices.append(hull_points[0])
		hull_vertices.append(hull_points[i])
		hull_vertices.append(hull_points[i + 1])
	
	if hull_vertices.size() > 0:
		if debug_logging:
			print("Convex hull generated %d triangles from %d points" % [hull_vertices.size() / 3, hull_points.size()])
		return hull_vertices
	
	# Fallback if triangulation fails
	if debug_logging:
		print("Failed to triangulate convex hull, falling back to raw vertices")
	var fallback = PackedVector3Array()
	for i in range(0, min(points.size(), 9), 3):
		if i + 2 < points.size():
			fallback.append(points[i])
			fallback.append(points[i + 1])
			fallback.append(points[i + 2])
	return fallback
