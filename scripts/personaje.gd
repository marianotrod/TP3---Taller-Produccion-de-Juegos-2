extends CharacterBody2D

const SPEED_COMBATE = 300.0
const SPEED_SIGILO = 150.0
const SPEED_ACOSTADO = SPEED_SIGILO * 0.75
const SPEED_ARRASTRAR_REHEN = SPEED_SIGILO
const SPEED_TREPAR = 150.0
const JUMP_VELOCITY = -700.0
var gravity_up = 1800.0
var gravity_down = 2200.0
const DISTANCIA_REHEN = 16

# --- UMBRAL DE DAÑO POR CAÍDA ---
const MAX_VELOCIDAD_CAIDA_SEGURA = 1400.0

# --- RUIDO ---
const INTERVALO_PASOS_COMBATE = 0.32
const INTERVALO_PASOS_SIGILO = 0.5
const ALTURA_CAIDA_SILENCIOSA = 48.0   # Caídas más cortas (escalones, agarrarse de una cornisa) no hacen ruido
const RADIO_MAX_ATERRIZAJE = 520.0     # El radio del ruido crece con la altura caída hasta este tope
const ALTURA_CAIDA_FUERTE = 400.0      # Desde esta altura suena más fuerte
const PIES = Vector2(0, 64)
const MARGEN_VACIO = 60.0   # Píxeles debajo del límite inferior de la cámara antes de morir

# --- ARMAS ---
const FUERZA_MAX_ARCO = 1500.0
const FUERZA_MAX_ARROJABLE = 950.0
const FUERZA_MIN = 50.0
const CARGA_POR_SEGUNDO = 1200.0

# --- GOLPE CUERPO A CUERPO ---
# Zona de golpe: desde apenas detrás del cuerpo hasta el alcance del brazo, y en altura
# desde arriba de la cabeza hasta los pies, para pegarle también a un guardia pegado o encima.
const ZONA_GOLPE_DESDE = Vector2(-5, -100)
const ZONA_GOLPE_HASTA = Vector2(70, 50)
# Zona del golpe que cuenta como pegarle a una pared (no incluye el piso)
const ZONA_PARED_DESDE = Vector2(30, -60)
const ZONA_PARED_HASTA = Vector2(70, 30)

# --- CORNISAS ---
const VELOCIDAD_TREPAR_CORNISA = 120.0
const RAPIDEZ_TREPADA_RAPIDA = 2.0   # Con saltar sube al doble de velocidad, pero hace ruido
const TIEMPO_SIN_AGARRE = 0.35       # Después de soltarse no se vuelve a agarrar enseguida

# EXPERIMENTAL: carrera corta por la pared. Al saltar contra una pared y seguir empujando
# hacia ella, cerca de la cima del salto sube un tramo más. No mide la pared: con estos números
# alcanza a colgarse de bordes de hasta ~2 tiles; si la pared es más alta, no llega y cae.
# Para desactivarla: false.
const WALL_RUN = true
const VELOCIDAD_WALL_RUN = 350.0
const DURACION_WALL_RUN = 0.2
const VELOCIDAD_Y_INICIO_WALL_RUN = -250.0   # Arranca cerca de la cima del salto, no subiendo rápido

# --- GOLPE MORTAL (feedback) ---
const PAUSA_IMPACTO = 0.15        # Segundos reales en que el juego casi se congela al recibir el golpe
const CONGELADO_MORTAL = 0.08     # Golpe mortal: congelado corto y después cámara lenta que se recupera
const CAMARA_LENTA_MORTAL = 0.7   # Segundos reales hasta volver a la velocidad normal
const EMPUJE_MUERTE = Vector2(300, -300)   # El golpe mortal la empuja hacia el lado contrario
const FRENADO_MUERTE = 1600.0
const ZOOM_MUERTE = 1.15
const ESCENA_SANGRE = preload("res://scenes/efecto_sangre.tscn")

const Mapa = preload("res://scripts/mapa.gd")

var nivel_ocultamiento = 0

