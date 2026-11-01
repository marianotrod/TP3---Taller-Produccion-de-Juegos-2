extends Node

# Uso: godot --path . res://pruebas/probe.tscn -- tester=res://pruebas/t_titulo_combate.gd con_titulo

const SALIDA = "C:/mariano/CazadoraInvisible/capturas/"
var fallas = 0

func check(cond, texto):
	print(("OK    " if cond else "FALLA ") + texto)
	if not cond:
		fallas += 1

func enemigo(nombre):
	for n in get_tree().get_nodes_in_group("enemigo"):
		if n.name == nombre:
			return n

func esperar(seg):
	await get_tree().create_timer(seg).timeout

func captura(nombre):
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(SALIDA + nombre + ".png")
	print("captura ", nombre)

func tecla():
	var ev = InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	var suelta = InputEventKey.new()
	suelta.keycode = KEY_SPACE
	suelta.pressed = false
	Input.parse_input_event(suelta)

func _ready():
	while not Navegacion.listo or get_tree().current_scene == null or get_tree().current_scene.name == "Probe":
		await get_tree().process_frame
	Ruido.mostrar_circulos = false
	var mundo = get_tree().current_scene
	var j = get_tree().get_first_node_in_group("jugador")

	# --- 1) Título ---
	var titulo = mundo.get_node_or_null("PantallaTitulo")
	check(titulo != null, "hay pantalla de título")
	await esperar(0.2)
	check(not j.visible and not j.is_physics_processing(), "durante el título la cazadora no está ni se mueve")
	var e1 = enemigo("enemigo")
	var x0 = e1.global_position.x
	await esperar(1.0)
	check(abs(e1.global_position.x - x0) > 20.0, "los guardias ya patrullan durante el título")
	await captura("titulo")
	tecla()
	await esperar(0.5)
	await captura("titulo_saliendo")
	await esperar(1.5)
	check(not is_instance_valid(titulo), "el cartel se fue")
	check(j.visible and j.is_on_floor() and not j.esta_muerto, "la cazadora cayó a la rama y está viva")
	print("   posición final ", j.global_position)
	await captura("titulo_aterrizo")

	# --- 2) Golpes cuerpo a cuerpo de cerca y encima ---
	j.set_physics_process(false)
	var E = e1.Estado
	var g = enemigo("enemigo5")
	var base = g.global_position
	g.set_physics_process(false)
	j.facing_left = false
	j.arma_cuerpo_a_cuerpo = "puño"
	for caso in [["pegado delante", Vector2(12, 0)], ["un poco detrás", Vector2(-15, 0)], ["encima", Vector2(0, -95)], ["al alcance", Vector2(85, 0)]]:
		g.golpes_puno = 0
		g.tiene_gorro = false
		j.global_position = base - caso[1]
		await get_tree().physics_frame
		await get_tree().physics_frame
		j.combo_paso = 1
		j.aplicar_golpe()
		check(g.golpes_puno == 1, "puño alcanza a un guardia " + caso[0])
		g.esta_herido = false
	j.global_position = base - Vector2(200, 0)
	await get_tree().physics_frame
	g.golpes_puno = 0
	j.aplicar_golpe()
	check(g.golpes_puno == 0, "no alcanza a uno a 200 px")

	# Empuje limitado: cuchillo con empuje fuerte
	g.set_physics_process(true)
	g.global_position = base
	g.velocity = Vector2.ZERO
	# Desde la derecha, porque a la derecha de este guardia hay una pared
	j.global_position = base + Vector2(20, 0)
	j.facing_left = true
	g.tiene_gorro = true
	await esperar(0.3)
	j.arma_cuerpo_a_cuerpo = "cuchillo"
	j.combo_paso = 1
	j.aplicar_golpe()
	var max_dist = 0.0
	while g.esta_herido:
		await get_tree().physics_frame
		max_dist = max(max_dist, abs(g.global_position.x - j.global_position.x))
	print("   distancia máxima tras el golpe: %.1f" % max_dist)
	check(max_dist > 50.0 and max_dist <= 72.0, "el golpe lo aleja pero queda al alcance")
	# Un segundo golpe reinicia el aturdimiento (antes lo cortaba el final del primero)
	j.global_position = Vector2(-3000, -3000)
	await esperar(1.0)
	g.recibir_dano(g.global_position.x - 20, "puño")
	await esperar(0.3)
	g.recibir_dano(g.global_position.x - 20, "puño")
	await esperar(0.4)
	check(g.esta_herido, "el segundo golpe reinicia el aturdimiento")
	await esperar(0.3)
	check(not g.esta_herido, "el aturdimiento termina después")
	await esperar(0.5)

	# --- 3) Guardia que descubre a un compañero caído ---
	var a = enemigo("enemigo")
	var b = enemigo("enemigo2")
	b.set_physics_process(true)
	a.volver_a_patrulla()
	a.terminar_vuelta()
	if a.direccion_x != 1:
		a.dar_vuelta()
	# Tramo de piso despejado al principio del nivel (entre la caja y los arbustos)
	a.global_position = Vector2(1180, 959.9)
	a.velocity = Vector2.ZERO
	b.global_position = a.global_position + Vector2(300, 0)
	await get_tree().physics_frame
	b.caer_desmayado()
	var reacciono = false
	for i in range(60):
		await get_tree().physics_frame
		if a.estado_actual == E.AGRESIVO:
			reacciono = true
			break
	check(reacciono, "ve a un compañero desmayado y pasa a alerta")
	check(a.punto_interes != null and a.punto_interes.distance_to(b.global_position) < 5.0, "va a revisar el cuerpo")
	var minima = 99999.0
	for i in range(300):
		await get_tree().physics_frame
		minima = min(minima, a.global_position.distance_to(b.global_position))
	print("   distancia mínima al cuerpo en 5 s: %.0f" % minima)
	check(minima < 80.0, "llegó hasta el cuerpo")

	# Mismo cuerpo, mismo incidente: no vuelve a reaccionar
	a.volver_a_patrulla()
	a.terminar_vuelta()
	a.mirar_hacia(b.global_position.x + 500)
	a.global_position = b.global_position - Vector2(300, 0)
	await esperar(1.0)
	check(a.estado_actual != E.AGRESIVO, "no reacciona de nuevo al mismo desmayo")

	# Lo matan: incidente nuevo, reacciona otra vez
	b.morir_general("danio_cae_al_suelo")
	await esperar(0.6)
	check(a.estado_actual == E.AGRESIVO, "reacciona al verlo muerto (incidente nuevo)")

	# Prioridad: si ve al jugador, el jugador manda
	var c = enemigo("enemigo4")
	var d = enemigo("enemigo3")
	c.volver_a_patrulla()
	c.terminar_vuelta()
	if c.direccion_x != 1:
		c.dar_vuelta()
	d.global_position = c.global_position + Vector2(300, 0)
	d.caer_desmayado()
	# El guardia del cuchillazo pudo haberla matado al recuperarse: se la revive
	j.esta_muerto = false
	j.colision_parado.disabled = false
	j.global_position = c.global_position + Vector2(150, 0)
	j.es_sigilo = false
	await esperar(0.15)
	print("   c: estado ", c.estado_actual, " punto ", c.punto_interes, " jugador ", j.global_position, " cuerpo ", d.global_position, " viendo ", c.viendo_jugador, " c ", c.global_position)
	check(c.estado_actual == E.AGRESIVO and c.punto_interes != null and c.punto_interes.distance_to(j.global_position) < 40.0, "viendo al jugador, su objetivo es el jugador y no el cuerpo")

	print("FALLAS: ", fallas)
	get_tree().quit()
