extends Node

# Tirador: sigue apuntando un rato aunque la pierda de vista, y la bala es casi instantánea.
# Uso: godot --headless --path . res://pruebas/probe.tscn -- tester=res://pruebas/t_tirador.gd

var fallas = 0

func check(cond, texto):
	print(("OK    " if cond else "FALLA ") + texto)
	if not cond:
		fallas += 1

func cuadros(n):
	for i in range(n):
		await get_tree().physics_frame

func _ready():
	while not Navegacion.listo or get_tree().current_scene == null or get_tree().current_scene.name == "Probe":
		await get_tree().process_frame
	Ruido.mostrar_circulos = false
	var j = get_tree().get_first_node_in_group("jugador")
	j.invulnerable = true
	var t = get_tree().get_nodes_in_group("tirador")[0]
	var bala_script = preload("res://scripts/bala.gd")

	# La ve y empieza a apuntar
	j.global_position = t.global_position + Vector2(400, 0)
	j.velocity = Vector2.ZERO
	await cuadros(2)
	t.mirar_hacia(j.global_position.x)
	t.entrar_estado_alerta()
	var n = 0
	while t.timer_apuntado < 0.0 and n < 120:
		await cuadros(1)
		n += 1
	check(t.timer_apuntado >= 0.0, "empieza a apuntar")
	await cuadros(15)

	# A mitad del apuntado deja de verla (como si se tapara), sin salir del alcance
	j.set_physics_process(false)
	j.collision_layer = 0
	var reinicio = false
	var bala = null
	for i in range(90):
		await cuadros(1)
		if t.timer_apuntado < 0.0 and t.timer_recarga <= 0.0:
			reinicio = true
		for nodo in get_tree().current_scene.get_children():
			if nodo.get_script() == bala_script:
				bala = nodo
		if bala:
			break
	check(not t.viendo_jugador, "ya no la ve")
	check(not reinicio and bala != null, "aunque la perdió de vista, termina de apuntar y dispara")
	if bala:
		var p0 = bala.global_position
		await cuadros(1)
		if is_instance_valid(bala):
			var v = (bala.global_position - p0).length() * 60.0
			print("   velocidad de la bala: %.0f px/s" % v)
			check(v > 3000.0, "la bala es rapidísima")

	# Si no vuelve a verla después de la memoria, deja de apuntar
	await cuadros(240)
	check(t.timer_apuntado < 0.0, "sin verla, no empieza a apuntar otra vez")
	print("FALLAS: ", fallas)
	get_tree().quit()
