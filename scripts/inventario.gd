extends Node

# Inventario de la cazadora: munición, arma arrojable y objeto cuerpo a cuerpo equipados,
# carrusel de selección y HUD. Es hijo del personaje.
#
# LB (cambiar_arma): arrojables. RB (cambiar_melee): objetos.
# Mantener el bumper abre el carrusel (el tiempo va más lento); un toque alterna con el último elegido.

const ARMAS = ["arco_letal", "arco_desmayante", "distraccion", "humo"]
const OBJETOS = ["puño", "cuchillo"]
const NOMBRES = {
	"arco_letal": "F. Letal", "arco_desmayante": "F. Desmayante",
	"distraccion": "Piedra", "humo": "Humo",
	"puño": "Puño", "cuchillo": "Cuchillo",
}
const MS_TOQUE = 220
const COOLDOWN_DISTRACCION = 1.5
const ESCALA_TIEMPO_CARRUSEL = 0.2

@export var flechas_letales_iniciales = 5
@export var flechas_desmayantes_iniciales = 5
@export var bombas_humo_iniciales = 2

@onready var jugador = get_parent()
@onready var interfaz = $"../Interfaz"
@onready var iconos_flechas = $"../Interfaz/IconosFlechas"
@onready var texto_flecha = $"../Interfaz/TextoFlecha"
@onready var texto_melee = $"../Interfaz/TextoMelee"
@onready var iconos_melee = $"../Interfaz/IconosMelee"

var arma_actual = "arco_letal"
var arma_anterior = "arco_desmayante"
var objeto_actual = "puño"
var objeto_anterior = "cuchillo"
var municion = {}
var cooldown_distraccion = 0.0
var inicio_pulsacion = { "cambiar_arma": -1, "cambiar_melee": -1 }
var carrusel = ""          # "" cerrado, o la acción del bumper que lo abrió
var carrusel_idx = 0
var interfaz_carrusel: Control = null
var icono_arrojable: Sprite2D = null

func _ready():
	municion = {
		"arco_letal": flechas_letales_iniciales,
		"arco_desmayante": flechas_desmayantes_iniciales,
		"humo": bombas_humo_iniciales,
	}
	crear_interfaz()
	actualizar_hud()

func _process(delta):
	if cooldown_distraccion > 0.0:
		cooldown_distraccion -= delta / max(Engine.time_scale, 0.01)
	if not jugador.esta_muerto:
		manejar_entrada()

# --- CONSULTAS ---

func carrusel_abierto():
	return carrusel != ""

func tipo_flecha():
	# "letal" o "desmayante" según el arco equipado
	return arma_actual.trim_prefix("arco_")

func es_arco(nombre = arma_actual):
	return nombre in ["arco_letal", "arco_desmayante"]

# --- USO ---

# Gasta munición (o activa el cooldown de la piedra). Devuelve false si no se puede usar.
func intentar_usar():
	match arma_actual:
		"arco_letal", "arco_desmayante", "humo":
			if municion[arma_actual] <= 0:
				Sonido.reproducir("sin_municion")
				return false
			municion[arma_actual] -= 1
		"distraccion":
			if cooldown_distraccion > 0.0:
				Sonido.reproducir("sin_municion")
				return false
			cooldown_distraccion = COOLDOWN_DISTRACCION
	actualizar_hud()
	return true

func recoger_flechas(tipo, cantidad):
	var clave = "arco_" + tipo
	municion[clave] = municion.get(clave, 0) + cantidad
	Sonido.reproducir("recoger")
	actualizar_hud()

# --- SELECCIÓN ---

func manejar_entrada():
	var ahora = Time.get_ticks_msec()
	for accion in ["cambiar_arma", "cambiar_melee"]:
		if Input.is_action_just_pressed(accion) and carrusel == "":
			inicio_pulsacion[accion] = ahora
		if Input.is_action_pressed(accion) and carrusel == "" and inicio_pulsacion[accion] >= 0 and ahora - inicio_pulsacion[accion] > MS_TOQUE:
			abrir_carrusel(accion)
		if Input.is_action_just_released(accion):
			if carrusel == accion:
				cerrar_carrusel()
			elif inicio_pulsacion[accion] >= 0 and carrusel == "":
				alternar_ultimo(accion)
			inicio_pulsacion[accion] = -1

	if carrusel != "":
		var lista = ARMAS if carrusel == "cambiar_arma" else OBJETOS
		var mover = 0
		if Input.is_action_just_pressed("mover_izq"):
			mover = -1
		elif Input.is_action_just_pressed("mover_der"):
			mover = 1
		if mover != 0:
			carrusel_idx = posmod(carrusel_idx + mover, lista.size())
			Sonido.reproducir("menu_mover")
			dibujar_carrusel()

func abrir_carrusel(accion):
	if not jugador.puede_abrir_carrusel():
		return
	carrusel = accion
	var lista = ARMAS if accion == "cambiar_arma" else OBJETOS
	carrusel_idx = lista.find(arma_actual if accion == "cambiar_arma" else objeto_actual)
	jugador.al_abrir_carrusel()
	Engine.time_scale = ESCALA_TIEMPO_CARRUSEL
	Sonido.reproducir("menu_abrir")
	dibujar_carrusel()
	interfaz_carrusel.show()

func cerrar_carrusel():
	var lista = ARMAS if carrusel == "cambiar_arma" else OBJETOS
	var elegido = lista[carrusel_idx]
	if carrusel == "cambiar_arma":
		equipar_arma(elegido)
	else:
		equipar_objeto(elegido)
	carrusel = ""
	Engine.time_scale = 1.0
	interfaz_carrusel.hide()
	Sonido.reproducir("menu_cerrar")

