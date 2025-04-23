@tool
extends Control

signal import_bsp

func _ready():
	$Button.pressed.connect(_on_button_pressed)

func _on_button_pressed():
	emit_signal("import_bsp")
