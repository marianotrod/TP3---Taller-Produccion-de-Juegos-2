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
const VELOCIDAD_ATERRIZAJE_RUIDOSO = 450.0
const VELOCIDAD_CAIDA_FUERTE = 1100.0
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

	actualizar_agarre_de_cornisa()
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

func actualizar_agarre_de_cornisa():
	var should_disable_ledge = false
	if not is_hanging:
		should_disable_ledge = floor_check.is_colliding() or velocity.y < 0 or top_check.is_colliding()
	ledge_collider.disabled = should_disable_ledge
	check_ledge_grab()

func check_ledge_grab():
	if not is_hanging and not floor_check.is_colliding() and not accion_bloqueante:
		if wall_check.is_colliding() and (is_on_floor() or abs(velocity.y) < 10.0) and velocity.y >= 0:
			is_hanging = true
			velocity = Vector2.ZERO

func procesar_colgada():
	velocity = Vector2.ZERO
	var trepar_hacia_pared = (not facing_left and Input.is_action_just_pressed("mover_der")) or (facing_left and Input.is_action_just_pressed("mover_izq"))
	var soltarse_hacia_atras = (not facing_left and Input.is_action_just_pressed("mover_izq")) or (facing_left and Input.is_action_just_pressed("mover_der"))

	if Input.is_action_just_pressed("arriba") or trepar_hacia_pared:
		is_hanging = false
		ejecutar_accion_bloqueante("trepa")
	elif Input.is_action_just_pressed("abajo") or soltarse_hacia_atras:
		is_hanging = false
		position.y += 2

# --- POSTURA ---

func procesar_cambio_de_postura():
	if not Input.is_action_just_pressed("cambiar_postura") or accion_bloqueante:
		return
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
	elif Input.is_action_just_pressed("saltar") and puede_saltar():
		velocity.y = JUMP_VELOCITY
		es_sigilo = false

	if Input.is_action_just_released("saltar") and velocity.y < 0:
		velocity.y *= 0.5

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
	Ruido.emitir(global_position, "ataque", self)
	Sonido.reproducir("golpe_aire", global_position, -4.0)

func aplicar_golpe():
	# Consulta directa en vez del área Hitbox: el área quedaba delante del cuerpo y no
	# alcanzaba a los guardias pegados o encima, y entre golpes del combo no volvía a disparar.
	var dir = -1.0 if facing_left else 1.0
	var forma = RectangleShape2D.new()
	forma.size = ZONA_GOLPE_HASTA - ZONA_GOLPE_DESDE
	var centro = (ZONA_GOLPE_DESDE + ZONA_GOLPE_HASTA) * 0.5
	var consulta = PhysicsShapeQueryParameters2D.new()
	consulta.shape = forma
	consulta.transform = Transform2D(0.0, global_position + Vector2(centro.x * dir, centro.y))
	consulta.collision_mask = hitbox.collision_mask
	consulta.exclude = [get_rid()]
	for resultado in get_world_2d().direct_space_state.intersect_shape(consulta, 16):
		golpear_cuerpo(resultado.collider)

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
		anim.offset.x = compensacion_sprite if facing_left else 0.0
		anim.offset.y = 0
		accion_bloqueante = false
		return

	accion_bloqueante = false
	ataque_encolado = false
	combo_paso = 0

# --- MUERTE ---

func morir(razon_muerte: String = "Fuiste neutralizado."):
	_morir(razon_muerte, ["aterriza_en_el_piso", "aterriza_en_el_piso_danio"])

func morir_por_caida():
	_morir("La caída fue demasiado alta.", ["aterriza_en_el_piso_danio"], false, true)

func morir_en_vacio():
	_morir("Caíste al vacío.", [], true)

func _morir(razon, animaciones, en_vacio = false, ruido_de_caida = false):
	if esta_muerto:
		return
	esta_muerto = true
	accion_bloqueante = true
	velocity = Vector2.ZERO
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
		colision_parado.set_deferred("disabled", true)
		colision_sigilo.set_deferred("disabled", true)
		colision_acostado.set_deferred("disabled", true)

	for nombre in animaciones:
		anim.play(nombre)
		await anim.animation_finished

	var ui_msg = get_tree().get_first_node_in_group("mensajes_ui")
	if ui_msg:
		ui_msg.mostrar_muerte(razon)
	else:
		await get_tree().create_timer(1.0 if en_vacio else 1.2).timeout
		get_tree().reload_current_scene()
