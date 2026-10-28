extends CharacterBody2D

const SPEED_COMBATE = 300.0
const SPEED_SIGILO = 150.0
const SPEED_ACOSTADO = SPEED_SIGILO * 0.75
const SPEED_ARRASTRAR_REHEN = SPEED_SIGILO
const JUMP_VELOCITY = -700.0
var gravity_up = 1800.0
var gravity_down = 2200.0
const DISTANCIA_REHEN = 16

# --- UMBRAL DE DAÑO POR CAÍDA ---
const MAX_VELOCIDAD_CAIDA_SEGURA = 1400.0

# --- RUIDO ---
const INTERVALO_PASOS_COMBATE = 0.32
const INTERVALO_PASOS_SIGILO = 0.5
const VELOCIDAD_ATERRIZAJE_RUIDOSO = 450.0
const VELOCIDAD_CAIDA_FUERTE = 1100.0
const PIES = Vector2(0, 64)
const MARGEN_VACIO = 60.0   # Píxeles debajo del límite inferior de la cámara antes de morir

# --- INVENTARIO ---
# LB (cambiar_arma): arrojables. RB (cambiar_melee): objetos.
# Mantener el bumper abre el carrusel; un toque alterna con el último elegido.
const ARMAS = ["arco_letal", "arco_desmayante", "distraccion", "humo"]
const OBJETOS = ["puño", "cuchillo"]
const NOMBRES = {
	"arco_letal": "F. Letal", "arco_desmayante": "F. Desmayante",
	"distraccion": "Piedra", "humo": "Humo",
	"puño": "Puño", "cuchillo": "Cuchillo",
}
const MS_TOQUE = 220
const COOLDOWN_DISTRACCION = 1.5
const FUERZA_MAX_ARCO = 1500.0
const FUERZA_MAX_ARROJABLE = 950.0
const ESCALA_TIEMPO_CARRUSEL = 0.2

var nivel_ocultamiento = 0
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

@export var flecha_escena: PackedScene
@export var flechas_letales_iniciales = 5
@export var flechas_desmayantes_iniciales = 5
@export var bombas_humo_iniciales = 2

@onready var anim = $AnimatedSprite2D
@onready var colision_parado = $ColisionParado
@onready var colision_sigilo = $ColisionSigilo
@onready var colision_acostado = $ColisionAcostado
@onready var ledge_collider = $LedgeCollider
@onready var wall_check = $WallCheck
@onready var floor_check = $FloorCheck
@onready var top_check = $TopCheck
@onready var hitbox = $Hitbox
@onready var hitbox_shape = $Hitbox/CollisionShape2D
@onready var area_takedown = $AreaTakedown
@onready var popup_acciones = $PopUpAcciones
@onready var linea_trayectoria = $LineaTrayectoria

@onready var iconos_flechas = $Interfaz/IconosFlechas
@onready var texto_flecha = $Interfaz/TextoFlecha
@onready var texto_melee = $Interfaz/TextoMelee
@onready var iconos_melee = $Interfaz/IconosMelee
@onready var punto_disparo = $PuntoDisparo

var pos_inicial_disparo_x = 0.0

var es_sigilo = false
var esta_acostado = false
var facing_left = false
var is_hanging = false
var accion_bloqueante = false
var enemigo_agarrado = null
var esta_muerto = false
var en_zona_interactiva = false

var zona_de_escalera = false
var pos_x_escalera = 0.0
var trepando_escalera = false
const SPEED_TREPAR = 150.0
var ancho_colision_original = 0.0
var pos_x_colision_original = 0.0
var timer_cooldown_escalera = 0.0

var distancia_frente = 15.0
var compensacion_sprite = 0

var is_aiming = false
var fuerza_arco = 50.0
var direccion_tiro = Vector2.RIGHT
var tipo_flecha = "letal"
var arma_cuerpo_a_cuerpo = "puño"
var combo_paso = 0
var ataque_encolado = false

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

var timer_pasos = 0.0
var estaba_en_suelo = true

