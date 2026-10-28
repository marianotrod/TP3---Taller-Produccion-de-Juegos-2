extends CharacterBody2D

enum Estado { PATRULLANDO, SOSPECHANDO, AGRESIVO, MUERTO, AGARRADO, DESMAYADO, LEVANTANDOSE, ESPERANDO_MARCADOR, SALTANDO, TREPANDO, CAYENDO_POR_AGUJERO, EN_ESCALERA, VOLVIENDO }

var timer_marcador = 0.0
var orden_pendiente = 0
var estado_actual = Estado.PATRULLANDO

const SPEED_PATRULLA = 100.0
const SPEED_SOSPECHA = 150
const SPEED_PERSECUCION = 285.0

# --- FÍSICAS PROPORCIONALES AL JUGADOR ---
const JUMP_VELOCITY = -650.0
var gravity_up = 1800.0
var gravity_down = 2200.0

# --- VARIABLES DE ESCALERA ---
const SPEED_ESCALERA = 60.0
const SPEED_ESCALERA_NAV = 140.0
var direccion_escalera = -1
var ancho_colision_original = 0.0
var tiempo_en_escalera = 0.0

# --- TIEMPOS DE ATENCIÓN ---
const TIEMPO_REACCION = 0.6      # Se gira hacia el ruido antes de ir a investigar
const TIEMPO_MIRANDO = 4.0       # Cuánto mira alrededor al llegar al punto de interés
const TIEMPO_ALERTA = 10.0       # Cuánto busca después de perder de vista al jugador
const TIEMPO_DESMAYO = 10.0
const TIEMPO_SOLTADO = 2.5       # Cuánto tarda en reaccionar un rehén soltado/arrojado
const TIEMPO_REGENERAR = 10.0    # Sin recibir daño, recupera toda la vida
const VIDA_MAX = 3
const PIES = 64.0                # Distancia del origen a los pies (para la navegación)

# --- EFECTOS VISUALES ---
@export var escena_sangre: PackedScene
# El "gorro" es el casco: absorbe la primera agresión y lo protege de la flecha sedante
@export var tiene_gorro = true

@onready var anim = $AnimatedSprite2D
@onready var ray_muro = $RayMuro
@onready var ray_piso = $RayPiso
@onready var ray_vision = $RayVision
@onready var cono_poligono = $ConoVision/CollisionPolygon2D

@onready var wall_check = $WallCheck
@onready var floor_check = $FloorCheck

var direccion_x = 1
var tiempo_sospecha = 0.0
var tiempo_desmayado = 0.0

var vida = VIDA_MAX
var esta_herido = false
var compensacion_sprite = 0.0

# --- SISTEMA DE DETECCIÓN VISUAL ---
var estado_alerta = 0 # 0: Tranquilo, 1: Sospecha, 2: Alerta
var nivel_sospecha = 0.0 # 0 a 100
var jugador_en_vision = null # Guarda referencia al jugador si está en el cono
var viendo_jugador = false

# --- ATENCIÓN Y NAVEGACIÓN ---
var punto_interes = null
var fase_sospecha = "reaccion"   # reaccion -> yendo -> mirando
var timer_reaccion = 0.0
var timer_alerta = 0.0
var timer_busqueda = 0.0
var puesto_patrulla = null
var direccion_patrulla = 1
var ruido_pendiente = null
var despertar_en_alerta = false
var tiempo_sin_dano = 0.0
var poligono_patrulla = PackedVector2Array()

var ruta = []
var ruta_idx = 0
var ruta_destino = null
var nav_saltando = false
var nav_tiempo_salto = 0.0
var nav_en_escalera = false
var timer_repath = 0.0
var timer_progreso = 0.0
var pos_progreso = Vector2.ZERO
var reintentos_ruta = 0
var intentos_destino = 0

func _ready():
	anim.animation_finished.connect(_on_animation_finished)

	# Hace única la colisión y guarda su tamaño original
	$CollisionShape2D.shape = $CollisionShape2D.shape.duplicate()
	ancho_colision_original = $CollisionShape2D.shape.size.x
	poligono_patrulla = cono_poligono.polygon

	cambiar_icono_estado("")

