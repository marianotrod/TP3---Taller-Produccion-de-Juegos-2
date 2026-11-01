extends Node

# Feedback al morir, invulnerabilidad (F3) y salto al tirador (F2).
# Uso (con ventana, para las capturas): godot --path . res://pruebas/probe.tscn -- tester=res://pruebas/t_muerte.gd

const SALIDA = "C:/mariano/CazadoraInvisible/capturas/"
var fallas = 0

func check(cond, texto):
	print(("OK    " if cond else "FALLA ") + texto)
	if not cond:
		fallas += 1

func esperar(seg):
	await get_tree().create_timer(seg, true, false, true).timeout

func captura(nombre):
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(SALIDA + nombre + ".png")
	print("captura ", nombre)

func _ready():
	while not Navegacion.listo or get_tree().current_scene == null or get_tree().current_scene.name == "Probe":
		await get_tree().process_frame
	Ruido.mostrar_circulos = false
	var mundo = get_tree().current_scene
	var j = get_tree().get_first_node_in_group("jugador")

	# F2: salto a cada tirador
	for i in range(3):
		mundo.ir_al_proximo_tirador(j)
		await get_tree().physics_frame
		var cerca = get_tree().get_nodes_in_group("tirador").filter(func(e): return e.global_position.distance_to(j.global_position) < 700)
		check(not cerca.is_empty(), "F2 lleva cerca del tirador %d" % (i + 1))
	await captura("f2_tirador")

	# F3: invulnerable
	j.invulnerable = true
	j.morir("prueba", j.global_position + Vector2(40, 0))
	var t0 = Time.get_ticks_msec()
	var congelado_ms = 0
	var destello_a_300 = 0.0
	while Time.get_ticks_msec() - t0 < 400:
		await get_tree().process_frame
		var ms = Time.get_ticks_msec() - t0
		if Engine.time_scale < 0.2:
			congelado_ms = ms
		var destellos = j.get_children().filter(func(n): return n is CanvasLayer and n.layer == 90)
		if ms >= 300 and destello_a_300 == 0.0 and not destellos.is_empty():
			destello_a_300 = destellos[0].get_child(0).color.a
	print("   congelado %d ms, destello a los 300 ms: %.2f" % [congelado_ms, destello_a_300])
	check(congelado_ms >= 120 and congelado_ms <= 200, "el golpe congela el juego ~150 ms")
	check(destello_a_300 > 0.1, "el destello rojo sigue visible a los 300 ms")
	await captura("golpe_invulnerable")
	await esperar(0.3)
	check(is_equal_approx(Engine.time_scale, 1.0), "después del congelado vuelve la velocidad normal")
	check(not j.esta_muerto, "invulnerable: el golpe no la mata")
	j.invulnerable = false

	# Muerte por bala: una bala de arcabuz disparada hacia ella desde la izquierda
	j.global_position = Vector2(10600, 950)
	j.velocity = Vector2.ZERO
	await esperar(0.3)
	var bala = Node2D.new()
	bala.set_script(preload("res://scripts/bala.gd"))
	bala.direccion = Vector2.RIGHT
	get_tree().current_scene.add_child(bala)
	bala.global_position = j.global_position + Vector2(-300, 0)
	for i in range(120):
		await get_tree().physics_frame
		if j.esta_muerto:
			break
	check(j.esta_muerto, "la bala la mata")
	await esperar(0.08)
	await captura("muerte_bala")
	await esperar(0.5)
	await captura("muerte_bala_despues")
	print("FALLAS: ", fallas)
	get_tree().quit()