@export var flecha_escena: PackedScene

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
@onready var punto_disparo = $PuntoDisparo
@onready var inventario = $Inventario

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
var ancho_colision_original = 0.0
var pos_x_colision_original = 0.0
var timer_cooldown_escalera = 0.0

var distancia_frente = 15.0
var compensacion_sprite = 0

var is_aiming = false
var fuerza_arco = FUERZA_MIN
var direccion_tiro = Vector2.RIGHT
var combo_paso = 0
var ataque_encolado = false

var timer_pasos = 0.0
var estaba_en_suelo = true
var punto_mas_alto_en_aire = 0.0

var timer_sin_agarre = 0.0
var posicion_tras_movimiento = Vector2.INF   # Para no usar choques viejos después de un teletransporte
var wall_run_disponible = false   # Se habilita al saltar y se gasta al usarla o al aterrizar
var timer_wall_run = 0.0
var wall_run_ruidosa = false      # El ruido sale a mitad de la carrera (un roce corto contra un escalón no suena)

var invulnerable = false          # Depuración (F3 en mundo.gd): los golpes se muestran pero no matan
var ultimo_golpe_ms = -100000
var azar_efectos = RandomNumberGenerator.new()   # Propio, para no alterar el azar de la IA

func _ready():
	Engine.time_scale = 1.0
	colision_parado.shape = colision_parado.shape.duplicate()
	ancho_colision_original = colision_parado.shape.size.x
	pos_x_colision_original = colision_parado.position.x

	hitbox_shape.disabled = true   # El golpe usa una consulta directa (aplicar_golpe); el área queda de referencia
	popup_acciones.hide()
	anim.animation_finished.connect(_on_animation_finished)

	colision_parado.disabled = false
	colision_sigilo.disabled = true
	colision_acostado.disabled = true

# --- CICLO PRINCIPAL ---
# Cada paso se ejecuta en este orden; varios dependen de lo que dejó el anterior.

func _physics_process(delta):
	if esta_muerto:
		if not anim.visible:
			return   # Cayó al vacío
		# Muerta sigue la física: vuela por el empujón del golpe y frena en el piso
		if not is_on_floor():
			velocity.y += gravity_down * delta
		else:
			velocity.x = move_toward(velocity.x, 0, FRENADO_MUERTE * delta)
		move_and_slide()
		return

	if inventario.carrusel_abierto():
		quieta_con_carrusel(delta)
		return

	if timer_cooldown_escalera > 0.0:
		timer_cooldown_escalera -= delta
	intentar_tomar_escalera()
	if trepando_escalera:
		mover_en_escalera()
		return

	actualizar_agarre_de_cornisa(delta)
	var direction = Input.get_axis("mover_izq", "mover_der")

	procesar_cambio_de_postura()
	if Input.is_physical_key_pressed(KEY_R):
		get_tree().reload_current_scene()
	actualizar_acostada_y_colision()

	procesar_atraer()
	procesar_agarre()
	procesar_ataque()
	procesar_apuntado(delta)
	orientar_puntos_de_accion()

	if is_hanging:
		procesar_colgada()
	else:
		procesar_movimiento(delta, direction)

	arrastrar_rehen(direction)
	update_animation(direction)

	var velocidad_y_previa = velocity.y
	move_and_slide()
	posicion_tras_movimiento = global_position

	if is_on_floor() and velocidad_y_previa > MAX_VELOCIDAD_CAIDA_SEGURA:
		morir_por_caida()
	procesar_ruido_movimiento(delta, velocidad_y_previa)

	# Zona de muerte: si cae por debajo del borde inferior de la cámara, muere
	if global_position.y > $Camera2D.limit_bottom + MARGEN_VACIO:
		morir_en_vacio()
		return

	nivel_ocultamiento = Mapa.ocultamiento_en(self, global_position)

func quieta_con_carrusel(delta):
	# Con el carrusel abierto el personaje no actúa (el tiempo va más lento)
	if not is_on_floor() and not trepando_escalera and not is_hanging:
		velocity.y += gravity_down * delta
	velocity.x = move_toward(velocity.x, 0, SPEED_COMBATE)
	move_and_slide()

# --- ESCALERA ---