func _physics_process(delta):
	procesar_vision(delta)

	if estado_actual == Estado.AGARRADO:
		return

	# Gravedad proporcional (anulada si está trepando o en escalera)
	if not is_on_floor() and estado_actual not in [Estado.TREPANDO, Estado.EN_ESCALERA] and not nav_en_escalera:
		if velocity.y < 0:
			velocity.y += gravity_up * delta
		else:
			velocity.y += gravity_down * delta

	if estado_actual in [Estado.MUERTO, Estado.LEVANTANDOSE]:
		move_and_slide()
		return

	if estado_actual == Estado.DESMAYADO:
		# Frena el deslizamiento si fue arrojado
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0, 1500 * delta)
		move_and_slide()
		tiempo_desmayado += delta
		if tiempo_desmayado >= TIEMPO_DESMAYO:
			despertarse()
		return

	tiempo_sin_dano += delta
	if vida < VIDA_MAX and tiempo_sin_dano >= TIEMPO_REGENERAR:
		vida = VIDA_MAX

	# Pausa de la IA si está procesando el knockup por daño
	if esta_herido:
		move_and_slide()
		return

	# Un ruido escuchado en el aire se procesa al volver a patrullar
	if ruido_pendiente != null and estado_actual == Estado.PATRULLANDO and is_on_floor():
		var pos_ruido = ruido_pendiente
		ruido_pendiente = null
		oir_ruido(pos_ruido, 0.0)

	match estado_actual:
		Estado.PATRULLANDO:
			comportamiento_patrulla(delta)
		Estado.SOSPECHANDO:
			comportamiento_sospecha(delta)
		Estado.AGRESIVO:
			comportamiento_agresivo(delta)
		Estado.VOLVIENDO:
			comportamiento_volviendo(delta)
		Estado.ESPERANDO_MARCADOR:
			velocity.x = 0
			timer_marcador -= delta
			if timer_marcador <= 0:
				if orden_pendiente == 2:
					dar_vuelta()
				estado_actual = Estado.PATRULLANDO
		Estado.SALTANDO:
			velocity.x = direccion_x * SPEED_PATRULLA
			check_ledge_grab()
			if is_on_floor() and velocity.y >= 0:
				estado_actual = Estado.PATRULLANDO
				$CollisionShape2D.shape.size.x = ancho_colision_original
		Estado.TREPANDO:
			velocity.x = 20
			velocity.y = -50
		Estado.CAYENDO_POR_AGUJERO:
			velocity.x = direccion_x * SPEED_PATRULLA
			if not is_on_floor():
				orden_pendiente = 1
			if is_on_floor() and orden_pendiente == 1:
				estado_actual = Estado.PATRULLANDO
		Estado.EN_ESCALERA:
			velocity.x = 0
			velocity.y = direccion_escalera * SPEED_ESCALERA
			tiempo_en_escalera += delta

			# Al bajar y tocar el piso inferior
			if direccion_escalera == 1 and is_on_floor() and tiempo_en_escalera > 0.1:
				soltar_escalera()

	move_and_slide()

	# Chequeo directo por colisión física contra el jugador
	if estado_actual not in [Estado.MUERTO, Estado.DESMAYADO, Estado.AGARRADO]:
		for i in range(get_slide_collision_count()):
			var colision = get_slide_collision(i)
			var collider = colision.get_collider()
			if collider and collider.is_in_group("jugador"):
				if collider.has_method("morir"):
					collider.morir("Un guardia te ha descubierto y ejecutado.")

	actualizar_animaciones()
	queue_redraw()

# --- SEGURIDAD DE ESCALERA ---

func abortar_escalera():
	if estado_actual == Estado.EN_ESCALERA:
		call_deferred("set_collision_mask_value", 1, true)
		$CollisionShape2D.shape.size.x = ancho_colision_original

# --- SISTEMA DE ICONO ESTADO ---

func cambiar_icono_estado(animacion_icono):
	if not has_node("IconoEstado"): return

	if animacion_icono == "":
		$IconoEstado.hide()
		return

	$IconoEstado.show()
	$IconoEstado.play(animacion_icono)

	if animacion_icono == "dormido":
		var mod_x = 20.0 if anim.flip_h else -20.0
		$IconoEstado.offset = Vector2(mod_x, 25.0)
		$IconoEstado.scale = Vector2(2.0, 2.0)
	else:
		$IconoEstado.offset = Vector2(0.0, 0.0)
		$IconoEstado.scale = Vector2(1.0, 1.0)

# --- SISTEMA DE SANGRE ---

func generar_sangre():
	if escena_sangre:
		var sangre = escena_sangre.instantiate()
		get_parent().add_child(sangre)
		sangre.global_position = global_position + Vector2(0, -15)

# --- FUNCIONES DE VISIÓN ---

func procesar_vision(delta):
	viendo_jugador = false
	if esta_herido or estado_actual in [Estado.MUERTO, Estado.DESMAYADO, Estado.AGARRADO, Estado.LEVANTANDOSE]:
		return

	if jugador_en_vision and puede_ver_jugador(jugador_en_vision):
		var jugador = jugador_en_vision
		viendo_jugador = true
		punto_interes = jugador.global_position

		if estado_actual == Estado.AGRESIVO:
			timer_alerta = TIEMPO_ALERTA
			return

		var camuflaje = jugador.get("nivel_ocultamiento")
		if camuflaje == null:
			camuflaje = 0

		if jugador.es_sigilo or jugador.esta_acostado:
			if estado_alerta == 0 or estado_actual == Estado.VOLVIENDO:
				entrar_estado_sospecha(jugador.global_position)

			var velocidad_deteccion = 60.0
			if camuflaje == 1:
				velocidad_deteccion = 15.0

			nivel_sospecha += delta * velocidad_deteccion

			if nivel_sospecha >= 100:
				entrar_estado_alerta()
		else:
			entrar_estado_alerta()
	else:
		bajar_sospecha_gradual(delta)