func _ready():
	Engine.time_scale = 1.0
	colision_parado.shape = colision_parado.shape.duplicate()
	ancho_colision_original = colision_parado.shape.size.x
	pos_x_colision_original = colision_parado.position.x

	hitbox_shape.disabled = true
	popup_acciones.hide()
	anim.animation_finished.connect(_on_animation_finished)
	hitbox.body_entered.connect(_on_hitbox_body_entered)

	colision_parado.disabled = false
	colision_sigilo.disabled = true
	colision_acostado.disabled = true

	pos_inicial_disparo_x = abs(punto_disparo.position.x)

	municion = {
		"arco_letal": flechas_letales_iniciales,
		"arco_desmayante": flechas_desmayantes_iniciales,
		"humo": bombas_humo_iniciales,
	}
	crear_interfaz_inventario()
	actualizar_hud()

func _process(delta):
	if cooldown_distraccion > 0.0:
		cooldown_distraccion -= delta / max(Engine.time_scale, 0.01)
	if not esta_muerto:
		manejar_inventario()

func _physics_process(delta):
	if esta_muerto:
		move_and_slide()
		return

	if carrusel != "":
		# Con el carrusel abierto el personaje no actúa (el tiempo va más lento)
		if not is_on_floor() and not trepando_escalera and not is_hanging:
			velocity.y += gravity_down * delta
		velocity.x = move_toward(velocity.x, 0, SPEED_COMBATE)
		move_and_slide()
		return

	if timer_cooldown_escalera > 0.0:
		timer_cooldown_escalera -= delta

	if zona_de_escalera and not trepando_escalera and not accion_bloqueante and timer_cooldown_escalera <= 0.0:
		if Input.is_action_pressed("arriba") or Input.is_action_pressed("abajo"):
			trepando_escalera = true
			colision_parado.shape.size.x = 8.0
			colision_parado.position.x = 0.0

			set_collision_mask_value(1, false)
			ledge_collider.disabled = true

			global_position.x = pos_x_escalera
			velocity = Vector2.ZERO
			es_sigilo = false
			esta_acostado = false
			is_hanging = false

	if trepando_escalera:
		var direccion_y = Input.get_axis("arriba", "abajo")
		velocity.y = direccion_y * SPEED_TREPAR
		velocity.x = 0

		if direccion_y != 0:
			anim.play("trepa_escalera")
		else:
			anim.play("escalera_idle")

		if Input.is_action_just_pressed("saltar"):
			set_collision_mask_value(1, true)
			var choca_con_bloque = test_move(global_transform, Vector2.ZERO)

			if choca_con_bloque:
				set_collision_mask_value(1, false)
			else:
				trepando_escalera = false
				colision_parado.shape.size.x = ancho_colision_original
				colision_parado.position.x = pos_x_colision_original
				velocity.y = JUMP_VELOCITY * 0.8
				timer_cooldown_escalera = 0.3

		move_and_slide()
		return

	var should_disable_ledge = false
	if not is_hanging:
		should_disable_ledge = floor_check.is_colliding() or velocity.y < 0 or top_check.is_colliding()
	ledge_collider.disabled = should_disable_ledge

	check_ledge_grab()

	var direction = Input.get_axis("mover_izq", "mover_der")

	if Input.is_action_just_pressed("cambiar_postura") and not accion_bloqueante:
		if enemigo_agarrado != null:
			enemigo_agarrado.ser_desmayado()
			popup_acciones.hide()
			ejecutar_accion_bloqueante("desmaya_enemigo")
		else:
			if es_sigilo:
				if not top_check.is_colliding():
					es_sigilo = false
			else:
				es_sigilo = true

	if Input.is_physical_key_pressed(KEY_R):
		get_tree().reload_current_scene()

	var quiere_acostarse = Input.is_action_pressed("abajo") and is_on_floor() and not is_hanging and not accion_bloqueante and enemigo_agarrado == null
	var bloqueado_acostado = esta_acostado and top_check.is_colliding()
	esta_acostado = quiere_acostarse or bloqueado_acostado

	if esta_acostado:
		colision_parado.disabled = true
		colision_sigilo.disabled = true
		colision_acostado.disabled = false
	elif es_sigilo and is_on_floor() and not is_hanging:
		colision_parado.disabled = true
		colision_sigilo.disabled = false
		colision_acostado.disabled = true
	else:
		colision_parado.disabled = false
		colision_sigilo.disabled = true
		colision_acostado.disabled = true

	if Input.is_action_just_pressed("atraer") and is_on_floor() and not is_hanging and not accion_bloqueante and enemigo_agarrado == null:
		ejecutar_accion_bloqueante("atrae_en_posicion_de_sigilo" if es_sigilo else "atrae_en_posicion_de_combate")
		# Golpe que atrae a los enemigos cercanos hacia este punto
		Ruido.emitir(global_position + PIES, "atraer", self)
		Sonido.reproducir("atraer", global_position)

	if Input.is_action_just_pressed("agarre") and not accion_bloqueante:
		if enemigo_agarrado == null:
			var cuerpos = area_takedown.get_overlapping_bodies()
			for cuerpo in cuerpos:
				if cuerpo.is_in_group("enemigo") and cuerpo.is_inside_tree() and cuerpo.has_method("puede_recibir_takedown"):
					if cuerpo.puede_recibir_takedown(global_position.x):
						enemigo_agarrado = cuerpo
						enemigo_agarrado.ser_agarrado()
						#popup_acciones.show()
						es_sigilo = false
						Sonido.reproducir("agarre", global_position)
						ejecutar_accion_bloqueante("agarra_enemigo")
						break
		else:
			# Soltar: el enemigo cae, se recupera enseguida y queda en alerta
			enemigo_agarrado.ser_soltado()
			enemigo_agarrado = null
			#popup_acciones.hide()

	if Input.is_action_just_pressed("atacar") and not is_hanging:
		if enemigo_agarrado != null:
			if not accion_bloqueante:
				enemigo_agarrado.ser_asesinado()
				popup_acciones.hide()
				Ruido.emitir(global_position, "matar_rehen", enemigo_agarrado)
				Sonido.reproducir("cuchillo_matar", global_position)
				ejecutar_accion_bloqueante("mata_enemigo")
		elif not is_aiming:
			manejar_combo_ataque()

	if Input.is_action_pressed("apuntar") and not is_hanging and enemigo_agarrado == null and not accion_bloqueante:
		is_aiming = true
		var vector_apuntado = Input.get_vector("mover_izq", "mover_der", "arriba", "abajo")
		if vector_apuntado != Vector2.ZERO:
			direccion_tiro = vector_apuntado.normalized()
			if direccion_tiro.x < 0:
				facing_left = true
			elif direccion_tiro.x > 0:
				facing_left = false
		else:
			direccion_tiro = Vector2(-1.0 if facing_left else 1.0, 0.0)

		if Input.is_action_pressed("disparar"):
			fuerza_arco += 1200 * delta
			fuerza_arco = clamp(fuerza_arco, 50.0, fuerza_maxima())
			actualizar_trayectoria()
		else:
			if linea_trayectoria.get_point_count() > 0:
				linea_trayectoria.clear_points()

		if Input.is_action_just_released("disparar"):
			usar_arma()
			fuerza_arco = 50.0

	elif Input.is_action_just_released("apuntar") and is_aiming:
		is_aiming = false
		fuerza_arco = 50.0
		if linea_trayectoria.get_point_count() > 0:
			linea_trayectoria.clear_points()

	if facing_left:
		hitbox.position.x = -distancia_frente
		hitbox_shape.position.x = -abs(hitbox_shape.position.x)
		area_takedown.position.x = -distancia_frente
		ledge_collider.position.x = -distancia_frente
		punto_disparo.position.x = -40.0
		wall_check.position.x = -distancia_frente
		wall_check.target_position.x = 0
	else:
		hitbox.position.x = distancia_frente
		hitbox_shape.position.x = abs(hitbox_shape.position.x)
		area_takedown.position.x = distancia_frente
		ledge_collider.position.x = distancia_frente
		punto_disparo.position.x = 40.0
		wall_check.position.x = distancia_frente
		wall_check.target_position.x = 0

	if is_hanging:
		velocity = Vector2.ZERO
		var trepar_hacia_pared = (not facing_left and Input.is_action_just_pressed("mover_der")) or (facing_left and Input.is_action_just_pressed("mover_izq"))
		var soltarse_hacia_atras = (not facing_left and Input.is_action_just_pressed("mover_izq")) or (facing_left and Input.is_action_just_pressed("mover_der"))

		if Input.is_action_just_pressed("arriba") or trepar_hacia_pared:
			is_hanging = false
			ejecutar_accion_bloqueante("trepa")
		elif Input.is_action_just_pressed("abajo") or soltarse_hacia_atras:
			is_hanging = false
			position.y += 2
	else:
		var esta_trepando = (accion_bloqueante and anim.animation == "trepa")

		if not is_aiming and not accion_bloqueante:
			if direction < 0:
				facing_left = false if enemigo_agarrado != null else true
			elif direction > 0:
				facing_left = true if enemigo_agarrado != null else false

		if not is_on_floor():
			if velocity.y < 0:
				velocity.y += gravity_up * delta
			else:
				velocity.y += gravity_down * delta

		var current_speed = SPEED_COMBATE

		if accion_bloqueante or is_aiming:
			current_speed = 0.0
			velocity.x = 0
			if esta_trepando:
				velocity.y = -120
		elif enemigo_agarrado != null:
			current_speed = SPEED_ARRASTRAR_REHEN
		elif esta_acostado:
			current_speed = SPEED_ACOSTADO
		elif es_sigilo:
			current_speed = SPEED_SIGILO

		if direction and not accion_bloqueante and not is_aiming:
			velocity.x = direction * current_speed
		else:
			velocity.x = move_toward(velocity.x, 0, current_speed)

		if Input.is_action_just_pressed("saltar") and enemigo_agarrado != null and not accion_bloqueante:
			arrojar_rehen()
		elif Input.is_action_just_pressed("saltar") and is_on_floor() and not accion_bloqueante and not esta_acostado and not (es_sigilo and top_check.is_colliding()) and not en_zona_interactiva:
			velocity.y = JUMP_VELOCITY
			es_sigilo = false

		if Input.is_action_just_released("saltar") and velocity.y < 0:
			velocity.y *= 0.5

	if enemigo_agarrado != null:
		var offset_x = -DISTANCIA_REHEN if facing_left else DISTANCIA_REHEN
		var offset_y = 10
		enemigo_agarrado.global_position = global_position + Vector2(offset_x, offset_y)
		if enemigo_agarrado.has_method("actualizar_movimiento_agarrado"):
			enemigo_agarrado.actualizar_movimiento_agarrado(direction, facing_left)

	update_animation(direction)
	var velocidad_y_previa = velocity.y

	move_and_slide()

	if is_on_floor() and velocidad_y_previa > MAX_VELOCIDAD_CAIDA_SEGURA:
		morir_por_caida()

	procesar_ruido_movimiento(delta, velocidad_y_previa)

	# Zona de muerte: si cae por debajo del borde inferior de la cámara, muere
	if global_position.y > $Camera2D.limit_bottom + MARGEN_VACIO:
		morir_en_vacio()
		return

	nivel_ocultamiento = 0
	var arbol = get_tree()
	if arbol and arbol.current_scene:
		var mapa = arbol.current_scene.get_node_or_null("TileMapLayer2")
		if mapa:
			var pos_celda = mapa.local_to_map(mapa.to_local(global_position))
			var datos_celda = mapa.get_cell_tile_data(pos_celda)
			if datos_celda:
				nivel_ocultamiento = datos_celda.get_custom_data("tipo_ocultamiento")

