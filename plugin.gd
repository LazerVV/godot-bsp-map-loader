@tool
extends EditorPlugin

var bsp_loader = preload("res://addons/bsp_loader/bsp_loader.gd").new()
var importer = null
var dock = null
var file_dialog = null

func _enter_tree():
	print("BSP Loader Plugin: Entering tree")
	importer = BSPImportPlugin.new(self)
	add_import_plugin(importer)
	
	# Add dock
	dock = preload("res://addons/bsp_loader/bsp_loader_dock.tscn").instantiate()
	add_control_to_bottom_panel(dock, "BSP Loader")
	
	# Create file dialog
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.filters = PackedStringArray(["*.bsp ; BSP Files"])
	file_dialog.file_selected.connect(_on_file_selected)
	get_editor_interface().get_base_control().add_child(file_dialog)
	
	dock.connect("import_bsp", _on_import_bsp_pressed)

func _exit_tree():
	print("BSP Loader Plugin: Exiting tree")
	if importer:
		remove_import_plugin(importer)
		importer = null
	if dock:
		remove_control_from_bottom_panel(dock)
		dock.queue_free()
		dock = null
	if file_dialog:
		file_dialog.queue_free()
		file_dialog = null

func _on_import_bsp_pressed():
	file_dialog.popup_centered(Vector2i(600, 400))

func _on_file_selected(path: String):
	print("Selected BSP file: ", path)
	var filesystem = get_editor_interface().get_resource_filesystem()
	filesystem.reimport_files([path])

class BSPImportPlugin extends EditorImportPlugin:
	var plugin_ref
	
	func _init(ref):
		plugin_ref = ref
		print("BSPImportPlugin: Initialized")
	
	func _get_importer_name() -> String:
		return "bsp_importer"
	
	func _get_visible_name() -> String:
		return "Quake 3 BSP Importer"
	
	func _get_recognized_extensions() -> PackedStringArray:
		print("BSPImportPlugin: Called _get_recognized_extensions")
		return ["bsp"]
	
	func _get_save_extension() -> String:
		return "tscn"
	
	func _get_resource_type() -> String:
		return "PackedScene"
	
	func _get_preset_count() -> int:
		return 1
	
	func _get_preset_name(preset: int) -> String:
		return "Default"
	
	func _get_import_options(path: String, preset: int) -> Array[Dictionary]:
		print("BSPImportPlugin: Called _get_import_options for path: ", path)
		return []
	
	func _get_priority() -> float:
		print("BSPImportPlugin: Called _get_priority")
		return 1.0
	
	func _get_import_order() -> int:
		print("BSPImportPlugin: Called _get_import_order")
		return 0
	
	func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
		print("BSPImportPlugin: Importing ", source_file)
		var bsp_node = plugin_ref.bsp_loader.load_bsp(source_file)
		if not bsp_node:
			push_error("Failed to load BSP file: ", source_file)
			return ERR_CANT_CREATE
		
		var scene = PackedScene.new()
		var result = scene.pack(bsp_node)
		if result != OK:
			push_error("Failed to pack scene: ", result)
			return result
		
		var save_file = save_path + "." + _get_save_extension()
		result = ResourceSaver.save(scene, save_file)
		if result != OK:
			push_error("Failed to save scene: ", result)
			return result
		
		print("BSPImportPlugin: Successfully imported ", source_file, " to ", save_file)
		return OK
