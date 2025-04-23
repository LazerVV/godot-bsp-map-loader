class_name BSPTextureLoader
extends RefCounted

var texture_base_paths: Array[String] = [
	"res://assets/textures/",
	"/home/l0rd/STORE/XONOTIC_DATA/textures"
]
var valid_extensions: Array[String] = ["tga", "png", "jpg", "jpeg", "bmp"]
var cached_texture_string: String = ""
var texture_scan_cache: Dictionary = {} # Cache for scanned textures

# Note: The regex matching logic below is complex and tailored to specific texture naming conventions.
# It must not be modified by AI or external tools, as it handles edge cases critical to texture loading.
# The regex is designed to match Quake 3-style texture paths with suffixes (_norm, _glow, etc.) and
# supports both file system and PK3 archives. Any changes risk breaking texture loading for maps.

func load_textures(shaders: Array[Dictionary], faces: Array[Dictionary]) -> Dictionary:
	var texture_dir = "res://assets/textures/"
	DirAccess.make_dir_recursive_absolute(texture_dir)
	
	# Filter shaders used by renderable faces
	var used_shader_indices: Array[int] = []
	for face in faces:
		if face.shader_num >= 0 and face.shader_num < shaders.size():
			if not used_shader_indices.has(face.shader_num):
				used_shader_indices.append(face.shader_num)
	
	var used_shaders: Array[Dictionary] = []
	for idx in used_shader_indices:
		var shader = shaders[idx]
		if shader.name not in BSPCommon.NON_RENDER_SHADERS or shader.name == "common/invisible":
			used_shaders.append(shader)
	
	print("Loading textures for %d used shaders: %s" % [used_shaders.size(), used_shaders.map(func(s): return s.name)])
	
	# Create required folders
	var required_folders: Array[String] = []
	for sh in used_shaders:
		var top_level = sh.name.get_base_dir().split("/")[0]
		if top_level and not required_folders.has(top_level):
			required_folders.append(top_level)
			var folder_path = texture_dir.path_join(top_level)
			DirAccess.make_dir_recursive_absolute(folder_path)
			print("Created folder: %s" % folder_path)
	
	# Scan textures if cache is empty
	var texture_cache = {"files": [], "textures": {}}
	print("REQUIRED FOLDERS: " + str(required_folders))
	if texture_scan_cache.is_empty():
		scan_textures(required_folders)
	
	# Match and copy textures
	var suffixes: Array[String] = ["_norm", "_glow", "_gloss", "_reflect"]
	for sh in used_shaders:
		var shader_name = sh.name
		var matched_textures = match_texture(shader_name, suffixes)
		print("MATCHED TEXTURES: "+str(matched_textures))
		for suffix in matched_textures:
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
						print("Unsupported texture format: %s for %s" % [ext, shader_name])
						continue
					if load_err == OK and not img.is_empty():
						img.save_png(dst)
						texture_cache.textures[shader_name + suffix] = ImageTexture.create_from_image(img)
						print("Extracted and saved texture: %s" % dst)
					else:
						print("Failed to load texture: %s (Error: %d, Empty: %s)" % [matched_textures[suffix], load_err, img.is_empty()])
					zip.close()
				else:
					print("Failed to open PK3: %s (Error: %d)" % [matched_textures[suffix], err])
			else:
				var src = matched_textures[suffix]
				if FileAccess.file_exists(src):
					var img = Image.new()
					var load_err = img.load(src)
					if load_err == OK and not img.is_empty():
						img.save_png(dst)
						texture_cache.textures[shader_name + suffix] = ImageTexture.create_from_image(img)
						print("Loaded and saved texture: %s" % dst)
					else:
						print("Failed to load texture: %s (Error: %d, Empty: %s)" % [src, load_err, img.is_empty()])
				else:
					print("Texture file not found: %s" % src)
	
	return texture_cache

