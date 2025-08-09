class_name BSPTextureLoader
extends RefCounted

var texture_base_paths: Array[String] = [
	"/workspace/XONOTIC_DATA"
]
var valid_extensions: Array[String] = ["tga", "png", "jpg", "jpeg", "bmp"]
var cached_texture_string: String = ""
var texture_scan_cache: Dictionary = {}
var non_solid_shaders: Array[String] = []
var shader_data: Dictionary = {} # Global shader definitions
var debug_logging: bool = false # Control verbosity of logging

func load_all_shader_files() -> void:
	var scripts_dir = "/workspace/XONOTIC_DATA/scripts/"
	var dir = DirAccess.open(scripts_dir)
	if not dir:
		if debug_logging:
			print("Failed to open scripts directory: %s" % scripts_dir)
		return

	var shader_files: Array[String] = []
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".shader"):
			shader_files.append(scripts_dir.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()

	# Sort files alphabetically
	shader_files.sort()

	# Parse each shader file
	for shader_file in shader_files:
		var file_data = parse_shader_file(shader_file)
		for shader_name in file_data.keys():
			shader_data[shader_name] = file_data[shader_name]
			if debug_logging:
				print("Loaded shader %s from %s" % [shader_name, shader_file])

func parse_shader_file(path: String) -> Dictionary:
	var file_data: Dictionary = {}
	if not FileAccess.file_exists(path):
		if debug_logging:
			print("Shader file not found: %s" % path)
		return file_data

	var file = FileAccess.open(path, FileAccess.READ)
	var current_shader: String = ""
	var current_block: Dictionary = {}
	var in_shader: bool = false
	var in_stage: bool = false
	var brace_level: int = 0

	while not file.eof_reached():
		var raw_line = file.get_line()
		var line = raw_line.strip_edges()
		var lower_line = line.to_lower()
		if line.begins_with("//") or line == "":
			continue
		if line.begins_with("textures/"):
			current_shader = line.replace("textures/", "")
			current_block = {"surfaceparms": [], "stages": [], "cull": "", "sky_env": ""}
			file_data[current_shader] = current_block
			in_shader = true
			brace_level = 0
			in_stage = false
			continue
		if in_shader:
			if line == "{":
				brace_level += 1
				if brace_level == 2:
					# Entering a stage block
					in_stage = true
					current_block["stages"].append({})
				continue
			if line == "}":
				if brace_level == 2 and in_stage:
					# Leaving a stage block
					in_stage = false
				elif brace_level == 1:
					# Leaving shader block
					in_shader = false
					if debug_logging:
						print("Parsed shader %s: %s" % [current_shader, current_block])
				brace_level = max(0, brace_level - 1)
				continue
			if in_stage:
				var parts = line.split(" ", false)
				if parts.size() > 0:
					var key = String(parts[0]).to_lower()
					if key in ["map", "blendfunc", "alphafunc"]:
						var stage = {}
						if key == "map":
							stage["map"] = parts[1].replace("textures/", "") if parts.size() > 1 else ""
						elif key == "blendfunc":
							if parts.size() == 2 and parts[1] == "blend":
								stage["blendFunc"] = ["GL_SRC_ALPHA", "GL_ONE_MINUS_SRC_ALPHA"]
							elif parts.size() > 2:
								stage["blendFunc"] = parts.slice(1)
						elif key == "alphafunc":
							stage["alphaFunc"] = parts[1] if parts.size() > 1 else ""
						if stage:
							current_block["stages"].append(stage)
			else:
				# Shader-level directives
				if lower_line.begins_with("surfaceparm"):
					var tokens = line.split(" ")
					var parm = tokens[1] if tokens.size() > 1 else ""
					current_block["surfaceparms"].append(parm)
					if parm == "nonsolid":
						non_solid_shaders.append(current_shader)
				elif lower_line.begins_with("skyparms"):
					# Format: skyParms env/<name> [cloudheight] [outerbox] [innerbox]
					var sky_parts = line.split(" ", false)
					if sky_parts.size() >= 2 and sky_parts[1].begins_with("env/"):
						current_block["sky_env"] = sky_parts[1].replace("env/", "").strip_edges()
				elif lower_line == "cull none":
					current_block["cull"] = "none"
	file.close()
	return file_data

func load_textures(shaders: Array[Dictionary], faces: Array[Dictionary]) -> Dictionary:
	var texture_dir = "res://assets/textures/"
	DirAccess.make_dir_recursive_absolute(texture_dir)
	
	# Load all shader files
	load_all_shader_files()
	
	# Filter shaders used by renderable faces
	var used_shader_indices: Array[int] = []
	for face in faces:
		if face["shader_num"] >= 0 and face["shader_num"] < shaders.size():
			if not used_shader_indices.has(face["shader_num"]):
				used_shader_indices.append(face["shader_num"])
	
	var used_shaders: Array[Dictionary] = []
	for idx in used_shader_indices:
		var shader = shaders[idx]
		if shader["name"] not in BSPCommon.NON_RENDER_SHADERS or shader["name"] == "common/invisible":
			used_shaders.append(shader)
	
	if debug_logging:
		print("Loading textures for %d used shaders: %s" % [used_shaders.size(), used_shaders.map(func(s): return s.get("name", "INVALID_SHADER"))])
	
	# Create required folders
	var required_folders: Array[String] = []
	for sh in used_shaders:
		var top_level = String(sh["name"]).get_base_dir().split("/")[0]
		if top_level and not required_folders.has(top_level):
			required_folders.append(top_level)
			var folder_path = texture_dir.path_join(top_level)
			DirAccess.make_dir_recursive_absolute(folder_path)
			if debug_logging:
				print("Created folder: %s" % folder_path)
	
	# Scan textures
	var texture_cache = {"files": [], "textures": {}}
	if debug_logging:
		print("REQUIRED FOLDERS: " + str(required_folders))
	if texture_scan_cache.is_empty():
		scan_textures(required_folders)
	
	# Match and copy textures
	var suffixes: Array[String] = ["_norm", "_glow", "_gloss", "_reflect"]
	var special_keywords: Array[String] = ["$lightmap", "$whiteimage", "$blackimage"]
	for sh in used_shaders:
		var shader_name = sh["name"]
		var tex_name = shader_name
		var map_texture = ""
		if shader_data.has(shader_name) and shader_data[shader_name].has("stages"):
			if debug_logging:
				print("Shader stages for %s: %s" % [shader_name, shader_data[shader_name]["stages"]])
			for stage in shader_data[shader_name]["stages"]:
				if stage.has("map") and stage["map"] and stage["map"] not in special_keywords:
					map_texture = String(stage["map"]).get_basename()
					tex_name = map_texture
					break
		if not map_texture or map_texture in special_keywords:
			tex_name = shader_name
		var matched_textures = match_texture_no_one_is_allowed_to_modify_this_function(tex_name, suffixes)
		if map_texture and not matched_textures.has(""):
			matched_textures = match_texture_no_one_is_allowed_to_modify_this_function(shader_name, suffixes)
		if debug_logging:
			print("MATCHED TEXTURES for %s (tried %s): %s" % [shader_name, tex_name, matched_textures])
		for suffix in matched_textures:
			var tex_key = shader_name + suffix
			var dst = "res://assets/textures/" + shader_name + suffix + ".png"
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			if matched_textures[suffix].begins_with("zip:"):
				var zip = ZIPReader.new()
				var err = zip.open(matched_textures[suffix].get_base_dir())
				if err == OK:
					var bytes = zip.read_file(matched_textures[suffix].substr(4))
					var img = Image.new()
					var ext = matched_textures[suffix].get_extension().to_lower()
					var load_err = OK
					if ext == "tga":
						load_err = img.load_tga_from_buffer(bytes)
					elif ext == "png":
						load_err = img.load_png_from_buffer(bytes)
					elif ext == "jpg" or ext == "jpeg":
						load_err = img.load_jpg_from_buffer(bytes)
					elif ext == "bmp":
						load_err = img.load_bmp_from_buffer(bytes)
					else:
						if debug_logging:
							print("Unsupported texture format: %s for %s" % [ext, shader_name])
						continue
					if load_err == OK and not img.is_empty():
						img.save_png(dst)
						if suffix == "":
							texture_cache["textures"][shader_name] = ImageTexture.create_from_image(img)
						texture_cache["textures"][tex_key] = ImageTexture.create_from_image(img)
						if debug_logging:
							print("Extracted and saved texture: %s" % dst)
					else:
						if debug_logging:
							print("Failed to load texture: %s (Error: %d, Empty: %s)" % [matched_textures[suffix], load_err, img.is_empty()])
					zip.close()
				else:
					if debug_logging:
						print("Failed to open PK3: %s (Error: %d)" % [matched_textures[suffix], err])
			else:
				var src = matched_textures[suffix]
				if FileAccess.file_exists(src):
					var img = Image.new()
					var load_err = img.load(src)
					if load_err == OK and not img.is_empty():
						img.save_png(dst)
						if suffix == "":
							texture_cache["textures"][shader_name] = ImageTexture.create_from_image(img)
						texture_cache["textures"][tex_key] = ImageTexture.create_from_image(img)
						if debug_logging:
							print("Loaded and saved texture: %s" % dst)
					else:
						if debug_logging:
							print("Failed to load texture: %s (Error: %d, Empty: %s)" % [src, load_err, img.is_empty()])
				else:
					if debug_logging:
						print("Texture file not found: %s" % src)
	
	if debug_logging:
		print("TEXTURE CACHE KEYS: %s" % texture_cache["textures"].keys())
	return texture_cache

func scan_textures(required_folders: Array[String]) -> void:
	cached_texture_string = ""
	
	for base_path in texture_base_paths:
		var cache_key = base_path + str(required_folders)
		if texture_scan_cache.has(cache_key):
			cached_texture_string += texture_scan_cache[cache_key] + "\n"
			continue
		var path_string = ""
		
		# Collect and sort PK3 files
		var pk3_files: Array[String] = []
		var dir = DirAccess.open(base_path)
		if dir:
			if debug_logging:
				print("Opened directory: %s" % base_path)
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".pk3"):
					pk3_files.append(base_path.path_join(file_name))
				file_name = dir.get_next()
			dir.list_dir_end()
		else:
			if debug_logging:
				print("Failed to open directory: %s" % base_path)
		
		# Sort PK3 files alphabetically
		pk3_files.sort()
		if debug_logging:
			print("PK3 files found: ", pk3_files)
		
		# Process PK3 files
		for pk3_path in pk3_files:
			var zip = ZIPReader.new()
			if zip.open(pk3_path) == OK:
				for file in zip.get_files():
					var ext = file.get_extension().to_lower()
					if valid_extensions.has(ext) and file.begins_with("textures/"):
						if path_string != "":
							path_string += "\n"
						path_string += "zip:" + pk3_path + "/" + file
				zip.close()
			else:
				if debug_logging:
					print("Failed to open PK3: %s" % pk3_path)
		
		# Process regular files in textures/ subdirectory
		var textures_dir = base_path.path_join("textures")
		if DirAccess.dir_exists_absolute(textures_dir):
			for file_info in scan_directory(textures_dir):
				if path_string != "":
					path_string += "\n"
				path_string += file_info.path
		else:
			if debug_logging:
				print("Textures directory not found: %s" % textures_dir)
		
		texture_scan_cache[cache_key] = path_string
		cached_texture_string += path_string + "\n"

