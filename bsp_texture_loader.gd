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

static func _strip_inline_comment(line: String) -> String:
	var comment_pos = line.find("//")
	if comment_pos >= 0:
		return line.substr(0, comment_pos)
	return line

static func _normalize_line(line: String) -> String:
	# Remove inline comments and normalize whitespace while isolating braces
	var s = _strip_inline_comment(line)
	# Replace tabs and carriage returns with spaces
	s = s.replace("\t", " ").replace("\r", "")
	# Isolate braces so we can detect them reliably
	s = s.replace("{", " { ").replace("}", " } ")
	# Collapse multiple spaces
	while s.find("  ") != -1:
		s = s.replace("  ", " ")
	return s.strip_edges()

static func _tokenize_ws(line: String) -> Array[String]:
	var s = _normalize_line(line)
	if s == "":
		return []
	return s.split(" ", false)

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
	var current_stage: Dictionary = {}
	var in_shader: bool = false
	var in_stage: bool = false
	var brace_level: int = 0

	while not file.eof_reached():
		var raw_line = file.get_line()
		var line = raw_line.strip_edges()
		var norm = _normalize_line(line)
		if norm == "" or norm.begins_with("//"):
			continue
		var lower_line = norm.to_lower()
		# Detect shader header (also handles "textures/foo {" on one line)
		if lower_line.begins_with("textures/") and not in_shader:
			var name_part = norm
			if name_part.find("{") != -1:
				name_part = name_part.get_slice("{", 0)
			current_shader = name_part.strip_edges().replace("textures/", "")
			current_block = {"surfaceparms": [], "stages": [], "cull": "", "sky_env": "", "qer_editorimage": ""}
			file_data[current_shader] = current_block
			in_shader = true
			brace_level = 0
			in_stage = false
			current_stage = {}
			# If the line also opened the block, count it
			if norm.find("{") != -1:
				brace_level += 1
			continue
		if in_shader:
			# Brace tracking (support braces on lines with tokens)
			if norm == "{" or norm.ends_with(" {") or norm.begins_with("{ "):
				brace_level += 1
				if brace_level == 2:
					in_stage = true
					current_stage = {}
				continue
			if norm == "}" or norm.ends_with(" }") or norm.begins_with("} "):
				if brace_level == 2 and in_stage:
					# End of stage
					in_stage = false
					if not current_stage.is_empty():
						current_block["stages"].append(current_stage)
					current_stage = {}
				elif brace_level == 1:
					# End of shader
					in_shader = false
					if debug_logging:
						print("Parsed shader %s: %s" % [current_shader, current_block])
				brace_level = max(0, brace_level - 1)
				continue
			if in_stage:
				var parts: Array[String] = _tokenize_ws(norm)
				if parts.size() == 0:
					continue
				var key = String(parts[0]).to_lower()
				match key:
					"map":
						# map <texture> | $lightmap
						if parts.size() > 1:
							var m = parts[1].strip_edges().trim_prefix("textures/")
							current_stage["map"] = m
					"clampmap":
						if parts.size() > 1:
							var cm = parts[1].strip_edges().trim_prefix("textures/")
							current_stage["map"] = cm
							current_stage["clamp"] = true
					"animmap":
						# animMap <freq> <tex1> <tex2> ...
						if parts.size() > 2:
							var freq = parts[1]
							var frames: Array = []
							for i in range(2, parts.size()):
								frames.append(parts[i].strip_edges().trim_prefix("textures/"))
							current_stage["animMap"] = {"freq": freq, "frames": frames}
							if frames.size() > 0 and not current_stage.has("map"):
								current_stage["map"] = frames[0]
					"blendfunc":
						# blendFunc <src> <dst> | add | filter | blend
						if parts.size() == 2:
							current_stage["blendFunc"] = parts[1].to_lower()
						elif parts.size() >= 3:
							current_stage["blendFunc"] = [parts[1], parts[2]]
					"alphafunc":
						if parts.size() > 1:
							current_stage["alphaFunc"] = parts[1].to_upper()
					"tcmod":
						# Collect tcMod operations in order for simple preview transforms
						if parts.size() >= 2:
							var op = parts[1].to_lower()
							var tcmods = current_stage.get("tcmods", [])
							match op:
								"scale":
									if parts.size() >= 4:
										tcmods.append({"op": "scale", "sx": float(parts[2]), "sy": float(parts[3])})
								"scroll":
									if parts.size() >= 4:
										tcmods.append({"op": "scroll", "ux": float(parts[2]), "uy": float(parts[3])})
								"rotate":
									if parts.size() >= 3:
										tcmods.append({"op": "rotate", "deg": float(parts[2])})
								"transform":
									if parts.size() >= 8:
										tcmods.append({
											"op": "transform",
											"a": float(parts[2]), "b": float(parts[3]), "c": float(parts[4]),
											"d": float(parts[5]), "e": float(parts[6]), "f": float(parts[7])
										})
							_:
								pass
						current_stage["tcmods"] = tcmods
					_:
						pass
			else:
				# Shader-level directives
				if lower_line.begins_with("surfaceparm"):
					var tokens = _tokenize_ws(norm)
					var parm = tokens[1] if tokens.size() > 1 else ""
					parm = String(parm).to_lower()
					current_block["surfaceparms"].append(parm)
					if parm == "nonsolid":
						non_solid_shaders.append(current_shader)
				elif lower_line.begins_with("qer_editorimage"):
					var tokens2 = _tokenize_ws(norm)
					if tokens2.size() > 1:
						var qei = tokens2[1].strip_edges().trim_prefix("textures/").trim_prefix("\"").trim_suffix("\"")
						current_block["qer_editorimage"] = qei
				elif lower_line.begins_with("skyparms"):
					# Format: skyParms env/<name> [cloudheight] [outerbox] [innerbox]
					var sky_parts = _tokenize_ws(norm)
					if sky_parts.size() >= 2 and String(sky_parts[1]).begins_with("env/"):
						current_block["sky_env"] = String(sky_parts[1]).replace("env/", "").strip_edges()
				elif lower_line.begins_with("cull"):
					# Accept: cull none|disable|twosided|back|front
					var c = _tokenize_ws(norm)
					if c.size() > 1:
						var v = String(c[1]).to_lower()
						if v in ["none", "disable", "twosided"]:
							current_block["cull"] = "none"
						else:
							current_block["cull"] = v
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
		var chosen_rel: String = ""
		var map_texture = ""
		# 1) Prefer qer_editorimage when present
		if shader_data.has(shader_name) and shader_data[shader_name].has("qer_editorimage") and String(shader_data[shader_name]["qer_editorimage"]) != "":
			chosen_rel = String(shader_data[shader_name]["qer_editorimage"]).trim_prefix("textures/")
		# 2) Else first non-$lightmap stage map/clampmap/animmap frame
		if chosen_rel == "" and shader_data.has(shader_name) and shader_data[shader_name].has("stages"):
			if debug_logging:
				print("Shader stages for %s: %s" % [shader_name, shader_data[shader_name]["stages"]])
			for stage in shader_data[shader_name]["stages"]:
				if stage.has("map") and stage["map"] and stage["map"] not in special_keywords:
					map_texture = String(stage["map"]).replace("textures/", "")
					chosen_rel = map_texture
					break
		# 3) Build matches: start with an exact-path search when we know the rel path
		var matched_textures: Dictionary = {}
		if chosen_rel != "":
			var found = find_texture_exact_rel(chosen_rel)
			if found != "":
				matched_textures[""] = found
		# 4) Merge with fallback heuristic to gather aux maps (_norm, _glow, ...)
		var fallback_try = shader_name if chosen_rel == "" else chosen_rel.get_file()
		var ht = match_texture_no_one_is_allowed_to_modify_this_function(fallback_try, suffixes)
		for k in ht.keys():
			if not matched_textures.has(k):
				matched_textures[k] = ht[k]
		if debug_logging:
			print("MATCHED TEXTURES for %s (rel=%s): %s" % [shader_name, chosen_rel, matched_textures])
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
						# Also alias by basename to support later lookups
						var base_alias = shader_name.get_file()
						texture_cache["textures"][base_alias + suffix] = ImageTexture.create_from_image(img)
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
						var base_alias2 = shader_name.get_file()
						texture_cache["textures"][base_alias2 + suffix] = ImageTexture.create_from_image(img)
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