func intentar_tomar_escalera():
	if not zona_de_escalera or trepando_escalera or accion_bloqueante or timer_cooldown_escalera > 0.0:
		return
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

func mover_en_escalera():
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
			restaurar_colision_parado()
			velocity.y = JUMP_VELOCITY * 0.8
			timer_cooldown_escalera = 0.3

	move_and_slide()

func restaurar_colision_parado():
	colision_parado.shape.size.x = ancho_colision_original
	colision_parado.position.x = pos_x_colision_original

func entrar_zona_escalera(centro_x):
	zona_de_escalera = true
	pos_x_escalera = centro_x

func salir_zona_escalera():
	zona_de_escalera = false
	if trepando_escalera:
		trepando_escalera = false
		restaurar_colision_parado()

		ledge_collider.set_deferred("disabled", false)
		call_deferred("set_collision_mask_value", 1, true)

		if Input.is_action_pressed("arriba"):
			position.y -= 4

# --- CORNISAS ---

func actualizar_agarre_de_cornisa(delta):
	timer_sin_agarre -= delta
	var should_disable_ledge = false
	if not is_hanging:
		should_disable_ledge = floor_check.is_colliding() or velocity.y < 0 or top_check.is_colliding() or timer_sin_agarre > 0.0
	ledge_collider.disabled = should_disable_ledge
	check_ledge_grab()

func check_ledge_grab():
	if not is_hanging and not floor_check.is_colliding() and not accion_bloqueante and timer_sin_agarre <= 0.0:
		# Solo si el LedgeCollider quedó apoyado sobre un borde. Antes alcanzaba con estar quieta en el
		# aire junto a una pared (la cima de cualquier salto) y se colgaba de una pared lisa.
		# No se pide WallCheck: en las ramas finas no las alcanza y se quedaba parada en el aire,
		# sostenida por el LedgeCollider. Si ese sensor se apoya en algo, es un borde delante.
		if apoyada_en_cornisa() and velocity.y >= 0:
			is_hanging = true
			timer_wall_run = 0.0
			velocity = Vector2.ZERO

func procesar_colgada():
	# Arriba o hacia la pared: trepa en silencio. Saltar: trepa rápido, con ruido.
	# B (cambiar postura) o abajo: se suelta. Hacia atrás no hace nada.
	velocity = Vector2.ZERO
	var hacia_pared = Input.is_action_pressed("mover_izq" if facing_left else "mover_der")
	if Input.is_action_just_pressed("saltar"):
		trepar_cornisa(true)
	elif Input.is_action_pressed("arriba") or hacia_pared:
		trepar_cornisa(false)
	elif Input.is_action_just_pressed("cambiar_postura") or Input.is_action_just_pressed("abajo"):
		soltar_cornisa()

func trepar_cornisa(rapido):
	is_hanging = false
	ejecutar_accion_bloqueante("trepa")
	if rapido:
		anim.speed_scale = RAPIDEZ_TREPADA_RAPIDA
		Ruido.emitir(global_position + PIES, "trepada_rapida", self)
		Sonido.reproducir("paso", global_position, -2.0)

func soltar_cornisa():
	is_hanging = false
	timer_sin_agarre = TIEMPO_SIN_AGARRE
	ledge_collider.disabled = true
	position.y += 2

# --- POSTURA ---

func procesar_cambio_de_postura():
	if not Input.is_action_just_pressed("cambiar_postura") or accion_bloqueante or is_hanging:
		return   # Colgada, B la suelta de la cornisa (procesar_colgada)
	if enemigo_agarrado != null:
		enemigo_agarrado.ser_desmayado()
		popup_acciones.hide()
		ejecutar_accion_bloqueante("desmaya_enemigo")
	elif es_sigilo:
		if not top_check.is_colliding():
			es_sigilo = false
	else:
		es_sigilo = true

func actualizar_acostada_y_colision():
	var quiere_acostarse = Input.is_action_pressed("abajo") and is_on_floor() and not is_hanging and not accion_bloqueante and enemigo_agarrado == null
	var bloqueado_acostado = esta_acostado and top_check.is_colliding()
	esta_acostado = quiere_acostarse or bloqueado_acostado

	if esta_acostado:
		usar_colision(colision_acostado)
	elif es_sigilo and is_on_floor() and not is_hanging:
		usar_colision(colision_sigilo)
	else:
		usar_colision(colision_parado)