func scan_directory(path: String) -> Array:
	var files: Array = []
	var dir = DirAccess.open(path)
	if not dir:
		var global_path = ProjectSettings.globalize_path(path)
		dir = DirAccess.open(global_path)
		if not dir:
			if debug_logging:
				print("Failed to open directory for scanning: %s" % path)
			return files

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var full_path = path.path_join(file_name)
		if dir.current_is_dir():
			files.append_array(scan_directory(full_path))
		else:
			var ext = file_name.get_extension().to_lower()
			if valid_extensions.has(ext):
				var rel_path = full_path.replace(path.get_base_dir(), "").trim_prefix("/")
				files.append({
					"path": full_path,
					"source": "dir",
					"rel_path": rel_path,
					"ext": "." + ext
				})
		file_name = dir.get_next()
	dir.list_dir_end()
	return files

func generate_shader_path_variants(parts: Array, no_strip_end: bool = false) -> Array:
	var result := []
	var dirs = parts.duplicate()
	if not no_strip_end:
		dirs = dirs.slice(0, max(0, dirs.size() - 1))
	var n = dirs.size()
	if no_strip_end:
		if parts.size() < 1:
			return result
		var rev = dirs.duplicate()
		rev.reverse()
		for i in range(rev.size()):
			for j in range(i + 1, rev.size() + 1):
				if j - i <= 0:
					continue
				var slice = rev.slice(i, j)
				slice.reverse()
				result.append(String("_").join(slice))
				result.append(String("-").join(slice))
	else:
		if parts.size() < 2:
			return result
		for i in range(n):
			for j in range(i + 1, n + 1):
				if j - i <= 0:
					continue
				var slice = dirs.slice(i, j)
				result.append(String("_").join(slice))
				result.append(String("-").join(slice))
				result.append(String("/").join(slice))
	return result