# --- RUIDO DE MOVIMIENTO ---

func procesar_ruido_movimiento(delta, velocidad_y_previa):
	var en_suelo = is_on_floor()
	if en_suelo and not estaba_en_suelo and not esta_muerto:
		if velocidad_y_previa > VELOCIDAD_CAIDA_FUERTE:
			Ruido.emitir(global_position + PIES, "caida_fuerte", self)
			Sonido.reproducir("aterrizaje", global_position, 3.0)
		elif velocidad_y_previa > VELOCIDAD_ATERRIZAJE_RUIDOSO:
			Ruido.emitir(global_position + PIES, "aterrizaje", self)
			Sonido.reproducir("aterrizaje", global_position)
	estaba_en_suelo = en_suelo

	# Pasos: en combate hacen ruido; en sigilo, arrastrándose o con rehén son silenciosos
	if en_suelo and abs(velocity.x) > 10.0 and not accion_bloqueante:
		timer_pasos -= delta
		if timer_pasos <= 0.0:
			if es_sigilo or esta_acostado or enemigo_agarrado != null:
				Sonido.reproducir("paso_sigilo", global_position, -14.0)
				timer_pasos = INTERVALO_PASOS_SIGILO
			else:
				Ruido.emitir(global_position + PIES, "paso_combate", self)
				Sonido.reproducir("paso", global_position, -6.0)
				timer_pasos = INTERVALO_PASOS_COMBATE
	else:
		timer_pasos = 0.0

