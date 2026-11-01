extends Node

# --- MÚSICA ADAPTATIVA (autoload "Musica") ---
# Cada cuadro elige la pista que corresponde y hace un fundido cruzado:
#   pausa:      título, menús, juego en pausa o jugadora muerta
#   alerta:     algún guardia en alerta (persiguiendo, con el cono grande)
#   curiosidad: algún guardia sospechando (la vio o la escuchó y está buscando)
#   sigilo:     el resto del tiempo
# Un nodo visible en el grupo "musica_pausa" fuerza la música de pausa (título, menús, mensajes).
# Las pistas que se apagan quedan en pausa y al volver siguen desde donde iban.

const PISTAS = {
	"pausa": "res://assets/musica/MusicaPausa.mp3",
	"sigilo": "res://assets/musica/MusicaSigilo.mp3",
	"curiosidad": "res://assets/musica/MusicaCuriosidad.mp3",
	"alerta": "res://assets/musica/MusicaAlerta.mp3",
}
const VOLUMEN_DB = -8.0
const DURACION_FUNDIDO = 1.2      # Segundos reales
const PERMANENCIA_ALERTA = 3.0    # La música de alerta sigue un rato después de que se calman
const PERMANENCIA_CURIOSIDAD = 2.0

var reproductores = {}
var actual = ""
var timer_alerta = 0.0
var timer_curiosidad = 0.0
var ultimo_us = 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS   # Suena también con el juego en pausa
	for nombre in PISTAS:
		var reproductor = AudioStreamPlayer.new()
		reproductor.stream = load(PISTAS[nombre])
		reproductor.volume_db = -80.0
		add_child(reproductor)
		reproductores[nombre] = reproductor
	ultimo_us = Time.get_ticks_usec()

func _process(_delta):
	# Tiempo real: el delta se achica con la cámara lenta del carrusel o de un golpe
	var ahora = Time.get_ticks_usec()
	var dt = min((ahora - ultimo_us) / 1000000.0, 0.1)
	ultimo_us = ahora

	var deseada = elegir_pista(dt)
	if deseada != "" and deseada != actual:
		actual = deseada
		var reproductor = reproductores[actual]
		if not reproductor.playing:
			reproductor.play()
		reproductor.stream_paused = false

	var paso = dt / DURACION_FUNDIDO
	for nombre in reproductores:
		var reproductor = reproductores[nombre]
		if not reproductor.playing:
			continue
		var nivel = db_to_linear(reproductor.volume_db) / db_to_linear(VOLUMEN_DB)
		nivel = move_toward(nivel, 1.0 if nombre == actual else 0.0, paso)
		reproductor.volume_db = linear_to_db(max(nivel, 0.0001) * db_to_linear(VOLUMEN_DB))
		if nombre != actual and nivel <= 0.0001:
			reproductor.stream_paused = true

func elegir_pista(dt):
	var arbol = get_tree()
	if arbol.current_scene == null or not arbol.current_scene.is_in_group("nivel"):
		return ""
	if arbol.paused or hay_pantalla_de_pausa():
		return "pausa"
	var jugador = arbol.get_first_node_in_group("jugador")
	if jugador == null or jugador.esta_muerto:
		return "pausa"

	timer_alerta -= dt
	timer_curiosidad -= dt
	for guardia in arbol.get_nodes_in_group("enemigo"):
		if not "estado_actual" in guardia:
			continue
		if guardia.estado_actual == guardia.Estado.AGRESIVO:
			timer_alerta = PERMANENCIA_ALERTA
		elif guardia.estado_actual == guardia.Estado.SOSPECHANDO:
			timer_curiosidad = PERMANENCIA_CURIOSIDAD
	if timer_alerta > 0.0:
		return "alerta"
	if timer_curiosidad > 0.0:
		return "curiosidad"
	return "sigilo"

func hay_pantalla_de_pausa():
	for nodo in get_tree().get_nodes_in_group("musica_pausa"):
		if nodo is CanvasLayer and nodo.visible:
			return true
		if nodo is CanvasItem and nodo.is_visible_in_tree():
			return true
	return false