func scan_textures(required_folders: Array[String]) -> void:
	cached_texture_string = ""
	
	var sorted_paths = texture_base_paths.duplicate()
	sorted_paths.sort()
	for base_path in sorted_paths:
		var cache_key = base_path + str(required_folders)
		if texture_scan_cache.has(cache_key):
			cached_texture_string += texture_scan_cache[cache_key]
			continue
		var path_string = ""
		if base_path.ends_with(".pk3"):
			var zip = ZIPReader.new()
			if zip.open(base_path) == OK:
				for file in zip.get_files():
					var ext = file.get_extension().to_lower()
					if valid_extensions.has(ext):
						var rel_path = file
						if path_string != "":
							path_string += "\n"
						path_string += "zip:" + file
				zip.close()
		else:
			var dir = DirAccess.open(base_path)
			if dir:
				dir.list_dir_begin()
				var files := []
				var f = dir.get_next()
				while f != "":
					files.append(f)
					f = dir.get_next()
				dir.list_dir_end()
				files.sort()
				for file_name in files:
					var full_path = base_path.path_join(file_name)
					if not FileAccess.file_exists(full_path):
						if required_folders.has(file_name):
							for file_info in scan_directory(full_path):
								if path_string != "":
									path_string += "\n"
								path_string += file_info.path
					else:
						var ext = file_name.get_extension().to_lower()
						if valid_extensions.has(ext):
							var rel_path = full_path.replace(base_path.get_base_dir(), "").trim_prefix("/")
							if path_string != "":
								path_string += "\n"
							path_string += full_path
		texture_scan_cache[cache_key] = path_string
		cached_texture_string += path_string

func scan_directory(path: String) -> Array:
	var files: Array = []
	var dir = DirAccess.open(path)
	if not dir:
		var global_path = ProjectSettings.globalize_path(path)
		dir = DirAccess.open(global_path)
		if not dir:
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
		
func match_texture(shader_name: String, suffixes: Array[String]) -> Dictionary:
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
		print("SHADER NOT FOUND!!!: (%s): %s" % [shader_name, pattern])
		
	return matched_textures

func create_materials(shaders: Array[Dictionary], texture_cache: Dictionary) -> Dictionary:
	var materials: Dictionary = {}
	if not texture_cache.has("textures"):
		texture_cache["textures"] = {}
	
	for sh in shaders:
		var sh_name = sh.name
		if sh_name in BSPCommon.NON_RENDER_SHADERS and sh_name != "common/invisible":
			if sh_name == "noshader":
				var mat = StandardMaterial3D.new()
				mat.resource_name = sh_name
				mat.albedo_color = Color(0, 0, 0, 0)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				materials[sh_name] = mat
				print("Created transparent material for %s" % sh_name)
			continue
		var mat := StandardMaterial3D.new()
		mat.resource_name = sh_name
		var found_base := false
		var tex_key = sh_name
		if texture_cache.textures.has(tex_key):
			mat.albedo_texture = texture_cache.textures[tex_key]
			found_base = true
			print("Applied texture %s to material %s" % [tex_key, sh_name])
		if not found_base and sh_name == "common/invisible":
			var invisible_path = "res://assets/textures/common/invisible.tga"
			if FileAccess.file_exists(invisible_path):
				var img = Image.load_from_file(invisible_path)
				if img and not img.is_empty():
					mat.albedo_texture = ImageTexture.create_from_image(img)
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
					mat.alpha_threshold = 0.5
					found_base = true
			else:
				mat.albedo_color = Color(0, 0, 0, 0)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if not found_base:
			mat.albedo_color = Color(0, 0, 0, 0)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			print("No texture found for material %s, using transparent material" % sh_name)
		if texture_cache.textures.has(sh_name + "_norm"):
			mat.normal_enabled = true
			mat.normal_texture = texture_cache.textures[sh_name + "_norm"]
			print("Applied normal texture %s to material %s" % [sh_name + "_norm", sh_name])
		if texture_cache.textures.has(sh_name + "_glow"):
			mat.emission_enabled = true
			mat.emission_texture = texture_cache.textures[sh_name + "_glow"]
			mat.emission = Color(1, 1, 1)
			mat.emission_energy = 1.0
			print("Applied emission texture %s to material %s" % [sh_name + "_glow", sh_name])
		if texture_cache.textures.has(sh_name + "_gloss"):
			mat.roughness_texture = texture_cache.textures[sh_name + "_gloss"]
			mat.roughness_texture_channel = StandardMaterial3D.TEXTURE_CHANNEL_RED
			print("Applied gloss texture %s to material %s" % [sh_name + "_gloss", sh_name])
		if texture_cache.textures.has(sh_name + "_reflect"):
			mat.metallic = 1.0
			mat.metallic_texture = texture_cache.textures[sh_name + "_reflect"]
			mat.metallic_texture_channel = StandardMaterial3D.TEXTURE_CHANNEL_RED
			print("Applied reflect texture %s to material %s" % [sh_name + "_reflect", sh_name])
		materials[sh_name] = mat
	
	return materials

static func escape_regex(s: String) -> String:
	var special_chars = ".^$*+?()[]{}|"
	var escaped = ""
	for c in s:
		if special_chars.contains(c):
			escaped += "\\" + c
		else:
			escaped += c
	return escaped