func puede_ver_jugador(jugador):
	if jugador.get("esta_muerto"):
		return false
	ray_vision.target_position = to_local(jugador.global_position)
	ray_vision.force_raycast_update()
	if ray_vision.is_colliding():
		return false

	var camuflaje = jugador.get("nivel_ocultamiento")
	if camuflaje == null:
		camuflaje = 0
	if camuflaje == 2 and (jugador.es_sigilo or jugador.esta_acostado):
		return false
	if jugador.has_method("esta_en_humo") and jugador.esta_en_humo():
		return false
	if follaje_bloquea(global_position, jugador.global_position):
		return false
	if humo_bloquea(global_position, jugador.global_position):
		return false
	return true

func follaje_bloquea(desde, hasta):
	# Un arbusto entre el enemigo y el jugador corta la línea de visión
	var escena = get_tree().current_scene
	if escena == null:
		return false
	var mapa = escena.get_node_or_null("TileMapLayer2")
	if mapa == null:
		return false
	var distancia = desde.distance_to(hasta)
	var pasos = int(distancia / 32.0)
	for i in range(1, pasos):
		var punto = desde.lerp(hasta, float(i) / pasos)
		if punto.distance_to(desde) < 60.0 or punto.distance_to(hasta) < 60.0:
			continue
		var datos = mapa.get_cell_tile_data(mapa.local_to_map(mapa.to_local(punto)))
		if datos and datos.get_custom_data("tipo_ocultamiento") == 2:
			return true
	return false

func humo_bloquea(desde, hasta):
	for nube in get_tree().get_nodes_in_group("humo"):
		var centro = nube.global_position
		var cercano = Geometry2D.get_closest_point_to_segment(centro, desde, hasta)
		if cercano.distance_to(centro) < nube.radio:
			return true
	return false

func bajar_sospecha_gradual(delta):
	if nivel_sospecha > 0 and estado_actual != Estado.AGRESIVO:
		nivel_sospecha = max(0.0, nivel_sospecha - delta * 40)

func _on_cono_vision_body_entered(body):
	if body != null and not body.is_queued_for_deletion():
		if body.is_in_group("jugador"):
			jugador_en_vision = body

func _on_cono_vision_body_exited(body):
	if body != null and body.is_in_group("jugador"):
		if not body in $ConoVision.get_overlapping_bodies():
			if jugador_en_vision == body:
				jugador_en_vision = null

func aplicar_cono():
	# Patrulla: corto y hacia abajo. Sospecha: más amplio. Alerta: largo y ancho.
	var puntos = poligono_patrulla
	if estado_actual == Estado.SOSPECHANDO:
		puntos = PackedVector2Array([Vector2(0, -10), Vector2(480, -90), Vector2(480, 130)])
	elif estado_actual == Estado.AGRESIVO:
		puntos = PackedVector2Array([Vector2(0, -10), Vector2(620, -220), Vector2(620, 200)])
	cono_poligono.set_deferred("polygon", puntos)

# --- CAMBIOS DE ESTADO ---

func guardar_puesto():
	# Recuerda dónde estaba patrullando para volver después
	if puesto_patrulla == null and estado_actual in [Estado.PATRULLANDO, Estado.ESPERANDO_MARCADOR, Estado.EN_ESCALERA, Estado.SALTANDO, Estado.CAYENDO_POR_AGUJERO]:
		puesto_patrulla = global_position
		direccion_patrulla = direccion_x

func entrar_estado_sospecha(posicion = null):
	abortar_escalera()
	guardar_puesto()
	limpiar_ruta()
	var ya_sospechaba = estado_actual == Estado.SOSPECHANDO
	estado_alerta = 1
	estado_actual = Estado.SOSPECHANDO
	tiempo_sospecha = 0.0
	punto_interes = posicion if posicion != null else global_position
	if posicion == null:
		fase_sospecha = "mirando"
	else:
		fase_sospecha = "reaccion"
		timer_reaccion = TIEMPO_REACCION * (0.4 if ya_sospechaba else 1.0)
		mirar_hacia(punto_interes.x)
	cambiar_icono_estado("sospecha")
	if not ya_sospechaba:
		Sonido.reproducir("sospecha", global_position)
	aplicar_cono()

func entrar_estado_alerta():
	timer_alerta = TIEMPO_ALERTA
	if estado_actual == Estado.AGRESIVO:
		return
	abortar_escalera()
	guardar_puesto()
	limpiar_ruta()
	estado_alerta = 2
	estado_actual = Estado.AGRESIVO
	nivel_sospecha = 100.0
	var jugador = get_tree().get_first_node_in_group("jugador")
	if jugador and punto_interes == null:
		punto_interes = jugador.global_position
	cambiar_icono_estado("alerta")
	Sonido.reproducir("alerta", global_position)
	aplicar_cono()

func bajar_alerta():
	volver_a_patrulla()