func esta_en_humo():
	for nube in get_tree().get_nodes_in_group("humo"):
		if global_position.distance_to(nube.global_position) < nube.radio * 0.85:
			return true
	return false

# --- ATAQUE ---

func manejar_combo_ataque():
	if combo_paso == 0:
		combo_paso = 1
		ejecutar_accion_bloqueante("combo_" + arma_cuerpo_a_cuerpo + "_1")
		hitbox_shape.disabled = false
		sonido_ataque()
	elif combo_paso == 1 and accion_bloqueante:
		ataque_encolado = true
	elif combo_paso == 2 and accion_bloqueante:
		ataque_encolado = true

func sonido_ataque():
	Ruido.emitir(global_position, "ataque", self)
	Sonido.reproducir("golpe_aire", global_position, -4.0)

func ejecutar_accion_bloqueante(nombre_animacion):
	accion_bloqueante = true
	anim.play(nombre_animacion)

# --- REHÉN ---

func arrojar_rehen():
	var dir = -1.0 if facing_left else 1.0
	# Con rehén, facing_left está invertido respecto a hacia dónde mira el rehén
	if enemigo_agarrado != null:
		dir = sign(enemigo_agarrado.global_position.x - global_position.x)
		if dir == 0:
			dir = 1.0
	enemigo_agarrado.ser_soltado(Vector2(dir * 450.0, -380.0))
	enemigo_agarrado = null
	Ruido.emitir(global_position, "arrojar_rehen", self)
	Sonido.reproducir("arrojar", global_position)
	ejecutar_accion_bloqueante("arroja_algo")