func usar_colision(activa):
	for forma in [colision_parado, colision_sigilo, colision_acostado]:
		forma.disabled = forma != activa

# --- MOVIMIENTO ---

func procesar_movimiento(delta, direction):
	var esta_trepando = (accion_bloqueante and anim.animation == "trepa")

	if not is_aiming and not accion_bloqueante:
		# Con rehén camina de espaldas: mira hacia el lado contrario al que se mueve
		if direction < 0:
			facing_left = enemigo_agarrado == null
		elif direction > 0:
			facing_left = enemigo_agarrado != null

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
			velocity.y = -VELOCIDAD_TREPAR_CORNISA * anim.speed_scale
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
	elif Input.is_action_just_pressed("saltar") and puede_saltar():
		velocity.y = JUMP_VELOCITY
		es_sigilo = false
		wall_run_disponible = true

	if Input.is_action_just_released("saltar") and velocity.y < 0 and timer_wall_run <= 0.0:
		velocity.y *= 0.5

	if WALL_RUN:
		procesar_wall_run(delta, direction)

func procesar_wall_run(delta, direction):
	var empuja_pared = is_on_wall() and direction != 0 and sign(direction) == -sign(get_wall_normal().x)
	if timer_wall_run > 0.0:
		timer_wall_run -= delta
		if empuja_pared and not accion_bloqueante:
			velocity.y = -VELOCIDAD_WALL_RUN
			if not wall_run_ruidosa and timer_wall_run < DURACION_WALL_RUN * 0.5:
				wall_run_ruidosa = true
				Ruido.emitir(global_position + PIES, "wall_run", self)
				Sonido.reproducir("paso", global_position, -4.0)
		else:
			timer_wall_run = 0.0
		return
	if wall_run_disponible and empuja_pared and not is_on_floor() and velocity.y > VELOCIDAD_Y_INICIO_WALL_RUN and velocity.y < 150.0 \
			and not accion_bloqueante and not is_aiming and enemigo_agarrado == null:
		wall_run_disponible = false
		wall_run_ruidosa = false
		timer_wall_run = DURACION_WALL_RUN
		velocity.y = -VELOCIDAD_WALL_RUN

func puede_saltar():
	return is_on_floor() and not accion_bloqueante and not esta_acostado and not (es_sigilo and top_check.is_colliding()) and not en_zona_interactiva

func orientar_puntos_de_accion():
	# Área de agarre, cornisa, punto de disparo y chequeo de pared van del lado al que mira
	var lado = -1.0 if facing_left else 1.0
	hitbox.position.x = distancia_frente * lado
	area_takedown.position.x = distancia_frente * lado
	ledge_collider.position.x = distancia_frente * lado
	punto_disparo.position.x = 40.0 * lado
	wall_check.position.x = distancia_frente * lado
	wall_check.target_position.x = 0

# --- RUIDO DE MOVIMIENTO ---

func procesar_ruido_movimiento(delta, velocidad_y_previa):
	var en_suelo = is_on_floor()
	if not en_suelo:
		if estaba_en_suelo:
			punto_mas_alto_en_aire = global_position.y
		punto_mas_alto_en_aire = min(punto_mas_alto_en_aire, global_position.y)
	elif not estaba_en_suelo and not esta_muerto:
		wall_run_disponible = false
		if not apoyada_en_cornisa():
			ruido_de_aterrizaje(global_position.y - punto_mas_alto_en_aire)
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

func ruido_de_aterrizaje(altura):
	# El círculo crece con la altura desde la que cayó: un tile (128 px) da uno chico
	if altura < ALTURA_CAIDA_SILENCIOSA:
		return
	var radio = min(altura + 30.0, RADIO_MAX_ATERRIZAJE)
	Ruido.emitir(global_position + PIES, radio, self)
	Sonido.reproducir("aterrizaje", global_position, 3.0 if altura >= ALTURA_CAIDA_FUERTE else lerp(-10.0, 0.0, altura / ALTURA_CAIDA_FUERTE))