func volver_a_patrulla():
	estado_alerta = 0
	nivel_sospecha = 0.0
	punto_interes = null
	limpiar_ruta()
	cambiar_icono_estado("")
	if puesto_patrulla == null or global_position.distance_to(puesto_patrulla) < 40.0:
		terminar_vuelta()
	else:
		estado_actual = Estado.VOLVIENDO
		aplicar_cono()

func terminar_vuelta():
	if puesto_patrulla != null and direccion_x != direccion_patrulla:
		dar_vuelta()
	puesto_patrulla = null
	estado_actual = Estado.PATRULLANDO
	velocity.x = 0
	aplicar_cono()

func oir_ruido(posicion, _radio):
	if esta_herido or estado_actual in [Estado.MUERTO, Estado.DESMAYADO, Estado.AGARRADO, Estado.LEVANTANDOSE]:
		return
	if estado_actual in [Estado.SALTANDO, Estado.TREPANDO, Estado.CAYENDO_POR_AGUJERO, Estado.EN_ESCALERA] or nav_en_escalera or nav_saltando:
		# Termina la maniobra y después investiga
		ruido_pendiente = posicion
		return
	if estado_actual == Estado.AGRESIVO:
		if not viendo_jugador:
			punto_interes = posicion
			timer_alerta = TIEMPO_ALERTA
			limpiar_ruta()
		return
	entrar_estado_sospecha(posicion)

# --- COMPORTAMIENTOS ---

func comportamiento_patrulla(_delta):
	var jugador = get_tree().get_first_node_in_group("jugador")
	if jugador and not jugador.esta_muerto:
		var distancia = global_position.distance_to(jugador.global_position)
		var dir_hacia_jugador = sign(jugador.global_position.x - global_position.x)

		var camuflaje = jugador.get("nivel_ocultamiento")
		if camuflaje == null:
			camuflaje = 0

		var esta_escondido = camuflaje == 2 and (jugador.es_sigilo or jugador.esta_acostado)

		if esta_escondido:
			add_collision_exception_with(jugador)
		else:
			remove_collision_exception_with(jugador)

			if distancia < 20.0 and dir_hacia_jugador == direccion_x:
				entrar_estado_alerta()
				return
			elif distancia < 30.0 and not jugador.es_sigilo and not jugador.esta_acostado:
				entrar_estado_alerta()
				return

	if ray_muro.is_colliding():
		dar_vuelta()
	elif is_on_floor() and not ray_piso.is_colliding():
		dar_vuelta()

	velocity.x = direccion_x * SPEED_PATRULLA

func comportamiento_sospecha(delta):
	match fase_sospecha:
		"reaccion":
			velocity.x = 0
			timer_reaccion -= delta
			if timer_reaccion <= 0:
				fase_sospecha = "yendo"
				pedir_ruta(punto_interes)
		"yendo":
			if seguir_ruta(delta, SPEED_SOSPECHA):
				fase_sospecha = "mirando"
				tiempo_sospecha = 0.0
		"mirando":
			velocity.x = 0
			tiempo_sospecha += delta
			if tiempo_sospecha >= TIEMPO_MIRANDO and not viendo_jugador:
				volver_a_patrulla()

func comportamiento_agresivo(delta):
	var jugador = get_tree().get_first_node_in_group("jugador")
	if jugador == null:
		return

	if viendo_jugador:
		var distancia = global_position.distance_to(jugador.global_position)
		if distancia < 25.0:
			velocity.x = 0
			if jugador.has_method("morir"):
				jugador.morir("Un guardia te ha descubierto y ejecutado.")
			return
		# Persecución: se recalcula la ruta seguido porque el jugador se mueve
		timer_repath -= delta
		if timer_repath <= 0 or ruta.is_empty():
			timer_repath = 0.4
			pedir_ruta(jugador.global_position)
		if seguir_ruta(delta, SPEED_PERSECUCION):
			# Ruta terminada (misma plataforma): va directo hacia el jugador
			var dx = jugador.global_position.x - global_position.x
			if abs(dx) > 8.0 and abs(jugador.global_position.y - global_position.y) < 80.0:
				mirar_hacia(jugador.global_position.x)
				velocity.x = sign(dx) * SPEED_PERSECUCION
		return

	# Lo perdió de vista: va al último punto de interés y después busca
	timer_alerta -= delta
	if timer_alerta <= 0:
		cambiar_icono_estado("sospecha")
		estado_alerta = 1
		estado_actual = Estado.SOSPECHANDO
		fase_sospecha = "mirando"
		tiempo_sospecha = 0.0
		limpiar_ruta()
		aplicar_cono()
		return

	if punto_interes != null:
		if ruta.is_empty() or ruta_destino != punto_interes:
			pedir_ruta(punto_interes)
		if seguir_ruta(delta, SPEED_SOSPECHA):
			punto_interes = null
			timer_busqueda = randf_range(0.5, 1.2)
		return

	# Búsqueda errática por los alrededores
	velocity.x = 0
	timer_busqueda -= delta
	if timer_busqueda <= 0:
		var candidatos = Navegacion.nodos_cercanos(global_position + Vector2(0, PIES), 600.0)
		if not candidatos.is_empty():
			var elegido = Navegacion.nodos[candidatos.pick_random()]
			punto_interes = elegido - Vector2(0, PIES)
		timer_busqueda = 1.0

