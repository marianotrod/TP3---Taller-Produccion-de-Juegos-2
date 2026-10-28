extends Node

# --- PATHFINDING DE PLATAFORMAS ---
# Al cargar un nivel se recorre la colisión del mundo (capa 1) columna por columna
# y se arma un grafo de superficies caminables. Las aristas son:
#   CAMINAR: entre columnas vecinas a casi la misma altura
#   CAER:    desde un borde hacia la superficie de abajo
#   SALTAR:  parábola libre de obstáculos (calculada con la física del enemigo)
#   ESCALERA: entre las superficies que conecta cada MarcadorEscalera
# Los enemigos piden rutas con calcular_ruta() y las recorren paso a paso.

enum Tipo { CAMINAR, CAER, SALTAR, ESCALERA }

const PASO = 32.0                # Ancho de columna del muestreo
const PIES = 64.0                # Distancia del origen del enemigo a sus pies
const ALTO_ACTOR = 93.0
const ANCHO_ACTOR = 40.0
const ESCALON_MAX = 20.0         # Desnivel que se sube caminando
const SALTO_ALTURA_MAX = 150.0   # Cuánto puede subir un enemigo de un salto
const SALTO_COLUMNAS_MAX = 8     # Distancia horizontal máxima de un salto (en columnas)
const SALTO_VX_MAX = 330.0
const MARGEN_SALTO = 40.0        # Altura extra sobre el destino en la parábola
const GRAVEDAD_SUBIDA = 1800.0   # Iguales a las del enemigo
const GRAVEDAD_BAJADA = 2200.0
const Y_MIN = -1200.0
const Y_MAX = 1400.0

var nodos: Array[Vector2] = []          # Posición (x, y de la superficie)
var columnas = {}                       # índice de columna -> Array de ids
var aristas = {}                        # "a:b" -> { tipo, vx, vy }
var astar = AStar2D.new()
var listo = false
var escena_construida = null
var dibujo: Node2D = null
var mostrar_debug = false

func _process(_delta):
	var escena = get_tree().current_scene
	if escena != escena_construida:
		listo = false
		escena_construida = escena
		if escena:
			# Esperamos a que la física registre las colisiones del nivel
			await get_tree().physics_frame
			await get_tree().physics_frame
			construir()
	if Input.is_physical_key_pressed(KEY_F2) and not _f2_previo:
		mostrar_debug = not mostrar_debug
		_actualizar_dibujo()
	_f2_previo = Input.is_physical_key_pressed(KEY_F2)

var _f2_previo = false

func reconstruir():
	if escena_construida:
		construir()

func construir():
	var escena = get_tree().current_scene
	if escena == null or not escena is Node2D:
		return
	var espacio = escena.get_world_2d().direct_space_state
	nodos.clear()
	columnas.clear()
	aristas.clear()
	astar.clear()

	var ancho_mundo = _ancho_mundo(escena)
	var total_columnas = int(ancho_mundo / PASO) + 1

	for c in range(total_columnas):
		var x = c * PASO + PASO * 0.5
		columnas[c] = []
		for y in _superficies_en(espacio, x):
			var id = nodos.size()
			nodos.append(Vector2(x, y))
			astar.add_point(id, Vector2(x, y))
			columnas[c].append(id)

	for c in range(total_columnas):
		for id in columnas[c]:
			_conectar_caminar_y_caer(espacio, c, id)
	for c in range(total_columnas):
		for id in columnas[c]:
			_conectar_saltos(espacio, c, id)
	_conectar_escaleras(escena)

	listo = true
	_actualizar_dibujo()
	print("Navegacion: %d nodos, %d aristas" % [nodos.size(), aristas.size()])

func _ancho_mundo(escena):
	var jugador = get_tree().get_first_node_in_group("jugador")
	if jugador and jugador.has_node("Camera2D"):
		var limite = jugador.get_node("Camera2D").limit_right
		if limite < 1000000:
			return float(limite)
	return 22000.0

func _consulta_rayo(desde, hasta):
	var q = PhysicsRayQueryParameters2D.create(desde, hasta, 1)
	q.collide_with_areas = false
	return q

func _es_solido(espacio, punto):
	var q = PhysicsPointQueryParameters2D.new()
	q.position = punto
	q.collision_mask = 1
	q.collide_with_areas = false
	return not espacio.intersect_point(q, 1).is_empty()