func apoyada_en_cornisa():
	# Al agarrarse de una cornisa queda "en el piso" sobre el LedgeCollider: eso no es aterrizar
	# Solo si se apoya desde arriba: de costado contra una pared lisa no es un borde
	if global_position != posicion_tras_movimiento:
		return false   # La movieron (F2, pruebas): los choques del último movimiento ya no valen
	for i in range(get_slide_collision_count()):
		var choque = get_slide_collision(i)
		if choque.get_local_shape() == ledge_collider and choque.get_normal().y < -0.7:
			return true
	return false

func esta_en_humo():
	for nube in get_tree().get_nodes_in_group("humo"):
		if global_position.distance_to(nube.global_position) < nube.radio * 0.85:
			return true
	return false

# --- ATRAER ---

func procesar_atraer():
	if Input.is_action_just_pressed("atraer") and is_on_floor() and not is_hanging and not accion_bloqueante and enemigo_agarrado == null:
		ejecutar_accion_bloqueante("atrae_en_posicion_de_sigilo" if es_sigilo else "atrae_en_posicion_de_combate")
		# Golpe que atrae a los enemigos cercanos hacia este punto
		Ruido.emitir(global_position + PIES, "atraer", self)
		Sonido.reproducir("atraer", global_position)

# --- REHÉN ---

func procesar_agarre():
	if not Input.is_action_just_pressed("agarre") or accion_bloqueante:
		return
	if enemigo_agarrado == null:
		for cuerpo in area_takedown.get_overlapping_bodies():
			if cuerpo.is_in_group("enemigo") and cuerpo.is_inside_tree() and cuerpo.has_method("puede_recibir_takedown"):
				if cuerpo.puede_recibir_takedown(global_position.x):
					enemigo_agarrado = cuerpo
					enemigo_agarrado.ser_agarrado()
					es_sigilo = false
					Sonido.reproducir("agarre", global_position)
					ejecutar_accion_bloqueante("agarra_enemigo")
					break
	else:
		# Soltar: el enemigo cae, se recupera enseguida y queda en alerta
		enemigo_agarrado.ser_soltado()
		enemigo_agarrado = null

func arrastrar_rehen(direction):
	if enemigo_agarrado == null:
		return
	var offset_x = -DISTANCIA_REHEN if facing_left else DISTANCIA_REHEN
	var offset_y = 10
	enemigo_agarrado.global_position = global_position + Vector2(offset_x, offset_y)
	if enemigo_agarrado.has_method("actualizar_movimiento_agarrado"):
		enemigo_agarrado.actualizar_movimiento_agarrado(direction, facing_left)

func arrojar_rehen():
	# Con rehén, facing_left está invertido respecto a hacia dónde mira el rehén
	var dir = sign(enemigo_agarrado.global_position.x - global_position.x)
	if dir == 0:
		dir = 1.0
	enemigo_agarrado.ser_soltado(Vector2(dir * 450.0, -380.0))
	enemigo_agarrado = null
	Ruido.emitir(global_position, "arrojar_rehen", self)
	Sonido.reproducir("arrojar", global_position)
	ejecutar_accion_bloqueante("arroja_algo")

# --- ATAQUE CUERPO A CUERPO ---

func procesar_ataque():
	if not Input.is_action_just_pressed("atacar") or is_hanging:
		return
	if enemigo_agarrado != null:
		if not accion_bloqueante:
			enemigo_agarrado.ser_asesinado()
			popup_acciones.hide()
			Ruido.emitir(global_position, "matar_rehen", enemigo_agarrado)
			Sonido.reproducir("cuchillo_matar", global_position)
			ejecutar_accion_bloqueante("mata_enemigo")
	elif not is_aiming:
		manejar_combo_ataque()

func manejar_combo_ataque():
	if combo_paso == 0:
		iniciar_golpe(1)
	elif combo_paso in [1, 2] and accion_bloqueante:
		ataque_encolado = true