func dedupe_array(arr: Array) -> Array:
	var seen := {}
	var out := []
	for v in arr:
		if not seen.has(v):
			seen[v] = true
			out.append(v)
	return out

func match_texture_no_one_is_allowed_to_modify_this_function(shader_name: String, suffixes: Array[String]) -> Dictionary:
	var shader_parts = shader_name.strip_edges().get_file().replace("-", "_").split("_")
	var shader_parts2 = shader_name.strip_edges().get_file().replace("-", "_").replace("/", "_").split("_")
	var pattern_variants = generate_shader_path_variants(shader_parts).map(func(p): return p)
	var base_path_regex = "(" + String("|").join(dedupe_array(pattern_variants.filter(func(v): return v != "" and v != "/")).map(func(v): return v + "/")) + ")?" if pattern_variants.size() > 0 else ""
	var pattern_variants2 = generate_shader_path_variants(shader_parts2, true).map(func(p): return p)
	var base_path_regex2 = "(" + String("|").join(dedupe_array(pattern_variants2.filter(func(v): return v != "" and v != "/")).map(func(v): return "" + v)) + ")" if pattern_variants2.size() > 0 else ""
	var matched_textures: Dictionary = {}
	var regex = RegEx.new()
	var pattern = ""
	var do_crazy = true
	for crazy_bullshit in ["", "([-_][0-9]+)+"]:
		if do_crazy:
			pattern = "(?i).*/textures/" + shader_name.strip_edges().get_base_dir().replace("-", "[/-]").replace("_", "[/_]") + "/" + base_path_regex + base_path_regex2 + crazy_bullshit + "(" + String("|").join(suffixes) + ")?\\." + "(" + String("|").join(valid_extensions) + ")\\s*(\\n|\\z)"
			var err = regex.compile(pattern)
			if err != OK:
				if debug_logging:
					print("Regex compile error for shader: %s, suffix: %s (Pattern: %s, Error: %d)" % [shader_name, str(suffixes), pattern, err])
			var results = regex.search_all(cached_texture_string)
			if results:
				results.reverse()
				for result in results:
					var cleaned_result = result.get_string().strip_edges()
					for ext in valid_extensions:
						var ends_with_suffix = false
						for suffix in suffixes:
							if cleaned_result.ends_with(suffix + "." + ext):
								ends_with_suffix = true
								matched_textures[suffix] = cleaned_result
								do_crazy = false
						if not ends_with_suffix and cleaned_result.ends_with("." + ext):
							matched_textures[""] = cleaned_result
							do_crazy = false
	
	if matched_textures.is_empty():
		if debug_logging:
			print("SHADER NOT FOUND!!!: %s (Pattern: %s)" % [shader_name, pattern])
		
	return matched_textures