func _superficies_en(espacio, x):
	var resultado = []
	var y = Y_MIN
	var vueltas = 0
	while y < Y_MAX and vueltas < 40:
		vueltas += 1
		var choque = espacio.intersect_ray(_consulta_rayo(Vector2(x, y), Vector2(x, Y_MAX)))
		if choque.is_empty():
			break
		var ys = choque.position.y
		if choque.normal.y < -0.5:
			# Hay que tener lugar para el cuerpo arriba de la superficie
			var techo = espacio.intersect_ray(_consulta_rayo(Vector2(x, ys - 2), Vector2(x, ys - ALTO_ACTOR)))
			if techo.is_empty():
				resultado.append(ys)
		# Atravesamos el sólido hasta encontrar aire de nuevo
		y = ys + 4.0
		while y < Y_MAX and _es_solido(espacio, Vector2(x, y)):
			y += 8.0
	return resultado

func _agregar_arista(a, b, tipo, extra = {}):
	var clave = "%d:%d" % [a, b]
	if aristas.has(clave):
		return
	var datos = { "tipo": tipo }
	datos.merge(extra)
	aristas[clave] = datos
	astar.connect_points(a, b, false)

func _paso_libre(espacio, desde_pies, hasta_pies):
	# Rayos a la altura de rodillas y pecho
	for alto in [24.0, 70.0]:
		var choque = espacio.intersect_ray(_consulta_rayo(desde_pies - Vector2(0, alto), hasta_pies - Vector2(0, alto)))
		if not choque.is_empty():
			return false
	return true

func _conectar_caminar_y_caer(espacio, c, id):
	var p = nodos[id]
	for lado in [-1, 1]:
		var vecina = c + lado
		if not columnas.has(vecina):
			continue
		var camino = -1
		for otro in columnas[vecina]:
			if abs(nodos[otro].y - p.y) <= ESCALON_MAX and _paso_libre(espacio, p, nodos[otro]):
				camino = otro
				break
		if camino != -1:
			_agregar_arista(id, camino, Tipo.CAMINAR)
			continue
		# Es un borde: buscamos dónde caeríamos (una o dos columnas más allá)
		for distancia in [1, 2]:
			var col = c + lado * distancia
			if not columnas.has(col):
				break
			var destino = -1
			for otro in columnas[col]:
				if nodos[otro].y > p.y + ESCALON_MAX and (destino == -1 or nodos[otro].y < nodos[destino].y):
					destino = otro
			if destino != -1:
				var borde = Vector2(p.x + lado * PASO * 0.5, p.y)
				if _paso_libre(espacio, p, borde):
					_agregar_arista(id, destino, Tipo.CAER)
				break

func _es_borde(espacio, c, id):
	# Solo se salta desde bordes o frente a paredes, para no llenar el grafo de saltos
	var p = nodos[id]
	for lado in [-1, 1]:
		var tiene_vecino = false
		if columnas.has(c + lado):
			for otro in columnas[c + lado]:
				if aristas.has("%d:%d" % [id, otro]) and aristas["%d:%d" % [id, otro]].tipo == Tipo.CAMINAR:
					tiene_vecino = true
		if not tiene_vecino:
			return true
	return false

func _conectar_saltos(espacio, c, id):
	if not _es_borde(espacio, c, id):
		return
	var p = nodos[id]
	for lado in [-1, 1]:
		for distancia in range(1, SALTO_COLUMNAS_MAX + 1):
			var col = c + lado * distancia
			if not columnas.has(col):
				break
			for otro in columnas[col]:
				var q = nodos[otro]
				var dy = q.y - p.y
				if dy < -SALTO_ALTURA_MAX or dy > 300.0:
					continue
				if abs(dy) <= ESCALON_MAX and distancia == 1:
					continue
				if aristas.has("%d:%d" % [id, otro]):
					continue
				var salto = calcular_salto(p, q)
				if salto.is_empty():
					continue
				if _parabola_libre(espacio, p, salto):
					_agregar_arista(id, otro, Tipo.SALTAR, salto)

func calcular_salto(desde, hasta):
	var dx = hasta.x - desde.x
	var dy = hasta.y - desde.y
	var altura = max(0.0, -dy) + MARGEN_SALTO
	var vy = -sqrt(2.0 * GRAVEDAD_SUBIDA * altura)
	var t_subida = -vy / GRAVEDAD_SUBIDA
	var caida = altura + dy
	if caida < 0:
		return {}
	var t_bajada = sqrt(2.0 * caida / GRAVEDAD_BAJADA)
	var vx = dx / (t_subida + t_bajada)
	if abs(vx) > SALTO_VX_MAX:
		return {}
	return { "vx": vx, "vy": vy, "t": t_subida + t_bajada }

