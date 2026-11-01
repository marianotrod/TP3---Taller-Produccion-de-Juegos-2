extends Node

const SALIDA = "C:/mariano/CazadoraInvisible/capturas/"

func captura(nombre):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(SALIDA + nombre + ".png")
	print("captura ", nombre)

func _ready():
	while not Navegacion.listo or get_tree().current_scene == null or get_tree().current_scene.name == "Probe":
		await get_tree().process_frame
	var j = get_tree().get_first_node_in_group("jugador")
	var crt = get_tree().current_scene.get_node_or_null("EfectoCRT")
	if crt:
		crt.hide()

	# 1) Grafo de navegación en la zona de las escaleras
	Navegacion.mostrar_debug = true
	Navegacion._actualizar_dibujo()
	j.global_position = Vector2(13400, 700)
	j.set_physics_process(false)
	for i in range(10):
		await get_tree().process_frame
	await captura("nav_escaleras")
	j.global_position = Vector2(4300, 600)
	for i in range(10):
		await get_tree().process_frame
	await captura("nav_inicio")
	Navegacion.mostrar_debug = false
	Navegacion._actualizar_dibujo()

	# 2) Ruido, humo y carrusel cerca de un guardia
	j.set_physics_process(true)
	j.global_position = Vector2(10500, 900)
	for i in range(20):
		await get_tree().physics_frame
	j.equipar_arma("humo")
	j.direccion_tiro = Vector2(1, -0.5).normalized()
	j.fuerza_arco = 700
	j.usar_arma()
	Ruido.emitir(j.global_position + Vector2(0, 64), "atraer", j)
	await get_tree().create_timer(0.45).timeout
	await captura("humo_ruido")
	j.abrir_carrusel("cambiar_arma")
	await get_tree().create_timer(0.1).timeout
	await captura("carrusel")
	get_tree().quit()
