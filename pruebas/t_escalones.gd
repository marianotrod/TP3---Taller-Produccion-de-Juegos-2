extends Node

# Para cada escalón de ~1 baldosa (128px) verifica que el enemigo pueda subirlo

func _ready():
	while not Navegacion.listo or get_tree().current_scene == null or get_tree().current_scene.name == "Probe":
		await get_tree().process_frame
	var nav = Navegacion
	var total = 0
	var fallan = []
	var vistos = {}
	for c in nav.columnas:
		for id in nav.columnas[c]:
			var p = nav.nodos[id]
			for lado in [-1, 1]:
				for otro in nav.columnas.get(c + lado, []):
					var q = nav.nodos[otro]
					var dy = p.y - q.y
					if dy > 100 and dy < 150:
						var clave = "%d:%d" % [int(q.y), int(q.x / 128)]
						if vistos.has(clave):
							continue
						vistos[clave] = true
						total += 1
						if nav.astar.get_id_path(id, otro).is_empty():
							fallan.append([p, q])
	print("escalones de 1 baldosa: %d, sin ruta para subir: %d" % [total, fallan.size()])
	for f in fallan.slice(0, 15):
		print("   desde ", f[0], " hasta ", f[1])
	get_tree().quit()
