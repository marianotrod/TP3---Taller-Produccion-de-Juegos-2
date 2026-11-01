extends "res://scripts/enemigo.gd"

# --- ENEMIGO CON ARCABUZ ---
# Patrulla, oye y busca igual que el enemigo melee. En alerta, si ve al jugador
# dentro del alcance, se detiene, apunta (con aviso visible) y dispara directo hacia él,
# en cualquier ángulo. Entre disparos tiene un tiempo de recarga.
# Si la pierde de vista mientras apunta, sigue apuntando un rato (MEMORIA_PUNTERIA)
# en vez de volver a empezar: correr de un lado a otro ya no alcanza para esquivarlo.

const ESCENA_BALA = preload("res://scripts/bala.gd")

@export var alcance_disparo = 800.0
@export var tiempo_apuntado = 1.0     # Demora antes de disparar
@export var tiempo_recarga = 2.5      # Cooldown entre disparos
const FRACCION_SEGUIMIENTO = 0.6      # Durante este tramo del apuntado sigue al jugador; después fija la dirección
const MEMORIA_PUNTERIA = 1.2          # Segundos que sigue apuntando después de perderla de vista

var timer_apuntado = -1.0
var timer_recarga = 0.0
var direccion_disparo = Vector2.RIGHT
var fogonazo = 0.0
var tiempo_sin_ver = 0.0

func _ready():
	super()
	add_to_group("tirador")

func _physics_process(delta):
	timer_recarga -= delta
	fogonazo = max(0.0, fogonazo - delta)
	tiempo_sin_ver = 0.0 if viendo_jugador else tiempo_sin_ver + delta
	super(delta)

func comportamiento_agresivo(delta):
	var jugador = obtener_jugador()
	var sigue_apuntando = timer_apuntado >= 0.0 and tiempo_sin_ver < MEMORIA_PUNTERIA
	if jugador and not jugador.esta_muerto and (viendo_jugador or sigue_apuntando) and is_on_floor() and global_position.distance_to(jugador.global_position) <= alcance_disparo:
		velocity.x = 0
		limpiar_ruta()
		mirar_hacia(jugador.global_position.x)
		if timer_apuntado < 0.0:
			if timer_recarga > 0.0:
				return
			timer_apuntado = tiempo_apuntado
			Sonido.reproducir("apuntar", global_position)
		if timer_apuntado > tiempo_apuntado * (1.0 - FRACCION_SEGUIMIENTO):
			direccion_disparo = direccion_hacia(jugador)
		timer_apuntado -= delta
		if timer_apuntado <= 0.0:
			disparar()
		return
	# Fuera de alcance o sin verlo: se comporta como el enemigo común (persigue o busca)
	timer_apuntado = -1.0
	super(delta)

func boca_del_arma():
	return global_position + Vector2(direccion_x * 34.0, 8.0)

func direccion_hacia(jugador):
	# Apunta directo al cuerpo, en cualquier ángulo
	return (jugador.global_position + Vector2(0, 10) - boca_del_arma()).normalized()

func disparar():
	timer_apuntado = -1.0
	timer_recarga = tiempo_recarga
	fogonazo = 0.12
	var bala = Node2D.new()
	bala.set_script(ESCENA_BALA)
	bala.direccion = direccion_disparo
	get_parent().add_child(bala)
	bala.global_position = boca_del_arma() + direccion_disparo * 10.0
	Sonido.reproducir("disparo", global_position)
	Ruido.emitir(global_position, "disparo", self)

func recibir_dano(atacante_x = null, arma = "cuchillo", golpe_final = false):
	timer_apuntado = -1.0
	super(atacante_x, arma, golpe_final)

func recibir_flechazo(tipo_flecha, direccion_flecha = Vector2.ZERO):
	timer_apuntado = -1.0
	super(tipo_flecha, direccion_flecha)

func actualizar_animaciones():
	super()
	if timer_apuntado >= 0.0 and estado_actual == Estado.AGRESIVO and not esta_herido:
		reproducir_animacion("idle")

func _draw():
	super()
	var boca = boca_del_arma() - global_position
	# Aviso de disparo: línea de mira que se intensifica
	if timer_apuntado >= 0.0 and estado_actual == Estado.AGRESIVO:
		var progreso = 1.0 - timer_apuntado / tiempo_apuntado
		var fijo = timer_apuntado <= tiempo_apuntado * (1.0 - FRACCION_SEGUIMIENTO)
		var color = Color(1.0, 0.15, 0.1, 0.25 + 0.6 * progreso) if fijo else Color(1.0, 0.6, 0.2, 0.2 + 0.4 * progreso)
		draw_line(boca, boca + direccion_disparo * alcance_disparo, color, 2.0 + 2.0 * progreso)
	if fogonazo > 0.0:
		draw_circle(boca + direccion_disparo * 14.0, 14.0, Color(1.0, 0.9, 0.5, 0.9))

func aplicar_cono():
	# En alerta el tirador abarca más ángulo para poder disparar en diagonal
	if estado_actual == Estado.AGRESIVO:
		cono_poligono.set_deferred("polygon", PackedVector2Array([Vector2(0, -10), Vector2(700, -480), Vector2(700, 420)]))
	else:
		super()
