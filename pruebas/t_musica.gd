extends Node

# Música adaptativa, pausa, empujón al morir y puntería libre del tirador.
# Uso: godot --headless --path . res://pruebas/probe.tscn -- tester=res://pruebas/t_musica.gd con_titulo

var fallas = 0

func check(cond, texto):
	print(("OK    " if cond else "FALLA ") + texto)
	if not cond:
		fallas += 1

func esperar(seg):
	var fin = Time.get_ticks_msec() + int(seg * 1000)
	while Time.get_ticks_msec() < fin:
		await get_tree().process_frame

func enemigo(nombre):
	for n in get_tree().get_nodes_in_group("enemigo"):
		if n.name == nombre:
			return n

func tecla(codigo):
	for presionada in [true, false]:
		var ev = InputEventKey.new()
		ev.physical_keycode = codigo
		ev.keycode = codigo
		ev.pressed = presionada
		Input.parse_input_event(ev)
		await get_tree().process_frame

func _ready():
	while not Navegacion.listo or get_tree().current_scene == null or get_tree().current_scene.name == "Probe":
		await get_tree().process_frame
	Ruido.mostrar_circulos = false
	var j = get_tree().get_first_node_in_group("jugador")
	await esperar(0.3)

	# --- Música ---
	check(Musica.actual == "pausa", "título: música de pausa")
	await tecla(KEY_SPACE)
	await esperar(1.5)
	check(Musica.actual == "sigilo", "jugando tranquila: música de sigilo (" + Musica.actual + ")")
	var g = enemigo("enemigo10")
	g.entrar_estado_sospecha(g.global_position + Vector2(200, 0))
	await esperar(0.2)
	check(Musica.actual == "curiosidad", "un guardia sospecha: música de curiosidad")
	g.entrar_estado_alerta()
	await esperar(0.2)
	check(Musica.actual == "alerta", "un guardia en alerta: música de alerta")
	g.volver_a_patrulla()
	g.terminar_vuelta()
	await esperar(1.0)
	check(Musica.actual == "alerta", "la alerta se mantiene un rato después")
	await esperar(3.0)
	check(Musica.actual == "sigilo", "después vuelve al sigilo (" + Musica.actual + ")")
	await esperar(1.5)
	check(Musica.reproductores["sigilo"].volume_db > -9.0 and Musica.reproductores["alerta"].stream_paused, "el fundido terminó y la pista anterior quedó en pausa")

	# --- Pausa ---
	await tecla(KEY_P)
	check(get_tree().paused, "P pausa el juego")
	var x0 = enemigo("enemigo").global_position.x
	await esperar(0.5)
	check(Musica.actual == "pausa", "en pausa: música de pausa")
	check(abs(enemigo("enemigo").global_position.x - x0) < 1.0, "en pausa los guardias no se mueven")
	await tecla(KEY_P)
	check(not get_tree().paused, "P sale de la pausa")
	await esperar(0.5)
	check(abs(enemigo("enemigo").global_position.x - x0) > 5.0, "fuera de pausa los guardias se mueven")

	# --- Tirador: puntería libre ---
	var t = get_tree().get_nodes_in_group("tirador")[0]
	j.global_position = t.global_position + Vector2(300, -137)
	var d = t.direccion_hacia(j)
	var angulo = rad_to_deg(d.angle())
	var resto = fposmod(angulo, 45.0)
	print("   ángulo de tiro: %.1f°" % angulo)
	check(resto > 3.0 and resto < 42.0, "el tirador apunta en ángulo libre, no en múltiplos de 45°")

	# --- Empujón al morir ---
	j.global_position = Vector2(10600, 950)
	j.velocity = Vector2.ZERO
	await esperar(0.5)
	var antes = j.global_position
	j.morir("prueba", antes + Vector2(-30, 0))
	await esperar(0.15)
	check(Engine.time_scale < 0.5, "golpe mortal: cámara lenta")
	await esperar(1.5)
	var despues = j.global_position
	print("   empujón: %.0f px, altura final %.0f (antes %.0f)" % [despues.x - antes.x, despues.y, antes.y])
	check(despues.x - antes.x > 40.0, "el golpe la empuja hacia el lado contrario")
	check(abs(despues.y - antes.y) < 20.0 and j.is_on_floor(), "cae y queda apoyada en el piso")
	check(is_equal_approx(Engine.time_scale, 1.0), "la velocidad vuelve a la normal")
	await esperar(0.5)
	check(Musica.actual == "pausa", "muerta: música de pausa")

	print("FALLAS: ", fallas)
	get_tree().quit()