# --- ARMAS ARROJABLES ---

func fuerza_maxima():
	if arma_actual in ["distraccion", "humo"]:
		return FUERZA_MAX_ARROJABLE
	return FUERZA_MAX_ARCO

func usar_arma():
	match arma_actual:
		"arco_letal", "arco_desmayante":
			if municion[arma_actual] <= 0:
				Sonido.reproducir("sin_municion")
				return
			municion[arma_actual] -= 1
			disparar_flecha()
			Sonido.reproducir("arco", global_position)
		"distraccion":
			if cooldown_distraccion > 0.0:
				Sonido.reproducir("sin_municion")
				return
			cooldown_distraccion = COOLDOWN_DISTRACCION
			lanzar_arrojable("distraccion")
		"humo":
			if municion["humo"] <= 0:
				Sonido.reproducir("sin_municion")
				return
			municion["humo"] -= 1
			lanzar_arrojable("humo")
	actualizar_hud()

func actualizar_trayectoria():
	if linea_trayectoria.get_point_count() > 0:
		linea_trayectoria.clear_points()

	var vel_simulada = direccion_tiro * fuerza_arco
	punto_disparo.position.y = 35.0

	var pos_simulada = punto_disparo.position
	linea_trayectoria.add_point(pos_simulada)

	var paso_tiempo = 0.05
	for i in range(30):
		vel_simulada.y += gravity_up * paso_tiempo
		pos_simulada += vel_simulada * paso_tiempo
		linea_trayectoria.add_point(pos_simulada)

func disparar_flecha():
	if flecha_escena:
		var nueva_flecha = flecha_escena.instantiate()
		nueva_flecha.global_position = punto_disparo.global_position
		nueva_flecha.velocity = direccion_tiro * fuerza_arco
		nueva_flecha.tipo = tipo_flecha
		get_parent().add_child(nueva_flecha)

func lanzar_arrojable(tipo):
	var objeto = Node2D.new()
	objeto.set_script(preload("res://scripts/arrojable.gd"))
	objeto.tipo = tipo
	objeto.velocity = direccion_tiro * fuerza_arco
	get_parent().add_child(objeto)
	objeto.global_position = punto_disparo.global_position
	Sonido.reproducir("arrojar", global_position, -4.0)

