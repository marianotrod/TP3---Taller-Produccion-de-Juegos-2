extends Node

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

func _ready():
	while not Navegacion.listo or get_tree().current_scene == null or get_tree().current_scene.name == "Probe":
		await get_tree().process_frame
	Ruido.mostrar_circulos = false
	var j = get_tree().get_first_node_in_group("jugador")
	j.set_physics_process(false)
	j.global_position = Vector2(-3000, -3000)
	var E = enemigo("enemigo6").Estado

	# Munición
	check(j.municion["arco_letal"] == 5 and j.municion["arco_desmayante"] == 5, "arranca con 5 flechas de cada tipo")
	j.recoger_flechas("letal", 5)
	check(j.municion["arco_letal"] == 10, "carcaj suma 5 flechas letales")
	j.equipar_arma("arco_desmayante")
	check(j.tipo_flecha == "desmayante", "equipar arco desmayante cambia el tipo de flecha")
	j.fuerza_arco = 600
	j.usar_arma()
	check(j.municion["arco_desmayante"] == 4, "disparar gasta una flecha desmayante")
	j.municion["arco_desmayante"] = 0
	j.usar_arma()
	check(j.municion["arco_desmayante"] == 0, "sin flechas no dispara")
	j.equipar_arma("distraccion")
	j.usar_arma()
	j.usar_arma()
	await get_tree().process_frame
	var piedras = get_tree().current_scene.get_children().filter(func(n): return n.get_script() == preload("res://scripts/arrojable.gd"))
	check(piedras.size() == 1, "piedra tiene cooldown (2 pedidos seguidos = 1 piedra)")
	j.alternar_ultimo("cambiar_arma")
	check(j.arma_actual == "arco_desmayante", "toque en LB alterna con la última arma")
	j.equipar_objeto("cuchillo")
	check(j.arma_cuerpo_a_cuerpo == "cuchillo", "equipar cuchillo")

	# Casco y flechas
	var con_casco = enemigo("enemigo2")
	var sin_casco = enemigo("enemigo")
	check(con_casco.tiene_gorro and not sin_casco.tiene_gorro, "mundo.tscn: enemigo2 con casco, enemigo sin casco")
	con_casco.recibir_flechazo("letal", Vector2(500, 0))
	check(not con_casco.tiene_gorro and con_casco.estado_actual != E.MUERTO, "flecha letal a enemigo con casco: pierde el casco y vive")
	sin_casco.recibir_flechazo("letal", Vector2(500, 0))
	check(sin_casco.estado_actual == E.MUERTO, "flecha letal a enemigo sin casco: muere")
	check(sin_casco.collision_layer == 0 or true, "")
	await esperar(0.1)
	check(sin_casco.collision_layer == 0, "el cadáver ya no recibe flechas ni golpes (capa 0)")

	var e3 = enemigo("enemigo3")   # sin casco
	var e4 = enemigo("enemigo4")   # con casco
	e4.recibir_flechazo("desmayante", Vector2(500, 0))
	check(e4.tiene_gorro and e4.estado_actual == E.SOSPECHANDO, "flecha sedante a enemigo con casco: no lo afecta, sospecha")
	e3.recibir_flechazo("desmayante", Vector2(500, 0))
	check(e3.estado_actual == E.DESMAYADO, "flecha sedante a enemigo sin casco: lo desmaya")

	# Puño: aturde sin quitar vida; el tercer golpe desmaya
	var e5 = enemigo("enemigo5")   # sin casco
	e5.recibir_dano(e5.global_position.x - 40, "puño", false)
	check(e5.vida == 3 and e5.estado_actual == E.AGRESIVO, "golpe de puño: no quita vida y pone en alerta")
	await esperar(1.0)
	e5.recibir_dano(e5.global_position.x - 40, "puño", true)
	check(e5.estado_actual == E.DESMAYADO, "tercer golpe del combo de puño: desmaya")

	# Cuchillo sobre casco: primera agresión solo quita el casco
	var e8 = enemigo("enemigo8")   # con casco
	e8.recibir_dano(e8.global_position.x - 40, "cuchillo", false)
	check(not e8.tiene_gorro and e8.vida == 3, "cuchillo a enemigo con casco: quita el casco sin daño")
	await esperar(1.0)
	e8.recibir_dano(e8.global_position.x - 40, "cuchillo", false)
	check(e8.vida == 2, "segundo cuchillazo quita vida")

	# Rehén soltado: se recupera y queda en alerta (antes quedaba congelado)
	var e6 = enemigo("enemigo6")
	e6.ser_agarrado()
	e6.ser_soltado()
	check(e6.estado_actual == E.DESMAYADO, "rehén soltado cae al piso")
	await esperar(6.0)
	check(e6.estado_actual == E.AGRESIVO, "rehén soltado se levanta en alerta (estado: %s)" % E.keys()[e6.estado_actual])

	# Rehén arrojado: sale despedido
	var e10 = enemigo("enemigo10")
	var x0 = e10.global_position.x
	e10.ser_agarrado()
	e10.ser_soltado(Vector2(450, -380))
	await esperar(0.6)
	check(e10.global_position.x - x0 > 60, "rehén arrojado sale despedido (%d px)" % (e10.global_position.x - x0))

	# Regeneración de vida
	var e12 = enemigo("enemigo12")   # con casco
	e12.tiene_gorro = false
	e12.recibir_dano(e12.global_position.x - 40, "cuchillo", false)
	check(e12.vida == 2, "cuchillo quita 1 de vida")
	await esperar(11.5)
	check(e12.vida == 3, "la vida se regenera después de 10 s sin daño")

	print("FALLAS: ", fallas)
	get_tree().quit()
