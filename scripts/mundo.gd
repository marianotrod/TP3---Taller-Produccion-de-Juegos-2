extends Node2D

# --- ATAJOS DE DEPURACIÓN (solo en versiones de desarrollo, no en la exportada) ---
# F1: círculos de ruido y conos de visión (en ruido.gd)
# F2: lleva a la jugadora cerca del próximo tirador
# F3: invulnerable (los golpes se muestran pero no matan)
# Backspace: muestra/oculta las formas de colisión (como --debug-collisions)

var indice_tirador = -1
var aviso_depuracion: Label = null

var cartel_pausa: CanvasLayer = null

func _ready():
	add_to_group("nivel")
	# La raíz procesa siempre (para poder salir de la pausa); el resto del nivel sí se pausa.
	# Antes los hijos heredaban "siempre" y la pausa no detenía nada.
	for hijo in get_children():
		hacer_pausable(hijo)
	# Lo que se crea durante el juego (flechas, balas, sangre, marcadores) también
	child_entered_tree.connect(hacer_pausable)
	crear_cartel_pausa()

func hacer_pausable(nodo):
	if nodo.process_mode == Node.PROCESS_MODE_INHERIT:
		nodo.process_mode = Node.PROCESS_MODE_PAUSABLE

func _process(_delta):
	if Input.is_action_just_pressed("pausa") and not has_node("PantallaTitulo"):
		get_tree().paused = not get_tree().paused
		cartel_pausa.visible = get_tree().paused

func crear_cartel_pausa():
	cartel_pausa = CanvasLayer.new()
	cartel_pausa.layer = 60
	cartel_pausa.hide()
	var fondo = ColorRect.new()
	fondo.color = Color(0, 0, 0, 0.45)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	cartel_pausa.add_child(fondo)
	var texto = Label.new()
	texto.text = "PAUSA"
	texto.set_anchors_preset(Control.PRESET_FULL_RECT)
	texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	texto.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	texto.add_theme_font_override("font", load("res://fonts/Minecraft.ttf"))
	texto.add_theme_font_size_override("font_size", 72)
	texto.add_theme_color_override("font_outline_color", Color.BLACK)
	texto.add_theme_constant_override("outline_size", 12)
	cartel_pausa.add_child(texto)
	add_child(cartel_pausa)

func _unhandled_input(event):
	if not OS.is_debug_build() or not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	if event.physical_keycode == KEY_BACKSPACE:
		alternar_colisiones_visibles()
		return
	var jugador = get_tree().get_first_node_in_group("jugador")
	if jugador == null or jugador.esta_muerto:
		return
	if event.physical_keycode == KEY_F2:
		ir_al_proximo_tirador(jugador)
	elif event.physical_keycode == KEY_F3:
		jugador.invulnerable = not jugador.invulnerable
		mostrar_aviso("INVULNERABLE (F3)" if jugador.invulnerable else "")

func alternar_colisiones_visibles():
	var visibles = not get_tree().debug_collisions_hint
	get_tree().debug_collisions_hint = visibles
	redibujar_colisiones(get_tree().root, visibles)

func redibujar_colisiones(nodo, visibles):
	# Las formas se dibujan solo al redibujar; los tiles tienen su propio modo de visibilidad
	if nodo is TileMapLayer:
		nodo.collision_visibility_mode = TileMapLayer.DEBUG_VISIBILITY_MODE_FORCE_SHOW if visibles else TileMapLayer.DEBUG_VISIBILITY_MODE_FORCE_HIDE
	elif nodo is CanvasItem:
		nodo.queue_redraw()
	for hijo in nodo.get_children():
		redibujar_colisiones(hijo, visibles)

func ir_al_proximo_tirador(jugador):
	var tiradores = get_tree().get_nodes_in_group("tirador")
	if tiradores.is_empty():
		return
	indice_tirador = (indice_tirador + 1) % tiradores.size()
	var tirador = tiradores[indice_tirador]
	# Un punto del piso a 350-600 px del tirador, sobre su misma superficie si se puede
	var pies_tirador = tirador.global_position + Vector2(0, 64)
	var mejor = null
	for id in Navegacion.nodos_cercanos(pies_tirador, 600.0):
		var punto = Navegacion.nodos[id]
		var distancia = abs(punto.x - pies_tirador.x)
		if distancia < 350.0:
			continue
		if mejor == null or abs(punto.y - pies_tirador.y) < abs(mejor.y - pies_tirador.y):
			mejor = punto
	if mejor == null:
		mejor = pies_tirador + Vector2(-450, 0)
	jugador.global_position = mejor - Vector2(0, 64)
	jugador.velocity = Vector2.ZERO
	jugador.is_hanging = false
	mostrar_aviso("Tirador %d de %d (F2)" % [indice_tirador + 1, tiradores.size()], 2.0)

func mostrar_aviso(texto, duracion = 0.0):
	if aviso_depuracion == null:
		var capa = CanvasLayer.new()
		capa.layer = 95
		add_child(capa)
		aviso_depuracion = Label.new()
		aviso_depuracion.position = Vector2(24, 24)
		aviso_depuracion.add_theme_font_override("font", load("res://fonts/Minecraft.ttf"))
		aviso_depuracion.add_theme_font_size_override("font_size", 28)
		aviso_depuracion.add_theme_color_override("font_outline_color", Color.BLACK)
		aviso_depuracion.add_theme_constant_override("outline_size", 8)
		capa.add_child(aviso_depuracion)
	aviso_depuracion.text = texto
	if duracion > 0.0:
		await get_tree().create_timer(duracion).timeout
		if is_instance_valid(aviso_depuracion) and aviso_depuracion.text == texto:
			var jugador = get_tree().get_first_node_in_group("jugador")
			aviso_depuracion.text = "INVULNERABLE (F3)" if jugador and jugador.invulnerable else ""