func recoger_flechas(tipo, cantidad):
	var clave = "arco_" + tipo
	municion[clave] = municion.get(clave, 0) + cantidad
	Sonido.reproducir("recoger")
	actualizar_hud()

# --- INVENTARIO ---

func manejar_inventario():
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
	if accion_bloqueante or enemigo_agarrado != null or trepando_escalera:
		return
	carrusel = accion
	var lista = ARMAS if accion == "cambiar_arma" else OBJETOS
	carrusel_idx = lista.find(arma_actual if accion == "cambiar_arma" else objeto_actual)
	is_aiming = false
	linea_trayectoria.clear_points()
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
	if arma_actual == "arco_letal":
		tipo_flecha = "letal"
	elif arma_actual == "arco_desmayante":
		tipo_flecha = "desmayante"
	actualizar_hud()

func equipar_objeto(nombre):
	if nombre != objeto_actual:
		objeto_anterior = objeto_actual
		objeto_actual = nombre
	arma_cuerpo_a_cuerpo = objeto_actual
	actualizar_hud()

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
	if arma_actual in ["arco_letal", "arco_desmayante"]:
		iconos_flechas.show()
		iconos_flechas.play(tipo_flecha)
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

func crear_interfaz_inventario():
	icono_arrojable = Sprite2D.new()
	icono_arrojable.position = iconos_flechas.position
	icono_arrojable.scale = Vector2(2, 2)
	icono_arrojable.hide()
	$Interfaz.add_child(icono_arrojable)

	interfaz_carrusel = HBoxContainer.new()
	interfaz_carrusel.add_theme_constant_override("separation", 24)
	interfaz_carrusel.position = Vector2(0, 80)
	interfaz_carrusel.hide()
	$Interfaz.add_child(interfaz_carrusel)

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

func check_ledge_grab():
	if not is_hanging and not floor_check.is_colliding() and not accion_bloqueante:
		if wall_check.is_colliding() and (is_on_floor() or abs(velocity.y) < 10.0) and velocity.y >= 0:
			is_hanging = true
			velocity = Vector2.ZERO

func update_animation(direction):
	if esta_muerto:
		return

	anim.flip_h = facing_left
	var offset_base_x = compensacion_sprite if facing_left else 0.0

	if not is_hanging and anim.animation != "trepa":
		anim.offset.y = 0
		anim.offset.x = offset_base_x

	if accion_bloqueante or trepando_escalera:
		return

	if is_hanging:
		anim.offset.y = 5
		anim.offset.x = offset_base_x + (-5.0 if facing_left else 5.0)
		anim.play("trepa")
		anim.pause()
		anim.frame = 0
	elif is_aiming:
		anim.play("prepara_el_arco")
	elif enemigo_agarrado != null:
		if direction != 0:
			anim.play("camina_con_enemigo_agarrado")
		else:
			anim.play("camina_con_enemigo_agarrado")
			anim.pause()
			anim.frame = 0
	elif not is_on_floor():
		if velocity.y < 0:
			anim.play("salta_hacia_arriba")
		else:
			if velocity.y > MAX_VELOCIDAD_CAIDA_SEGURA:
				anim.play("cae_muy_alto")
			else:
				anim.play("cae")
	elif esta_acostado:
		if direction != 0:
			anim.play("arrastra_acostado")
		else:
			anim.play("idle_acostado")
	else:
		if direction != 0:
			if es_sigilo:
				anim.play("camina_sigilo")
			else:
				anim.play("camina_combate")
		else:
			if es_sigilo:
				anim.play("idle_sigilo")
			else:
				anim.play("idle_combate")