func find_texture_exact_rel(rel: String) -> String:
	# Accept inputs like: "foo/bar", "foo/bar.tga", or "textures/foo/bar(.ext)"
	var rel_clean = rel.strip_edges().trim_prefix("textures/")
	var rel_no_ext = rel_clean
	if rel_no_ext.get_extension() != "":
		rel_no_ext = rel_no_ext.get_basename()
	# Build regex to find exact path under textures/
	var regex = RegEx.new()
	# Prefer later matches (later pk3s / later files)
	var found_path := ""
	for ext in valid_extensions:
		var pattern = "(?i).*/textures/" + escape_regex(rel_no_ext) + "\\." + ext + "\\s*(\\n|\\z)"
		if regex.compile(pattern) != OK:
			continue
		var results = regex.search_all(cached_texture_string)
		if results and results.size() > 0:
			# Use the last entry which represents the highest-priority pack by our scan order
			var cleaned = results[results.size() - 1].get_string().strip_edges()
			found_path = cleaned
	# Return either a filesystem path or zip:path if found
	return found_path

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
		var applied_base_file: String = ""
		# Try shader name first
		var tex_key = sh_name
		if texture_cache["textures"].has(tex_key):
			mat.albedo_texture = texture_cache["textures"][tex_key]
			applied_base_file = tex_key.get_file()
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
		# Fallback to qer_editorimage or first stage map
		if not found_base and shader_data.has(sh_name):
			var base_keys: Array[String] = []
			if shader_data[sh_name].has("qer_editorimage") and String(shader_data[sh_name]["qer_editorimage"]) != "":
				base_keys.append(String(shader_data[sh_name]["qer_editorimage"]).get_file())
			if shader_data[sh_name].has("stages"):
				for stage in shader_data[sh_name]["stages"]:
					if stage.has("map") and stage["map"] and not String(stage["map"]).begins_with("$"):
						base_keys.append(String(stage["map"]).get_file())
			for key in base_keys:
				if texture_cache["textures"].has(key):
					mat.albedo_texture = texture_cache["textures"][key]
					applied_base_file = key
					var img2 = texture_cache["textures"][key].get_image()
					if img2 and img2.detect_alpha() != Image.ALPHA_NONE:
						mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						mat.alpha_scissor_threshold = 0.5
					found_base = true
					if debug_logging:
						print("Applied fallback base texture %s to %s" % [key, sh_name])
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
			# Try to apply simple tcMod transforms from the stage that supplied the base map
			if sh_data.has("stages") and mat.albedo_texture:
				var chosen_stage: Dictionary = {}
				var base_name := applied_base_file
				# Find first suitable stage if name probe fails
				for stage in sh_data["stages"]:
					if stage.has("map") and stage["map"] and not String(stage["map"]).begins_with("$"):
						if chosen_stage.is_empty():
							chosen_stage = stage
						# Prefer exact rel-path match
						if base_name != "" and (String(stage["map"]).get_file() == base_name or String(stage["map"]).ends_with("/" + base_name)):
							chosen_stage = stage
							break
				if not chosen_stage.is_empty() and chosen_stage.has("tcmods"):
					var uv_scale = Vector3(1, 1, 1)
					var uv_offset = Vector3(0, 0, 0)
					for t in chosen_stage["tcmods"]:
						match t["op"]:
							"scale":
								uv_scale.x *= t["sx"]
								uv_scale.y *= t["sy"]
							"scroll":
								# Static preview: ignore time-based scroll; keep offset at 0
								pass
							"transform":
								# Only apply pure scale/translate (no shear/rotate)
								if is_equal_approx(t["b"], 0.0) and is_equal_approx(t["d"], 0.0):
									uv_scale.x *= t["a"]
									uv_scale.y *= t["e"]
									uv_offset.x += t["c"]
									uv_offset.y += t["f"]
							else:
								pass
						_:
							pass
					mat.uv1_scale = uv_scale
					mat.uv1_offset = uv_offset
			if sh_data.has("stages"):
				for stage in sh_data["stages"]:
					if stage.has("blendFunc"):
						var bf = stage["blendFunc"]
						var set_alpha := false
						if typeof(bf) == TYPE_ARRAY and bf.size() >= 2:
							var src = String(bf[0]).to_upper()
							var dst = String(bf[1]).to_upper()
							if src == "GL_SRC_ALPHA" and dst == "GL_ONE_MINUS_SRC_ALPHA":
								mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
								set_alpha = true
						elif typeof(bf) == TYPE_STRING:
							var mode = String(bf).to_lower()
							if mode == "blend":
								mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
								set_alpha = true
							elif mode == "add":
								mat.transparency = BaseMaterial3D.TRANSPARENCY_ADD
								set_alpha = true
						if set_alpha:
							mat.alpha_scissor_threshold = 0.5
							if debug_logging:
								print("Applied blendFunc for %s -> %s" % [sh_name, str(bf)])
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