func create_materials(shaders: Array[Dictionary], texture_cache: Dictionary) -> Dictionary:
	var materials: Dictionary = {}
	if not texture_cache.has("textures"):
		texture_cache["textures"] = {}
	
	for sh in shaders:
		var sh_name = sh["name"]
		if sh_name in BSPCommon.NON_RENDER_SHADERS and sh_name != "common/invisible":
			if sh_name == "noshader":
				var mat = StandardMaterial3D.new()
				mat.resource_name = sh_name
				mat.albedo_color = Color(0, 0, 0, 0)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				materials[sh_name] = mat
				if debug_logging:
					print("Created transparent material for %s" % sh_name)
			continue
		var mat = StandardMaterial3D.new()
		mat.resource_name = sh_name # Set material name to shader name
		var found_base = false
		# Try shader name first
		var tex_key = sh_name
		if texture_cache["textures"].has(tex_key):
			mat.albedo_texture = texture_cache["textures"][tex_key]
			var img = texture_cache["textures"][tex_key].get_image()
			if img and img.detect_alpha() != Image.ALPHA_NONE:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.alpha_scissor_threshold = 0.5
			else:
				if debug_logging:
					print("Warning: Texture %s for material %s has no alpha channel" % [tex_key, sh_name])
			found_base = true
			if debug_logging:
				print("Applied texture %s to material %s" % [tex_key, sh_name])
		# Fallback to map directive
		if not found_base and shader_data.has(sh_name) and shader_data[sh_name].has("stages"):
			for stage in shader_data[sh_name]["stages"]:
				if stage.has("map") and stage["map"] and not stage["map"].begins_with("$"):
					var map_name = String(stage["map"]).get_basename()
					if texture_cache["textures"].has(map_name):
						mat.albedo_texture = texture_cache["textures"][map_name]
						var img = texture_cache["textures"][map_name].get_image()
						if img and img.detect_alpha() != Image.ALPHA_NONE:
							mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
							mat.alpha_scissor_threshold = 0.5
						else:
							if debug_logging:
								print("Warning: Texture %s for material %s has no alpha channel" % [map_name, sh_name])
						found_base = true
						if debug_logging:
							print("Applied map texture %s to material %s (from map %s)" % [map_name, sh_name, stage["map"]])
						break
		if not found_base and sh_name == "common/invisible":
			var invisible_path = "res://assets/textures/common/invisible.tga"
			if FileAccess.file_exists(invisible_path):
				var img = Image.load_from_file(invisible_path)
				if img and not img.is_empty():
					mat.albedo_texture = ImageTexture.create_from_image(img)
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.alpha_scissor_threshold = 0.5
					found_base = true
				else:
					if debug_logging:
						print("Warning: Invisible texture %s not found or empty" % invisible_path)
			else:
				if debug_logging:
					print("Warning: Invisible texture %s not found" % invisible_path)
		if not found_base:
			if debug_logging:
				print("Warning: No texture found for material %s, using fallback" % sh_name)
			mat.albedo_color = Color(0.5, 0.5, 0.5, 1.0) # Gray fallback to avoid white
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		if texture_cache["textures"].has(sh_name + "_norm"):
			mat.normal_enabled = true
			mat.normal_texture = texture_cache["textures"][sh_name + "_norm"]
			if debug_logging:
				print("Applied normal texture %s to material %s" % [sh_name + "_norm", sh_name])
		if texture_cache["textures"].has(sh_name + "_glow"):
			mat.emission_enabled = true
			mat.emission_texture = texture_cache["textures"][sh_name + "_glow"]
			mat.emission = Color(1, 1, 1)
			mat.emission_energy = 1.0
			if debug_logging:
				print("Applied emission texture %s to material %s" % [sh_name + "_glow", sh_name])
		if texture_cache["textures"].has(sh_name + "_gloss"):
			mat.roughness_texture = texture_cache["textures"][sh_name + "_gloss"]
			mat.roughness_texture_channel = StandardMaterial3D.TEXTURE_CHANNEL_RED
			if debug_logging:
				print("Applied gloss texture %s to material %s" % [sh_name + "_gloss", sh_name])
		if texture_cache["textures"].has(sh_name + "_reflect"):
			mat.metallic = 1.0
			mat.metallic_texture = texture_cache["textures"][sh_name + "_reflect"]
			mat.metallic_texture_channel = StandardMaterial3D.TEXTURE_CHANNEL_RED
			if debug_logging:
				print("Applied reflect texture %s to material %s" % [sh_name + "_reflect", sh_name])
		
		# Apply shader properties
		if shader_data.has(sh_name):
			var sh_data = shader_data[sh_name]
			if sh_data.has("stages"):
				for stage in sh_data["stages"]:
					if stage.has("blendFunc") and stage["blendFunc"] in ["GL_SRC_ALPHA", "GL_ONE_MINUS_SRC_ALPHA"]:
						mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						mat.alpha_scissor_threshold = 0.5
						if debug_logging:
							print("Applied alpha blending for material %s" % sh_name)
					if stage.has("alphaFunc") and stage["alphaFunc"] == "GE128":
						mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
						mat.alpha_scissor_threshold = 0.5
						if debug_logging:
							print("Applied alpha testing (GE128) for material %s" % sh_name)
			if sh_data.has("surfaceparms") and "trans" in sh_data["surfaceparms"]:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.alpha_scissor_threshold = 0.5
				if debug_logging:
					print("Enabled transparency for material %s due to surfaceparm trans" % sh_name)
			if sh_data.has("cull") and sh_data["cull"] == "none":
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				if debug_logging:
					print("Disabled culling for material %s" % sh_name)
		
		materials[sh_name] = mat
	
	return materials