func iniciar_golpe(paso):
	combo_paso = paso
	ejecutar_accion_bloqueante("combo_" + inventario.objeto_actual + "_" + str(paso))
	sonido_ataque()
	aplicar_golpe()

func sonido_ataque():
	# Golpe al aire: lo oye la jugadora, no los guardias (el ruido sale solo si pega en algo)
	Sonido.reproducir("golpe_aire", global_position, -4.0)

func aplicar_golpe():
	# Consulta directa en vez del área Hitbox: el área quedaba delante del cuerpo y no
	# alcanzaba a los guardias pegados o encima, y entre golpes del combo no volvía a disparar.
	var golpeados = consultar_zona(ZONA_GOLPE_DESDE, ZONA_GOLPE_HASTA, hitbox.collision_mask)
	for cuerpo in golpeados:
		golpear_cuerpo(cuerpo)
	if not golpeados.is_empty():
		Ruido.emitir(global_position, "ataque", self)
	elif not consultar_zona(ZONA_PARED_DESDE, ZONA_PARED_HASTA, 1).is_empty():
		Ruido.emitir(global_position, "golpe_pared", self)
		Sonido.reproducir("piedra", global_position, -4.0)

func consultar_zona(desde, hasta, mascara):
	# Cuerpos dentro de un rectángulo delante de la jugadora (desde/hasta mirando a la derecha)
	var dir = -1.0 if facing_left else 1.0
	var forma = RectangleShape2D.new()
	forma.size = hasta - desde
	var centro = (desde + hasta) * 0.5
	var consulta = PhysicsShapeQueryParameters2D.new()
	consulta.shape = forma
	consulta.transform = Transform2D(0.0, global_position + Vector2(centro.x * dir, centro.y))
	consulta.collision_mask = mascara
	consulta.exclude = [get_rid()]
	var cuerpos = []
	for resultado in get_world_2d().direct_space_state.intersect_shape(consulta, 16):
		cuerpos.append(resultado.collider)
	return cuerpos

func golpear_cuerpo(body):
	if body.is_in_group("enemigo") or body.is_in_group("cazadora"):
		if body.has_method("recibir_dano"):
			var arma = inventario.objeto_actual
			# El tercer golpe del combo de puño desmaya
			body.recibir_dano(global_position.x, arma, combo_paso >= 3)
			Sonido.reproducir("cuchillo_corte" if arma == "cuchillo" else "punetazo", global_position)
		else:
			body.queue_free()

func ejecutar_accion_bloqueante(nombre_animacion):
	accion_bloqueante = true
	anim.speed_scale = 1.0
	# Una acción tiene que terminar para liberar a la jugadora: si la animación quedó en loop
	# en las sprite sheets (pasaba con "desmaya_enemigo"), se quedaba trabada para siempre.
	anim.sprite_frames.set_animation_loop(nombre_animacion, false)
	anim.play(nombre_animacion)

# --- APUNTAR Y ARROJAR ---

func procesar_apuntado(delta):
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
			fuerza_arco = clamp(fuerza_arco + CARGA_POR_SEGUNDO * delta, FUERZA_MIN, fuerza_maxima())
			actualizar_trayectoria()
		else:
			borrar_trayectoria()

		if Input.is_action_just_released("disparar"):
			usar_arma()
			fuerza_arco = FUERZA_MIN

	elif Input.is_action_just_released("apuntar") and is_aiming:
		# Soltar apuntar antes que disparar cancela el tiro
		is_aiming = false
		fuerza_arco = FUERZA_MIN
		borrar_trayectoria()

func borrar_trayectoria():
	if linea_trayectoria.get_point_count() > 0:
		linea_trayectoria.clear_points()

func fuerza_maxima():
	return FUERZA_MAX_ARCO if inventario.es_arco() else FUERZA_MAX_ARROJABLE

func usar_arma():
	if not inventario.intentar_usar():
		return
	var arma = inventario.arma_actual
	if inventario.es_arco(arma):
		disparar_flecha()
		Sonido.reproducir("arco", global_position)
	else:
		lanzar_arrojable(arma)

func actualizar_trayectoria():
	borrar_trayectoria()

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
		nueva_flecha.tipo = inventario.tipo_flecha()
		get_parent().add_child(nueva_flecha)

