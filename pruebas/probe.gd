extends Node

# Escena de prueba: carga mundo.tscn y corre el tester indicado en la línea de comandos
# Uso: godot --headless --path . res://pruebas/probe.tscn -- tester=res://pruebas/t_nav.gd

func _ready():
	var tester_path = "res://pruebas/t_nav.gd"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("tester="):
			tester_path = arg.substr(7)
	var tester = Node.new()
	tester.set_script(load(tester_path))
	get_tree().root.add_child.call_deferred(tester)
	get_tree().change_scene_to_file.call_deferred("res://scenes/mundo.tscn")