func get_non_solid_shaders() -> Array[String]:
	return non_solid_shaders

# Skybox helpers (parsed from shader skyParms env/<name>)
func has_skybox(shader_name: String) -> bool:
	return shader_data.has(shader_name) and shader_data[shader_name].has("sky_env") and shader_data[shader_name]["sky_env"] != ""

func get_skybox_name(shader_name: String) -> String:
	if has_skybox(shader_name):
		return String(shader_data[shader_name]["sky_env"])
	return ""

func load_skybox_textures(env_name: String) -> Dictionary:
	var result: Dictionary = {}
	if not env_name:
		return result
	var sides = {
		"rt": ["rt", "px"],
		"lf": ["lf", "nx"],
		"up": ["up", "py"],
		"dn": ["dn", "ny"],
		"ft": ["ft", "pz"],
		"bk": ["bk", "nz"]
	}
	# Search both loose files and inside pk3 archives under env/
	for base_path in texture_base_paths:
		# 1) Regular files
		for side in sides.keys():
			if result.has(side):
				continue
			for alias in sides[side]:
				for ext in valid_extensions:
					var p = base_path.path_join("env").path_join(env_name + "_" + alias + "." + ext)
					if FileAccess.file_exists(p):
						var img = Image.new()
						if img.load(p) == OK and not img.is_empty():
							result[side] = ImageTexture.create_from_image(img)
							break
				if result.has(side):
					continue
		# 2) PK3 archives
		var dir = DirAccess.open(base_path)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			var pk3_list: Array[String] = []
			while file_name != "":
				if file_name.ends_with(".pk3"):
					pk3_list.append(base_path.path_join(file_name))
				file_name = dir.get_next()
			dir.list_dir_end()
			pk3_list.sort()
			for pk3_path in pk3_list:
				var zip = ZIPReader.new()
				if zip.open(pk3_path) != OK:
					continue
				for side in sides.keys():
					if result.has(side):
						continue
					var found = false
					for alias in sides[side]:
						for ext in valid_extensions:
							var inside_path = "env/" + env_name + "_" + alias + "." + ext
							if zip.get_files().has(inside_path):
								var bytes = zip.read_file(inside_path)
								var img = Image.new()
								var ok = OK
								match ext:
									"tga":
										ok = img.load_tga_from_buffer(bytes)
									"png":
										ok = img.load_png_from_buffer(bytes)
									"jpg", "jpeg":
										ok = img.load_jpg_from_buffer(bytes)
									"bmp":
										ok = img.load_bmp_from_buffer(bytes)
									_:
										ok = ERR_FILE_UNRECOGNIZED
								if ok == OK and not img.is_empty():
									result[side] = ImageTexture.create_from_image(img)
									found = true
									break
						if found:
							continue
				zip.close()
	# Ensure we found all six sides
	for side in ["rt","lf","up","dn","ft","bk"]:
		if not result.has(side):
			# Missing side; return what we have (caller can skip if empty)
			return result
	return result

static func escape_regex(s: String) -> String:
	var special_chars = ".^$*+?()[]{}|"
	var escaped = ""
	for c in s:
		if special_chars.contains(c):
			escaped += "\\" + c
		else:
			escaped += c
	return escaped