func comportamiento_volviendo(delta):
	if puesto_patrulla == null:
		terminar_vuelta()
		return
	if ruta.is_empty():
		pedir_ruta(puesto_patrulla)
	if seguir_ruta(delta, SPEED_PATRULLA):
		terminar_vuelta()

func mirar_hacia(x):
	var dir = sign(x - global_position.x)
	if dir != 0 and dir != direccion_x:
		dar_vuelta()

func dar_vuelta():
	direccion_x *= -1
	ray_muro.target_position.x *= -1
	ray_piso.position.x *= -1
	if has_node("ConoVision"):
		$ConoVision.scale.x *= -1

	wall_check.target_position.x *= -1
	floor_check.target_position.x *= -1

# --- SEGUIMIENTO DE RUTAS ---

func pedir_ruta(destino):
	limpiar_ruta()
	if destino != ruta_destino:
		intentos_destino = 0
	ruta_destino = destino
	if destino == null or not Navegacion.listo:
		return
	ruta = Navegacion.calcular_ruta(global_position + Vector2(0, PIES), destino + Vector2(0, PIES))
	ruta_idx = 0
	timer_progreso = 0.0
	pos_progreso = global_position

func limpiar_ruta():
	if nav_en_escalera:
		set_collision_mask_value(1, true)
		$CollisionShape2D.shape.size.x = ancho_colision_original
	ruta = []
	ruta_idx = 0
	nav_saltando = false
	nav_en_escalera = false

# Devuelve true cuando llegó (o no hay forma de llegar)
func seguir_ruta(delta, velocidad):
	if ruta.size() < 2 or ruta_idx >= ruta.size() - 1:
		velocity.x = 0
		# Terminó la ruta pero quedó lejos (salto fallido): reintenta un par de veces
		if not ruta.is_empty() and ruta_destino != null and global_position.distance_to(ruta_destino) > 100.0 and intentos_destino < 2:
			intentos_destino += 1
			pedir_ruta(ruta_destino)
			return false
		return true

	# Si no avanza durante un rato, recalcula; si sigue sin poder, abandona
	timer_progreso += delta
	if timer_progreso > 1.2:
		if global_position.distance_to(pos_progreso) < 12.0 and not nav_en_escalera:
			reintentos_ruta += 1
			var destino = ruta_destino
			if reintentos_ruta > 2:
				reintentos_ruta = 0
				limpiar_ruta()
				return true
			pedir_ruta(destino)
			return false
		reintentos_ruta = 0
		timer_progreso = 0.0
		pos_progreso = global_position

	var a = ruta[ruta_idx]
	var b = ruta[ruta_idx + 1]
	var datos = Navegacion.arista(a, b)
	var tipo = datos.get("tipo", Navegacion.Tipo.CAMINAR)
	var pies = global_position + Vector2(0, PIES)
	var destino = Navegacion.nodos[b]

	# Si quedó en otra superficie (aterrizó mal, lo empujaron), recalcula
	if is_on_floor() and not nav_saltando and not nav_en_escalera and tipo != Navegacion.Tipo.ESCALERA:
		var origen = Navegacion.nodos[a]
		if abs(pies.y - origen.y) > 60.0 and abs(pies.y - destino.y) > 60.0:
			reintentos_ruta += 1
			if reintentos_ruta > 3:
				reintentos_ruta = 0
				limpiar_ruta()
				return true
			pedir_ruta(ruta_destino)
			return false

	match tipo:
		Navegacion.Tipo.SALTAR:
			if nav_saltando:
				nav_tiempo_salto += delta
				velocity.x = datos.vx
				if nav_tiempo_salto > 0.1 and is_on_floor():
					nav_saltando = false
					velocity.x = 0
					ruta_idx += 1
			else:
				var origen = Navegacion.nodos[a]
				var dx = origen.x - pies.x
				if abs(dx) > 6.0:
					mirar_hacia(origen.x)
					velocity.x = sign(dx) * min(velocidad, abs(dx) / delta)
				elif is_on_floor():
					mirar_hacia(destino.x)
					velocity = Vector2(datos.vx, datos.vy)
					nav_saltando = true
					nav_tiempo_salto = 0.0
		Navegacion.Tipo.ESCALERA:
			if not nav_en_escalera:
				var dx = datos.x - global_position.x
				if abs(dx) > 6.0:
					mirar_hacia(datos.x)
					velocity.x = sign(dx) * min(velocidad, abs(dx) / delta)
				else:
					nav_en_escalera = true
					global_position.x = datos.x
					velocity = Vector2.ZERO
					set_collision_mask_value(1, false)
					$CollisionShape2D.shape.size.x = 10.0
			else:
				velocity.x = 0
				var objetivo_y = destino.y - PIES
				var dy = objetivo_y - global_position.y
				if abs(dy) <= SPEED_ESCALERA_NAV * delta + 1.0:
					global_position.y = objetivo_y - 2.0
					velocity.y = 0
					nav_en_escalera = false
					set_collision_mask_value(1, true)
					$CollisionShape2D.shape.size.x = ancho_colision_original
					ruta_idx += 1
				else:
					velocity.y = sign(dy) * SPEED_ESCALERA_NAV
		_:
			# CAMINAR y CAER: en el aire mantiene la inercia
			if tipo == Navegacion.Tipo.CAER:
				if not is_on_floor():
					# En el aire se corrige hacia la columna donde tiene que caer
					velocity.x = clamp((destino.x - pies.x) * 6.0, -velocidad, velocidad)
					return false
				if pies.y < destino.y - 40.0:
					# Todavía arriba: sigue caminando hacia el borde hasta caer
					var lado = sign(destino.x - Navegacion.nodos[a].x)
					if lado == 0:
						lado = direccion_x
					mirar_hacia(global_position.x + lado)
					velocity.x = lado * velocidad
					return false
			var dx = destino.x - pies.x
			var llego_altura = abs(pies.y - destino.y) < 40.0 or tipo == Navegacion.Tipo.CAMINAR
			if abs(dx) < 10.0 and llego_altura:
				ruta_idx += 1
			else:
				mirar_hacia(destino.x)
				velocity.x = sign(dx) * velocidad
	return false

