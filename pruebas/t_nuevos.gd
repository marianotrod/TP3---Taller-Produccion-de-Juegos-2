extends Node

var fallas = 0
var j

func check(cond, texto):
	print(("OK    " if cond else "FALLA ") + texto)
	if not cond:
		fallas += 1

func nodo(nombre):
	return get_tree().current_scene.find_child(nombre, true, false)

func esperar(seg):
	await get_tree().create_timer(seg).timeout

func _ready():
	while not Navegacion.listo or get_tree().current_scene == null or get_tree().current_scene.name == "Probe":
		await get_tree().process_frame
	Ruido.mostrar_circulos = true
	j = get_tree().get_first_node_in_group("jugador")
	j.set_physics_process(false)
	j.global_position = Vector2(-3000, -3000)
	await esperar(0.2)

	# --- Puño contra enemigo con casco ---
	var e2 = nodo("enemigo2")
	var E = e2.Estado
	check(e2.tiene_gorro, "enemigo2 tiene casco")
	for i in range(3):
		e2.recibir_dano(e2.global_position.x - 40, "puño", false)
		await esperar(0.8)
	check(e2.estado_actual == E.DESMAYADO and not e2.tiene_gorro, "3 golpes de puño desmayan al enemigo con casco (estado %s)" % E.keys()[e2.estado_actual])

	# --- Tirador: demora, cooldown y puntería libre ---
	var t = nodo("tirador1")
	var disparos = []
	var bala_script = preload("res://scripts/bala.gd")
	# Jugador en el aire, a ~22° por encima de la horizontal (detrás de una plataforma: las balas no llegan)
	j.global_position = t.global_position + Vector2(380, -150)
	await get_tree().physics_frame
	t.mirar_hacia(j.global_position.x)
	t.entrar_estado_alerta()
	var inicio = 0.0
	var reloj = 0.0
	var balas_vistas = {}
	while reloj < 7.0:
		await get_tree().physics_frame
		reloj += 1.0 / 60.0
		for n in get_tree().current_scene.get_children():
			if n.get_script() == bala_script and not balas_vistas.has(n):
				balas_vistas[n] = true
				disparos.append([reloj, n.direccion, rad_to_deg((j.global_position + Vector2(0, 10) - t.boca_del_arma()).angle())])
		if j.esta_muerto and not balas_vistas.has("muerte"):
			balas_vistas["muerte"] = true
			print("      murio en t=%.2f jugador=%s" % [reloj, j.global_position])
			for n in get_tree().current_scene.get_children():
				if n.get_script() == bala_script:
					print("        bala en ", n.global_position, " dir ", n.direccion)
				elif n.is_in_group("enemigo") and n is CharacterBody2D and n.global_position.distance_to(j.global_position) < 300:
					print("        enemigo ", n.name, " en ", n.global_position, " estado ", n.Estado.keys()[n.estado_actual])
	print("      disparos: ", disparos)
	check(disparos.size() >= 2, "el tirador dispara varias veces (%d)" % disparos.size())
	if disparos.size() >= 2:
		check(disparos[0][0] >= 0.9, "tarda en disparar el primero (%.2f s)" % disparos[0][0])
		check(disparos[1][0] - disparos[0][0] >= 3.0, "cooldown entre disparos (%.2f s)" % (disparos[1][0] - disparos[0][0]))
		var d = disparos[0][1]
		var ang = rad_to_deg(d.angle())
		var resto = fposmod(ang, 45.0)
		check(resto > 1.0 and resto < 44.0, "dirección libre, no redondeada a 45° (%.1f°)" % ang)
		var esperado = disparos[0][2]
		check(abs(ang - esperado) < 3.0, "el disparo apunta a la jugadora (%.1f° contra %.1f°)" % [ang, esperado])

	# Jugadora en línea horizontal: el disparo la mata
	j.global_position = t.global_position + Vector2(400, 0)
	t.timer_recarga = 0.0
	t.timer_apuntado = -1.0
	reloj = 0.0
	while not j.esta_muerto and reloj < 5.0:
		await get_tree().physics_frame
		reloj += 1.0 / 60.0
	check(j.esta_muerto, "el disparo en línea mata a la jugadora (%.2f s) %s" % [reloj, get_tree().current_scene.get_node("PantallaMensajes/Contenedor/Subtitulo").text])
	check(j.get("ultima_razon") == null or true, "")

	# --- La bala no corta la soga del puente ---
	var puente = nodo("PuenteCaedizo")
	var contrapeso = puente.get_node("Contrapeso")
	var bala = Node2D.new()
	bala.set_script(bala_script)
	bala.direccion = Vector2.RIGHT
	get_tree().current_scene.add_child(bala)
	bala.global_position = contrapeso.global_position - Vector2(300, 0)
	await esperar(0.6)
	check(not puente.puente_caido, "una bala contra el contrapeso no hace caer el puente")
	contrapeso.recibir_flechazo("letal")
	check(puente.puente_caido, "una flecha sí lo hace caer")

	print("FALLAS: ", fallas)
	get_tree().quit()
