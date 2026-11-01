extends CanvasLayer

# Pantalla de título sobre el nivel: el mundo ya corre (los guardias patrullan) pero la
# cazadora todavía no está. Al tocar una tecla el cartel sale por abajo y ella cae desde
# arriba de la pantalla a la rama donde arranca.

const ALTURA_CAIDA = 260.0       # Arranca fuera de pantalla; menos que una caída mortal
const DEMORA_ENTRADA = 0.4       # Ignora teclas apenas carga el nivel
const DURACION_SALIDA = 0.9
const DEMORA_CAIDA = 0.35        # Cuándo empieza a caer, mientras el cartel se va

# Se muestra solo al abrir el juego; al reintentar (recarga de escena) no vuelve a aparecer
static var ya_mostrado = false

@onready var contenedor = $Contenedor
@onready var texto = $Contenedor/Texto

var jugador = null
var esperando = false
var tiempo = 0.0

func _ready():
	add_to_group("musica_pausa")
	jugador = get_tree().get_first_node_in_group("jugador")
	if ya_mostrado or jugador == null or _corriendo_pruebas():
		queue_free()
		return
	# El jugador queda arriba, fuera de cuadro, quieto e invisible hasta que empiece
	jugador.global_position.y -= ALTURA_CAIDA
	jugador.set_physics_process(false)
	jugador.set_process(false)
	jugador.hide()
	jugador.get_node("Interfaz").hide()
	await get_tree().create_timer(DEMORA_ENTRADA).timeout
	esperando = true

func _process(delta):
	tiempo += delta
	texto.modulate.a = 0.6 + 0.4 * sin(tiempo * 4.0)

func _input(event):
	if not esperando:
		return
	var es_tecla = event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton
	if es_tecla and event.pressed and not event.is_echo():
		get_viewport().set_input_as_handled()
		comenzar()

func comenzar():
	esperando = false
	ya_mostrado = true
	var alto_pantalla = get_viewport().get_visible_rect().size.y
	var tween = create_tween()
	tween.tween_property(contenedor, "position:y", alto_pantalla + 100.0, DURACION_SALIDA) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(DEMORA_CAIDA).timeout
	soltar_jugador()
	await tween.finished
	queue_free()

func soltar_jugador():
	jugador.velocity = Vector2.ZERO
	jugador.show()
	jugador.get_node("Interfaz").show()
	jugador.set_physics_process(true)
	jugador.set_process(true)

func _corriendo_pruebas():
	# Las pruebas automáticas (pruebas/probe.tscn) arrancan directo, salvo que pidan el título
	var args = OS.get_cmdline_user_args()
	if "con_titulo" in args:
		return false
	for arg in args:
		if arg.begins_with("tester="):
			return true
	return false