func reproducir_animacion(nombre_animacion):
	if tiene_gorro:
		anim.play(nombre_animacion)
	else:
		anim.play(nombre_animacion + "_sin_gorro")

func actualizar_animaciones():
	anim.flip_h = (direccion_x < 0)
	var offset_base_x = compensacion_sprite if (direccion_x < 0) else 0.0

	if estado_actual != Estado.TREPANDO:
		anim.offset.y = 0
		anim.offset.x = offset_base_x

	if esta_herido or estado_actual == Estado.TREPANDO:
		return

	if nav_en_escalera:
		reproducir_animacion("trepa_escalera")
		return
	if estado_actual in [Estado.SOSPECHANDO, Estado.AGRESIVO, Estado.VOLVIENDO] and not is_on_floor():
		reproducir_animacion("salta" if velocity.y < 0 else "cae")
		return

	match estado_actual:
		Estado.PATRULLANDO:
			reproducir_animacion("idle" if velocity.x == 0 else "patrulla_camina")
		Estado.SOSPECHANDO:
			if fase_sospecha == "reaccion":
				reproducir_animacion("sorpresa")
			elif velocity.x != 0:
				reproducir_animacion("curioso_camina")
			else:
				reproducir_animacion("mira_derecha_izquierda_patrulla")
		Estado.AGRESIVO:
			if velocity.x != 0:
				reproducir_animacion("corre_y_ataca")
			else:
				reproducir_animacion("mira_derecha_izquierda_patrulla")
		Estado.VOLVIENDO:
			reproducir_animacion("idle" if velocity.x == 0 else "patrulla_camina")
		Estado.ESPERANDO_MARCADOR:
			reproducir_animacion("mira_derecha_izquierda_patrulla")
		Estado.SALTANDO:
			if velocity.y < 0:
				reproducir_animacion("salta")
			else:
				reproducir_animacion("cae")
		Estado.CAYENDO_POR_AGUJERO:
			if is_on_floor():
				reproducir_animacion("patrulla_camina")
			else:
				reproducir_animacion("cae")
		Estado.EN_ESCALERA:
			reproducir_animacion("trepa_escalera")

# --- DAÑO ---

func preparar_para_golpe():
	abortar_escalera()
	limpiar_ruta()
	$CollisionShape2D.shape.size.x = ancho_colision_original
	if estado_actual == Estado.TREPANDO:
		$CollisionShape2D.set_deferred("disabled", false)

# arma: "cuchillo" quita vida, "puño" aturde. El último golpe del combo de puño desmaya.
func recibir_dano(atacante_x = null, arma = "cuchillo", golpe_final = false):
	preparar_para_golpe()

	if estado_actual in [Estado.MUERTO, Estado.DESMAYADO, Estado.LEVANTANDOSE]:
		return
	tiempo_sin_dano = 0.0

	if tiene_gorro:
		# El casco absorbe la primera agresión y se cae
		tiene_gorro = false
		aturdir(atacante_x)
		return

	if arma == "puño":
		if golpe_final:
			caer_desmayado()
		else:
			aturdir(atacante_x)
		return

	vida -= 1

	if vida <= 0:
		morir_general("danio_cae_al_suelo")
	else:
		aturdir(atacante_x)