func _on_animation_finished():
	var terminada = anim.animation

	if "combo" in terminada:
		hitbox_shape.disabled = true
		if ataque_encolado:
			ataque_encolado = false
			combo_paso += 1
			ejecutar_accion_bloqueante("combo_" + arma_cuerpo_a_cuerpo + "_" + str(combo_paso))
			hitbox_shape.disabled = false
			sonido_ataque()
			return

	if terminada == "mata_enemigo" or terminada == "desmaya_enemigo":
		hitbox_shape.disabled = true
		if enemigo_agarrado != null:
			var es_muerte = (terminada == "mata_enemigo")
			enemigo_agarrado.soltar_cuerpo(es_muerte)
			enemigo_agarrado = null
		accion_bloqueante = false
		return

	if terminada == "trepa":
		var direccion = -1 if anim.flip_h else 1
		var empuje_x = 25 * direccion
		var subida_y = 12
		global_position += Vector2(empuje_x, subida_y)
		anim.offset.x = compensacion_sprite if facing_left else 0.0
		anim.offset.y = 0
		accion_bloqueante = false
		return

	accion_bloqueante = false
	ataque_encolado = false
	combo_paso = 0

func _on_hitbox_body_entered(body):
	if body.is_in_group("enemigo") or body.is_in_group("cazadora"):
		if body.has_method("recibir_dano"):
			# El tercer golpe del combo de puño desmaya
			body.recibir_dano(global_position.x, arma_cuerpo_a_cuerpo, combo_paso >= 3)
			Sonido.reproducir("cuchillo_corte" if arma_cuerpo_a_cuerpo == "cuchillo" else "punetazo", global_position)
		else:
			body.queue_free()

func entrar_zona_escalera(centro_x):
	zona_de_escalera = true
	pos_x_escalera = centro_x

func salir_zona_escalera():
	zona_de_escalera = false
	if trepando_escalera:
		trepando_escalera = false
		colision_parado.shape.size.x = ancho_colision_original
		colision_parado.position.x = pos_x_colision_original

		ledge_collider.set_deferred("disabled", false)
		call_deferred("set_collision_mask_value", 1, true)

		if Input.is_action_pressed("arriba"):
			position.y -= 4

# --- FUNCIONES DE MUERTE CORREGIDAS ---

func morir(razon_muerte: String = "Fuiste neutralizado."):
	if esta_muerto:
		return
	esta_muerto = true
	accion_bloqueante = true
	velocity = Vector2.ZERO
	cerrar_carrusel_por_muerte()
	Sonido.reproducir("muerte_jugador")

	colision_parado.set_deferred("disabled", true)
	colision_sigilo.set_deferred("disabled", true)
	colision_acostado.set_deferred("disabled", true)

	anim.play("aterriza_en_el_piso")
	await anim.animation_finished

	anim.play("aterriza_en_el_piso_danio")
	await anim.animation_finished

	var ui_msg = get_tree().get_first_node_in_group("mensajes_ui")
	if ui_msg:
		ui_msg.mostrar_muerte(razon_muerte)
	else:
		await get_tree().create_timer(1.2).timeout
		get_tree().reload_current_scene()

func morir_por_caida():
	if esta_muerto:
		return
	esta_muerto = true
	accion_bloqueante = true
	velocity = Vector2.ZERO
	cerrar_carrusel_por_muerte()
	Ruido.emitir(global_position + PIES, "caida_fuerte", self)
	Sonido.reproducir("muerte_jugador")

	colision_parado.set_deferred("disabled", true)
	colision_sigilo.set_deferred("disabled", true)
	colision_acostado.set_deferred("disabled", true)

	anim.play("aterriza_en_el_piso_danio")
	await anim.animation_finished

	var ui_msg = get_tree().get_first_node_in_group("mensajes_ui")
	if ui_msg:
		ui_msg.mostrar_muerte("La caída fue demasiado alta.")
	else:
		await get_tree().create_timer(1.2).timeout
		get_tree().reload_current_scene()

func morir_en_vacio():
	if esta_muerto:
		return
	esta_muerto = true
	accion_bloqueante = true
	velocity = Vector2.ZERO
	cerrar_carrusel_por_muerte()
	Sonido.reproducir("muerte_jugador")
	anim.hide()
	if enemigo_agarrado != null:
		enemigo_agarrado.ser_soltado()
		enemigo_agarrado = null
	var ui_msg = get_tree().get_first_node_in_group("mensajes_ui")
	if ui_msg:
		ui_msg.mostrar_muerte("Caíste al vacío.")
	else:
		await get_tree().create_timer(1.0).timeout
		get_tree().reload_current_scene()

func cerrar_carrusel_por_muerte():
	carrusel = ""
	Engine.time_scale = 1.0
	if interfaz_carrusel:
		interfaz_carrusel.hide()