func lanzar_arrojable(tipo):
	var objeto = Node2D.new()
	objeto.set_script(preload("res://scripts/arrojable.gd"))
	objeto.tipo = tipo
	objeto.velocity = direccion_tiro * fuerza_arco
	get_parent().add_child(objeto)
	objeto.global_position = punto_disparo.global_position
	Sonido.reproducir("arrojar", global_position, -4.0)

# Lo llama el carcaj
func recoger_flechas(tipo, cantidad):
	inventario.recoger_flechas(tipo, cantidad)

# --- CARRUSEL (lo abre el inventario) ---

func puede_abrir_carrusel():
	return not accion_bloqueante and enemigo_agarrado == null and not trepando_escalera

func al_abrir_carrusel():
	is_aiming = false
	linea_trayectoria.clear_points()

# --- ANIMACIÓN ---

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
	anim.speed_scale = 1.0

	if is_hanging:
		anim.offset.y = 5
		anim.offset.x = offset_base_x + (-5.0 if facing_left else 5.0)
		anim.play("trepa")
		anim.pause()
		anim.frame = 0
	elif is_aiming:
		anim.play("prepara_el_arco")
	elif enemigo_agarrado != null:
		anim.play("camina_con_enemigo_agarrado")
		if direction == 0:
			anim.pause()
			anim.frame = 0
	elif timer_wall_run > 0.0:
		anim.play("camina_combate")   # Corre por la pared
		anim.speed_scale = 1.5
	elif not is_on_floor():
		if velocity.y < 0:
			anim.play("salta_hacia_arriba")
		elif velocity.y > MAX_VELOCIDAD_CAIDA_SEGURA:
			anim.play("cae_muy_alto")
		else:
			anim.play("cae")
	elif esta_acostado:
		anim.play("arrastra_acostado" if direction != 0 else "idle_acostado")
	elif direction != 0:
		anim.play("camina_sigilo" if es_sigilo else "camina_combate")
	else:
		anim.play("idle_sigilo" if es_sigilo else "idle_combate")

func _on_animation_finished():
	var terminada = anim.animation

	if "combo" in terminada:
		if ataque_encolado:
			ataque_encolado = false
			iniciar_golpe(combo_paso + 1)
			return

	if terminada == "mata_enemigo" or terminada == "desmaya_enemigo":
		if enemigo_agarrado != null:
			enemigo_agarrado.soltar_cuerpo(terminada == "mata_enemigo")
			enemigo_agarrado = null
		accion_bloqueante = false
		return

	if terminada == "trepa":
		var direccion = -1 if anim.flip_h else 1
		global_position += Vector2(25 * direccion, 12)
		velocity = Vector2.ZERO   # Sin esto conservaba la subida de la trepada y saltaba un poco al llegar
		anim.speed_scale = 1.0
		anim.offset.x = compensacion_sprite if facing_left else 0.0
		anim.offset.y = 0
		accion_bloqueante = false
		return

	accion_bloqueante = false
	ataque_encolado = false
	combo_paso = 0

# --- MUERTE ---

# desde: de dónde vino el golpe (guardia o bala). Con eso se muestra el impacto.
func morir(razon_muerte: String = "Fuiste neutralizado.", desde = null, sonido = "cuchillo_corte"):
	if esta_muerto:
		return
	if desde != null:
		if invulnerable:
			# Muestra el golpe como mucho una vez por segundo, sin morir
			if Time.get_ticks_msec() - ultimo_golpe_ms > 1000:
				ultimo_golpe_ms = Time.get_ticks_msec()
				mostrar_impacto(desde, sonido, false)
			return
		mostrar_impacto(desde, sonido, true)
	elif invulnerable:
		return
	var empuje = Vector2.ZERO
	if desde != null:
		var lado = sign(global_position.x - desde.x)
		if lado == 0:
			lado = -1.0 if not facing_left else 1.0
		empuje = Vector2(EMPUJE_MUERTE.x * lado, EMPUJE_MUERTE.y)
	_morir(razon_muerte, ["aterriza_en_el_piso", "aterriza_en_el_piso_danio"], false, false, empuje)