func aturdir(atacante_x = null):
	esta_herido = true
	nivel_sospecha = 100.0
	entrar_estado_alerta()

	if atacante_x != null:
		var dir_al_atacante = sign(atacante_x - global_position.x)
		if dir_al_atacante != 0 and dir_al_atacante != direccion_x:
			dar_vuelta()

	if atacante_x != null:
		var dir_empuje = sign(global_position.x - atacante_x)
		if dir_empuje == 0:
			dir_empuje = -direccion_x
		velocity.x = dir_empuje * 180.0
	else:
		velocity.x = -direccion_x * 180.0

	velocity.y = -300.0

	reproducir_animacion("recibe_danio")
	await anim.animation_finished

	velocity.x = 0
	esta_herido = false

func caer_desmayado():
	limpiar_ruta()
	estado_actual = Estado.DESMAYADO
	tiene_gorro = false
	tiempo_desmayado = 0.0
	velocity.x = 0
	anim.flip_h = not anim.flip_h
	cambiar_icono_estado("dormido")
	$CollisionShape2D.set_deferred("disabled", false)
	reproducir_animacion("desmayado_idle")

func quitar_colision_de_cuerpo():
	# El cadáver sigue apoyado en el piso, pero ya no lo tocan flechas ni ataques
	set_deferred("collision_layer", 0)
	jugador_en_vision = null

func morir_general(animacion_caida):
	limpiar_ruta()
	estado_actual = Estado.MUERTO
	velocity.x = 0
	anim.flip_h = not anim.flip_h
	cambiar_icono_estado("")
	quitar_colision_de_cuerpo()
	generar_sangre()
	Sonido.reproducir("muerte_enemigo", global_position)
	reproducir_animacion(animacion_caida)
	await anim.animation_finished
	reproducir_animacion("muerto")
	set_physics_process(false)

func puede_recibir_takedown(posicion_jugador_x):
	if estado_actual in [Estado.AGRESIVO, Estado.MUERTO, Estado.AGARRADO, Estado.DESMAYADO, Estado.LEVANTANDOSE, Estado.TREPANDO, Estado.CAYENDO_POR_AGUJERO, Estado.EN_ESCALERA]:
		return false
	if nav_en_escalera or nav_saltando:
		return false
	if direccion_x == 1 and posicion_jugador_x < global_position.x:
		return true
	elif direccion_x == -1 and posicion_jugador_x > global_position.x:
		return true
	return false

func ser_agarrado():
	abortar_escalera()
	limpiar_ruta()
	guardar_puesto()
	$CollisionShape2D.shape.size.x = ancho_colision_original
	estado_actual = Estado.AGARRADO
	cambiar_icono_estado("")
	$CollisionShape2D.set_deferred("disabled", true)
	velocity = Vector2.ZERO
	reproducir_animacion("agarrado")

func ser_desmayado():
	$CollisionShape2D.shape.size.x = ancho_colision_original
	estado_actual = Estado.DESMAYADO
	tiene_gorro = false
	cambiar_icono_estado("dormido")
	reproducir_animacion("agarrado_desmayando")
	await anim.animation_finished
	if estado_actual == Estado.DESMAYADO:
		reproducir_animacion("agarrado_desmayando_mantener")

func ser_asesinado():
	estado_actual = Estado.MUERTO
	cambiar_icono_estado("")
	generar_sangre()
	reproducir_animacion("agarrado_matar")

func soltar_cuerpo(es_muerte):
	set_physics_process(true)
	$CollisionShape2D.set_deferred("disabled", false)
	set_collision_mask_value(1, true)

	anim.flip_h = not anim.flip_h

	if es_muerte:
		quitar_colision_de_cuerpo()
		reproducir_animacion("muerto")
		cambiar_icono_estado("")
	else:
		tiempo_desmayado = 0.0
		cambiar_icono_estado("dormido")
		reproducir_animacion("agarrado_desmayado_cae_al_suelo")
		await anim.animation_finished
		if estado_actual == Estado.DESMAYADO:
			reproducir_animacion("desmayado_idle")

# Rehén soltado (Y) o arrojado (A): cae, se recupera enseguida y queda en alerta
func ser_soltado(impulso = Vector2.ZERO):
	estado_actual = Estado.DESMAYADO
	despertar_en_alerta = true
	soltar_cuerpo(false)
	tiempo_desmayado = TIEMPO_DESMAYO - TIEMPO_SOLTADO
	cambiar_icono_estado("")
	velocity = impulso

func actualizar_movimiento_agarrado(direccion_jugador, facing_left_jugador):
	if estado_actual == Estado.MUERTO or estado_actual == Estado.DESMAYADO:
		return
	anim.flip_h = facing_left_jugador
	if direccion_jugador != 0:
		reproducir_animacion("agarrado_camina")
	else:
		reproducir_animacion("agarrado")

func ser_neutralizado():
	abortar_escalera()
	limpiar_ruta()
	estado_actual = Estado.MUERTO
	velocity = Vector2.ZERO
	cambiar_icono_estado("")
	quitar_colision_de_cuerpo()
	generar_sangre()
	reproducir_animacion("agarrado_matar")
	await anim.animation_finished
	reproducir_animacion("muerto")
	set_physics_process(false)

