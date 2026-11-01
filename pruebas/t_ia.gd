extends Node

# Cada enemigo oye un ruido en un punto alcanzable y se mide si llega y si vuelve a patrullar

var objetivos = {}
var llegada = {}
var vuelta = {}
var tiempo = 0.0
var enemigos = []

func _ready():
	while not Navegacion.listo or get_tree().current_scene == null or get_tree().current_scene.name == "Probe":
		await get_tree().process_frame
	var jugador = get_tree().get_first_node_in_group("jugador")
	jugador.set_physics_process(false)
	jugador.global_position = Vector2(-3000, -3000)
	Ruido.mostrar_circulos = false
	var semilla = 7
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seed="):
			semilla = int(arg.substr(5))
	seed(semilla)
	for e in get_tree().get_nodes_in_group("enemigo"):
		if not e is CharacterBody2D:
			continue
		var pies = e.global_position + Vector2(0, 64)
		var desde = Navegacion.nodo_mas_cercano(pies)
		var candidatos = []
		for id in range(Navegacion.nodos.size()):
			var n = Navegacion.nodos[id]
			var d = n.distance_to(pies)
			if d > 350 and d < 1300 and abs(n.y - pies.y) > 100:
				var r = Navegacion.astar.get_id_path(desde, id)
				if r.size() > 0:
					candidatos.append(id)
		if candidatos.is_empty():
			print(e.name, ": sin objetivo alcanzable a otra altura")
			continue
		var t = candidatos.pick_random()
		var destino = Navegacion.nodos[t] - Vector2(0, 64)
		objetivos[e] = destino
		enemigos.append(e)
		var ruta = Navegacion.calcular_ruta(pies, Navegacion.nodos[t])
		var tipos = []
		for i in range(ruta.size() - 1):
			tipos.append(["C", "F", "S", "E"][Navegacion.arista(ruta[i], ruta[i + 1]).tipo])
		print("%s desde %s hacia %s ruta %s" % [e.name, e.global_position.round(), destino.round(), "".join(tipos)])
		e.oir_ruido(destino, 0.0)

var traza = {}

func _physics_process(delta):
	if enemigos.is_empty():
		return
	tiempo += delta
	for e in enemigos:
		var tipo = "-"
		if e.ruta.size() >= 2 and e.ruta_idx < e.ruta.size() - 1:
			tipo = ["C", "F", "S", "E"][Navegacion.arista(e.ruta[e.ruta_idx], e.ruta[e.ruta_idx + 1]).tipo]
		var linea = "%s %s arista=%s salto=%s esc=%s suelo=%s" % [e.Estado.keys()[e.estado_actual], e.fase_sospecha, tipo, e.nav_saltando, e.nav_en_escalera, e.is_on_floor()]
		if not traza.has(e) or traza[e][-1][1] != linea:
			traza[e] = traza.get(e, []) + [[snapped(tiempo, 0.1), linea, e.global_position.round()]]
		if not llegada.has(e) and e.global_position.distance_to(objetivos[e]) < 70:
			llegada[e] = tiempo
		if llegada.has(e) and not vuelta.has(e) and e.estado_actual == e.Estado.PATRULLANDO:
			vuelta[e] = tiempo
	if tiempo > 45.0:
		var ok = 0
		for e in enemigos:
			var estado = e.Estado.keys()[e.estado_actual]
			if llegada.has(e):
				ok += 1
			else:
				for t in traza[e].slice(0, 30):
					print("      ", t)
			print("%-10s llego=%s  volvio=%s  estado=%s  pos=%s  dist=%d" % [e.name, str(snapped(llegada.get(e, -1), 0.1)), str(snapped(vuelta.get(e, -1), 0.1)), estado, e.global_position.round(), e.global_position.distance_to(objetivos[e])])
		print("LLEGARON %d / %d" % [ok, enemigos.size()])
		get_tree().quit()