func _parabola_libre(espacio, desde, salto):
	var forma = RectangleShape2D.new()
	forma.size = Vector2(ANCHO_ACTOR, ALTO_ACTOR - 12.0)
	var q = PhysicsShapeQueryParameters2D.new()
	q.shape = forma
	q.collision_mask = 1
	q.collide_with_areas = false
	var t = 0.0
	var pasos = 24
	for i in range(1, pasos):
		t = salto.t * i / pasos
		var pos = desde + Vector2(salto.vx * t, _altura_en(salto.vy, t))
		# Centro del cuerpo, levantado unos píxeles para no tocar el piso de salida/llegada
		q.transform = Transform2D(0, pos - Vector2(0, ALTO_ACTOR * 0.5 + 6.0))
		if not espacio.intersect_shape(q, 1).is_empty():
			return false
	return true

func _altura_en(vy, t):
	var t_subida = -vy / GRAVEDAD_SUBIDA
	if t <= t_subida:
		return vy * t + 0.5 * GRAVEDAD_SUBIDA * t * t
	var apice = vy * t_subida + 0.5 * GRAVEDAD_SUBIDA * t_subida * t_subida
	var tb = t - t_subida
	return apice + 0.5 * GRAVEDAD_BAJADA * tb * tb

func _conectar_escaleras(escena):
	for marcador in _buscar_escaleras(escena):
		var forma = marcador.get_node("CollisionShape2D")
		var alto = forma.shape.size.y * abs(forma.global_scale.y)
		var centro = forma.global_position
		var arriba = centro.y - alto * 0.5
		var abajo = centro.y + alto * 0.5
		var c = int(centro.x / PASO)
		var en_escalera = []
		for col in [c - 1, c, c + 1]:
			if not columnas.has(col):
				continue
			for id in columnas[col]:
				var y = nodos[id].y
				if y >= arriba - 100.0 and y <= abajo + 60.0:
					en_escalera.append(id)
		en_escalera.sort_custom(func(a, b): return nodos[a].y < nodos[b].y)
		# Unimos cada nivel con el siguiente (ignorando nodos al mismo nivel)
		var niveles = []
		for id in en_escalera:
			if niveles.is_empty() or nodos[id].y - nodos[niveles[-1]].y > ESCALON_MAX:
				niveles.append(id)
		for i in range(niveles.size() - 1):
			var datos = { "x": centro.x }
			_agregar_arista(niveles[i], niveles[i + 1], Tipo.ESCALERA, datos)
			_agregar_arista(niveles[i + 1], niveles[i], Tipo.ESCALERA, datos)

func _buscar_escaleras(nodo, lista = []):
	for hijo in nodo.get_children():
		if hijo is Area2D and "orden" in hijo and hijo.orden in [5, 6] and hijo.has_node("CollisionShape2D"):
			lista.append(hijo)
		_buscar_escaleras(hijo, lista)
	return lista

# --- CONSULTAS ---

func nodo_mas_cercano(pies: Vector2, tolerancia_arriba = 40.0):
	if not listo or nodos.is_empty():
		return -1
	var c = int(pies.x / PASO)
	var mejor = -1
	var mejor_distancia = INF
	for col in range(c - 3, c + 4):
		if not columnas.has(col):
			continue
		for id in columnas[col]:
			var n = nodos[id]
			# Preferimos la superficie que está debajo de los pies
			if n.y < pies.y - tolerancia_arriba:
				continue
			var d = abs(n.x - pies.x) + abs(n.y - pies.y) * 1.5
			if d < mejor_distancia:
				mejor_distancia = d
				mejor = id
	return mejor

func calcular_ruta(desde_pies: Vector2, hasta_pies: Vector2) -> Array:
	var a = nodo_mas_cercano(desde_pies)
	var b = nodo_mas_cercano(hasta_pies, 200.0)
	if a == -1 or b == -1:
		return []
	if a == b:
		return [a]
	return Array(astar.get_id_path(a, b))

func arista(a, b):
	return aristas.get("%d:%d" % [a, b], {})

func nodos_cercanos(pies: Vector2, radio: float) -> Array:
	var lista = []
	var c = int(pies.x / PASO)
	var rango = int(radio / PASO) + 1
	for col in range(c - rango, c + rango + 1):
		if columnas.has(col):
			for id in columnas[col]:
				if nodos[id].distance_to(pies) <= radio:
					lista.append(id)
	return lista

# --- DEBUG (F2) ---

func _actualizar_dibujo():
	if dibujo and is_instance_valid(dibujo):
		dibujo.queue_free()
		dibujo = null
	if not mostrar_debug or not listo:
		return
	var escena = get_tree().current_scene
	if escena == null:
		return
	dibujo = Node2D.new()
	dibujo.z_index = 50
	dibujo.set_script(preload("res://scripts/navegacion_debug.gd"))
	escena.add_child(dibujo)