func recibir_flechazo(tipo_flecha, direccion_flecha = Vector2.ZERO):
	preparar_para_golpe()

	if estado_actual in [Estado.MUERTO, Estado.DESMAYADO, Estado.LEVANTANDOSE]:
		return
	tiempo_sin_dano = 0.0

	if tipo_flecha == "letal":
		if tiene_gorro:
			# Pierde el casco sin recibir daño
			tiene_gorro = false
			aturdir(global_position.x - sign(direccion_flecha.x) * 50.0 if direccion_flecha != Vector2.ZERO else null)
			return
		morir_general("danio_cae_al_suelo")
	elif tipo_flecha == "desmayante":
		if tiene_gorro:
			# El casco lo protege, pero se da cuenta de dónde vino
			var origen = global_position - direccion_flecha.normalized() * 300.0
			entrar_estado_sospecha(origen)
			return
		caer_desmayado()

func despertarse():
	estado_actual = Estado.LEVANTANDOSE
	tiempo_desmayado = 0.0
	cambiar_icono_estado("")
	anim.play("empieza_a_levantarse")
	await anim.animation_finished
	anim.play("mira_izquierda_derecha_levantandose")
	await anim.animation_finished
	anim.play("se_levanta")
	await anim.animation_finished
	if estado_actual != Estado.LEVANTANDOSE:
		return
	if despertar_en_alerta:
		despertar_en_alerta = false
		var jugador = get_tree().get_first_node_in_group("jugador")
		punto_interes = jugador.global_position if jugador else null
		entrar_estado_alerta()
	else:
		entrar_estado_sospecha()

func recibir_orden_marcador(orden, tiempo, marcador = null):
	if estado_actual != Estado.PATRULLANDO:
		return
	if orden == 0:
		dar_vuelta()
	elif orden == 1:
		estado_actual = Estado.ESPERANDO_MARCADOR
		timer_marcador = tiempo
		orden_pendiente = 1
	elif orden == 2:
		estado_actual = Estado.ESPERANDO_MARCADOR
		timer_marcador = tiempo
		orden_pendiente = 2
	elif orden == 3:
		estado_actual = Estado.SALTANDO
		velocity.y = JUMP_VELOCITY
	elif orden == 4:
		estado_actual = Estado.CAYENDO_POR_AGUJERO
		orden_pendiente = 0
	elif orden == 5 or orden == 6:
		if marcador == null: return

		if randf() > 0.5:
			return

		estado_actual = Estado.EN_ESCALERA
		$CollisionShape2D.shape.size.x = 10.0
		tiempo_en_escalera = 0.0

		set_collision_mask_value(1, false)

		var colision_escalera = marcador.get_node("CollisionShape2D")
		global_position.x = colision_escalera.global_position.x
		var centro_real_y = colision_escalera.global_position.y

		if global_position.y < centro_real_y:
			direccion_escalera = 1
		else:
			direccion_escalera = -1

func check_ledge_grab():
	if is_on_wall() and wall_check.is_colliding() and not floor_check.is_colliding() and velocity.y >= 0:
		ejecutar_trepada()

func ejecutar_trepada():
	estado_actual = Estado.TREPANDO
	velocity = Vector2.ZERO
	$CollisionShape2D.set_deferred("disabled", true)
	anim.offset.y = 2
	anim.offset.x = 0
	reproducir_animacion("trepa_esquina")
	anim.frame = 0

func soltar_escalera():
	if estado_actual == Estado.EN_ESCALERA and tiempo_en_escalera > 0.1:
		set_collision_mask_value(1, true)
		$CollisionShape2D.shape.size.x = ancho_colision_original

		if direccion_escalera == -1:
			estado_actual = Estado.SALTANDO
			velocity.y = JUMP_VELOCITY * 0.7
			position.y -= 4
		else:
			estado_actual = Estado.PATRULLANDO
			velocity.y = 0

func _on_animation_finished():
	var terminada = anim.animation

	if terminada == "trepa_esquina" or terminada == "trepa_esquina_sin_gorro":
		var empuje_x = 50 * direccion_x
		var subida_y = 0
		global_position += Vector2(empuje_x, subida_y)
		anim.offset.x = compensacion_sprite if (direccion_x < 0) else 0.0
		anim.offset.y = 0
		$CollisionShape2D.set_deferred("disabled", false)
		estado_actual = Estado.PATRULLANDO

# --- DEBUG (F1): cono de visión según el estado ---

func _draw():
	if not Ruido.mostrar_circulos or estado_actual in [Estado.MUERTO, Estado.DESMAYADO, Estado.AGARRADO]:
		return
	var color = Color(0.4, 1.0, 0.4, 0.15)
	if estado_actual == Estado.SOSPECHANDO:
		color = Color(1.0, 0.85, 0.2, 0.2)
	elif estado_actual == Estado.AGRESIVO:
		color = Color(1.0, 0.2, 0.2, 0.22)
	var puntos = PackedVector2Array()
	for p in cono_poligono.polygon:
		puntos.append(Vector2(p.x * $ConoVision.scale.x, p.y) + cono_poligono.position)
	draw_colored_polygon(puntos, color)
