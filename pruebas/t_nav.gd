extends Node

func _ready():
	while not Navegacion.listo or get_tree().current_scene == null or get_tree().current_scene.name == "Probe":
		await get_tree().process_frame
	var nav = Navegacion
	var por_tipo = {}
	for k in nav.aristas:
		var t = nav.aristas[k].tipo
		por_tipo[t] = por_tipo.get(t, 0) + 1
	print("aristas por tipo (0 caminar,1 caer,2 saltar,3 escalera): ", por_tipo)

	# Componentes conexas (no dirigidas)
	var vecinos = {}
	for k in nav.aristas:
		var p = k.split(":")
		var a = int(p[0]); var b = int(p[1])
		vecinos[a] = vecinos.get(a, []) + [b]
		vecinos[b] = vecinos.get(b, []) + [a]
	var visto = {}
	var comps = []
	for i in range(nav.nodos.size()):
		if visto.has(i): continue
		var pila = [i]; visto[i] = true; var miembros = []
		while pila:
			var n = pila.pop_back(); miembros.append(n)
			for v in vecinos.get(n, []):
				if not visto.has(v): visto[v] = true; pila.append(v)
		var minx = INF; var maxx = -INF; var miny = INF; var maxy = -INF
		for m in miembros:
			minx = min(minx, nav.nodos[m].x); maxx = max(maxx, nav.nodos[m].x)
			miny = min(miny, nav.nodos[m].y); maxy = max(maxy, nav.nodos[m].y)
		comps.append([miembros.size(), "x %d..%d y %d..%d" % [minx, maxx, miny, maxy]])
	comps.sort_custom(func(a, b): return a[0] > b[0])
	print("componentes: ", comps.size())
	for c in comps.slice(0, 25):
		print("  ", c)

	# Mapa ASCII: una fila cada 64px de alto, una columna cada 128px
	print("--- mapa (# superficie) x de 0 a 22000, y de -700 a 1100")
	for fila in range(-11, 18):
		var y0 = fila * 64.0
		var linea = ""
		for col in range(0, 172):
			var x0 = col * 128.0
			var ch = " "
			for cc in range(int(x0 / 32), int((x0 + 128) / 32)):
				for id in nav.columnas.get(cc, []):
					if nav.nodos[id].y >= y0 and nav.nodos[id].y < y0 + 64:
						ch = "#"
			linea += ch
		print("%5d|%s" % [y0, linea])

	# Enemigos y escaleras
	for e in get_tree().get_nodes_in_group("enemigo"):
		if e is CharacterBody2D:
			print("enemigo ", e.name, " pos ", e.global_position.round(), " nodo ", Navegacion.nodo_mas_cercano(e.global_position + Vector2(0, 64)))
	get_tree().quit()