func cerrar_carrusel_sin_elegir():
	carrusel = ""
	Engine.time_scale = 1.0
	if interfaz_carrusel:
		interfaz_carrusel.hide()

func alternar_ultimo(accion):
	if accion == "cambiar_arma":
		equipar_arma(arma_anterior)
	else:
		equipar_objeto(objeto_anterior)
	Sonido.reproducir("menu_mover")

func equipar_arma(nombre):
	if nombre != arma_actual:
		arma_anterior = arma_actual
		arma_actual = nombre
	actualizar_hud()

func equipar_objeto(nombre):
	if nombre != objeto_actual:
		objeto_anterior = objeto_actual
		objeto_actual = nombre
	actualizar_hud()

# --- HUD ---

func texto_cantidad(nombre):
	if nombre == "distraccion":
		return "∞"
	if municion.has(nombre):
		return "x%d" % municion[nombre]
	return ""

func textura_de(nombre):
	match nombre:
		"arco_letal":
			return iconos_flechas.sprite_frames.get_frame_texture("letal", 0)
		"arco_desmayante":
			return iconos_flechas.sprite_frames.get_frame_texture("desmayante", 0)
		"cuchillo":
			return iconos_melee.sprite_frames.get_frame_texture("cuchillo", 0)
		"puño":
			return iconos_melee.sprite_frames.get_frame_texture("punio", 0)
	return textura_arrojable(nombre)

func textura_arrojable(nombre):
	# Íconos simples dibujados por código para piedra y humo
	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var centro = Vector2(16, 17)
	for x in range(32):
		for y in range(32):
			var d = Vector2(x, y).distance_to(centro)
			if nombre == "humo":
				if d < 9:
					img.set_pixel(x, y, Color(0.2, 0.25, 0.18))
				elif y < 9 and abs(x - 16) < 3 and y > 4:
					img.set_pixel(x, y, Color(0.55, 0.5, 0.35))
				elif d < 14 and (x + y) % 3 == 0:
					img.set_pixel(x, y, Color(0.75, 0.75, 0.72, 0.8))
			else:
				if d < 9:
					var luz = 0.55 if Vector2(x, y).distance_to(centro - Vector2(3, 3)) < 4 else 0.4
					img.set_pixel(x, y, Color(luz, luz * 0.93, luz * 0.85))
	return ImageTexture.create_from_image(img)

func actualizar_hud():
	if es_arco():
		iconos_flechas.show()
		iconos_flechas.play(tipo_flecha())
		if icono_arrojable:
			icono_arrojable.hide()
	else:
		iconos_flechas.hide()
		if icono_arrojable:
			icono_arrojable.texture = textura_arrojable(arma_actual)
			icono_arrojable.show()
	texto_flecha.text = "%s %s" % [NOMBRES[arma_actual], texto_cantidad(arma_actual)]
	texto_melee.text = NOMBRES[objeto_actual]
	iconos_melee.play("cuchillo" if objeto_actual == "cuchillo" else "punio")

func crear_interfaz():
	icono_arrojable = Sprite2D.new()
	icono_arrojable.position = iconos_flechas.position
	icono_arrojable.scale = Vector2(2, 2)
	icono_arrojable.hide()
	interfaz.add_child(icono_arrojable)

	interfaz_carrusel = HBoxContainer.new()
	interfaz_carrusel.add_theme_constant_override("separation", 24)
	interfaz_carrusel.position = Vector2(0, 80)
	interfaz_carrusel.hide()
	interfaz.add_child(interfaz_carrusel)

func dibujar_carrusel():
	for hijo in interfaz_carrusel.get_children():
		hijo.queue_free()
	var lista = ARMAS if carrusel == "cambiar_arma" else OBJETOS
	var fuente = load("res://fonts/Minecraft.ttf")
	for i in range(lista.size()):
		var nombre = lista[i]
		var elegido = i == carrusel_idx
		var caja = PanelContainer.new()
		var estilo = StyleBoxFlat.new()
		estilo.bg_color = Color(0, 0, 0, 0.75 if elegido else 0.5)
		estilo.border_color = Color(1.0, 0.85, 0.3) if elegido else Color(0.5, 0.5, 0.5, 0.6)
		estilo.set_border_width_all(4 if elegido else 2)
		estilo.set_content_margin_all(12)
		caja.add_theme_stylebox_override("panel", estilo)
		var columna = VBoxContainer.new()
		columna.alignment = BoxContainer.ALIGNMENT_CENTER
		var icono = TextureRect.new()
		icono.texture = textura_de(nombre)
		icono.custom_minimum_size = Vector2(96, 96)
		icono.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icono.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icono.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var etiqueta = Label.new()
		etiqueta.text = NOMBRES[nombre] + "\n" + texto_cantidad(nombre)
		etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		etiqueta.add_theme_font_override("font", fuente)
		etiqueta.add_theme_font_size_override("font_size", 24)
		var sin_municion = municion.has(nombre) and municion[nombre] <= 0
		etiqueta.modulate = Color(1, 0.45, 0.4) if sin_municion else Color.WHITE
		columna.add_child(icono)
		columna.add_child(etiqueta)
		caja.add_child(columna)
		interfaz_carrusel.add_child(caja)
	# Centrado horizontal en pantalla
	await get_tree().process_frame
	if is_instance_valid(interfaz_carrusel):
		var ancho_pantalla = get_viewport().get_visible_rect().size.x
		interfaz_carrusel.position.x = (ancho_pantalla - interfaz_carrusel.size.x) * 0.5