func mostrar_impacto(desde, sonido, mortal):
	# Gira hacia quien la golpeó para que se lea de dónde vino
	if desde.x != global_position.x:
		facing_left = desde.x < global_position.x
		anim.flip_h = facing_left
	Sonido.reproducir(sonido, global_position, 4.0)
	var sangre = ESCENA_SANGRE.instantiate()
	get_parent().add_child(sangre)
	sangre.global_position = global_position + Vector2(0, -15)
	destello_rojo(0.55 if mortal else 0.3)
	sacudir_camara(14.0 if mortal else 6.0)
	if mortal:
		var tween = create_tween()
		tween.tween_property($Camera2D, "zoom", Vector2.ONE * ZOOM_MUERTE, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pausa_de_impacto(mortal)

func pausa_de_impacto(mortal):
	# Se mide con el reloj real: los timers de la escena dependen de la escala de tiempo
	var escala_previa = Engine.time_scale
	Engine.time_scale = 0.05
	var fin = Time.get_ticks_msec() + int((CONGELADO_MORTAL if mortal else PAUSA_IMPACTO) * 1000.0)
	while Time.get_ticks_msec() < fin:
		await get_tree().process_frame
	if mortal:
		# Cámara lenta mientras sale despedida, recuperando la velocidad de a poco
		await en_tiempo_real(CAMARA_LENTA_MORTAL, func(t): Engine.time_scale = lerp(0.2, escala_previa, t * t))
	Engine.time_scale = escala_previa

func destello_rojo(intensidad):
	var capa = CanvasLayer.new()
	capa.layer = 90
	var rect = ColorRect.new()
	rect.color = Color(0.8, 0.0, 0.0, intensidad)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(rect)
	add_child(capa)
	await en_tiempo_real(0.6, func(t): rect.color.a = intensidad * (1.0 - t))
	capa.queue_free()

func sacudir_camara(fuerza):
	var camara = $Camera2D
	await en_tiempo_real(0.35, func(t):
		camara.offset = Vector2(azar_efectos.randf_range(-1, 1), azar_efectos.randf_range(-1, 1)) * fuerza * (1.0 - t))
	camara.offset = Vector2.ZERO

# Llama a paso(t) con t de 0 a 1 durante "duracion" segundos reales, sin importar la
# escala de tiempo (los tweens y timers se aceleran o frenan con ella).
func en_tiempo_real(duracion, paso: Callable):
	var inicio = Time.get_ticks_msec()
	var t = 0.0
	while t < 1.0:
		t = min((Time.get_ticks_msec() - inicio) / (duracion * 1000.0), 1.0)
		paso.call(t)
		await get_tree().process_frame

func morir_por_caida():
	if invulnerable:
		return
	_morir("La caída fue demasiado alta.", ["aterriza_en_el_piso_danio"], false, true)

func morir_en_vacio():
	_morir("Caíste al vacío.", [], true)

func _morir(razon, animaciones, en_vacio = false, ruido_de_caida = false, empuje = Vector2.ZERO):
	if esta_muerto:
		return
	esta_muerto = true
	accion_bloqueante = true
	anim.speed_scale = 1.0
	velocity = empuje
	inventario.cerrar_carrusel_sin_elegir()
	if ruido_de_caida:
		Ruido.emitir(global_position + PIES, "caida_fuerte", self)
	Sonido.reproducir("muerte_jugador")

	if en_vacio:
		anim.hide()
		if enemigo_agarrado != null:
			enemigo_agarrado.ser_soltado()
			enemigo_agarrado = null
	else:
		# Sigue apoyada en el piso, pero guardias, conos y balas ya no la detectan
		set_deferred("collision_layer", 0)

	for nombre in animaciones:
		anim.play(nombre)
		await anim.animation_finished

	var ui_msg = get_tree().get_first_node_in_group("mensajes_ui")
	if ui_msg:
		ui_msg.mostrar_muerte(razon)
	else:
		await get_tree().create_timer(1.0 if en_vacio else 1.2).timeout
		get_tree().reload_current_scene()
