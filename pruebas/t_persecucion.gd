extends Node

var fallas = 0
var j

func check(cond, texto):
	print(("OK    " if cond else "FALLA ") + texto)
	if not cond:
		fallas += 1

func nodo(nombre):
	return get_tree().current_scene.find_child(nombre, true, false)

func frames(seg):
	for i in range(int(seg * 60)):
		await get_tree().physics_frame

func _ready():
	while not Navegacion.listo or get_tree().current_scene == null or get_tree().current_scene.name == "Probe":
		await get_tree().process_frame
	j = get_tree().get_first_node_in_group("jugador")
	j.set_physics_process(false)
	var nav = Navegacion

	# --- Marcador del último punto visto ---
	var e = nodo("enemigo6")
	j.global_position = e.global_position + Vector2(e.direccion_x * 220, 0)
	await frames(0.3)
	check(e.estado_actual == e.Estado.AGRESIVO, "el guardia la ve y pasa a alerta")
	var visto = j.global_position
	j.global_position = Vector2(-3000, -3000)   # desaparece de su vista
	await frames(0.1)
	var marcador = e.marcador_interes
	check(marcador != null and marcador.global_position.distance_to(visto) < 5, "deja un marcador en el último punto donde la vio")
	await frames(4.0)
	check(e.global_position.distance_to(visto) < 120 or not is_instance_valid(marcador), "va a revisar el marcador")
	check(not is_instance_valid(marcador) or marcador.is_queued_for_deletion(), "al llegar quita el marcador")

	# --- Persecución subiendo escalones de 1 baldosa ---
	var escalones = []
	var vistos = {}
	for c in nav.columnas:
		for id in nav.columnas[c]:
			var p = nav.nodos[id]
			for lado in [-1, 1]:
				for otro in nav.columnas.get(c + lado, []):
					var q = nav.nodos[otro]
					if p.y - q.y > 100 and p.y - q.y < 150 and not vistos.has(int(q.x / 256)):
						# Arranca 5 columnas antes del escalón, en el piso de abajo
						var inicio = -1
						for cand in nav.columnas.get(c - lado * 5, []):
							if abs(nav.nodos[cand].y - p.y) < 10:
								inicio = cand
						if inicio != -1 and not nav.astar.get_id_path(inicio, otro).is_empty():
							vistos[int(q.x / 256)] = true
							escalones.append([inicio, otro])
	escalones.shuffle()
	var alcanzados = 0
	var probados = 0
	for par in escalones.slice(0, 8):
		var cazador = nodo("enemigo7")
		cazador.set_physics_process(true)
		cazador.show()
		cazador.limpiar_ruta()
		cazador.estado_actual = cazador.Estado.PATRULLANDO
		cazador.esta_herido = false
		cazador.global_position = nav.nodos[par[0]] - Vector2(0, 64)
		cazador.velocity = Vector2.ZERO
		j.esta_muerto = false
		j.global_position = nav.nodos[par[1]] - Vector2(0, 64)
		await frames(0.1)
		cazador.punto_interes = j.global_position
		cazador.entrar_estado_alerta()
		var t = 0.0
		while t < 15.0 and not j.esta_muerto:
			await frames(0.1)
			t += 0.1
		probados += 1
		if j.esta_muerto:
			alcanzados += 1
		else:
			print("      no llegó: de ", nav.nodos[par[0]], " a ", nav.nodos[par[1]], " quedó en ", cazador.global_position.round(), " ", cazador.Estado.keys()[cazador.estado_actual])
	check(alcanzados == probados, "el guardia sube escalones para alcanzarla (%d/%d)" % [alcanzados, probados])

	# --- Caer al vacío ---
	j.esta_muerto = false
	j.anim.show()
	j.set_physics_process(true)
	j.global_position = Vector2(4400, 1300)
	await frames(0.2)
	check(j.esta_muerto, "caer debajo de la cámara mata a la jugadora")

	print("FALLAS: ", fallas)
	get_tree().quit()
