extends CanvasLayer

@onready var fondo_oscuro = $FondoOscuro
@onready var titulo = $Contenedor/Titulo
@onready var subtitulo = $Contenedor/Subtitulo
@onready var instruccion = $Contenedor/Instruccion

enum TipoMensaje { NINGUNO, MUERTE, FIN_DEMO }
var tipo_actual = TipoMensaje.NINGUNO
var puede_interactuar = false

func _ready():
	add_to_group("musica_pausa")
	hide()
	fondo_oscuro.modulate.a = 0.0

func _process(_delta):
	if puede_interactuar and Input.is_action_just_pressed("saltar"):
		match tipo_actual:
			TipoMensaje.MUERTE:
				get_tree().reload_current_scene()
			TipoMensaje.FIN_DEMO:
				get_tree().reload_current_scene()

# La variable "razon" recibe el texto desde personaje.gd
func mostrar_muerte(razon: String = "Fuiste neutralizado."):
	tipo_actual = TipoMensaje.MUERTE
	titulo.text = "CAÍSTE EN COMBATE"
	# Acá inyecta el texto personalizado ("La caída fue demasiado alta", "Te mató un enemigo", etc.)
	subtitulo.text = razon 
	instruccion.text = "Presiona X para reintentar"
	_animar_aparicion()

func mostrar_fin_demo():
	tipo_actual = TipoMensaje.FIN_DEMO
	titulo.text = "¡FELICITACIONES!"
	subtitulo.text = "Has completado la DEMO con éxito."
	instruccion.text = "Presiona X para reiniciar"
	_animar_aparicion()

func _animar_aparicion():
	show()
	var tween = create_tween()
	tween.tween_property(fondo_oscuro, "modulate:a", 1.0, 0.5)
	await tween.finished
	puede_interactuar = true
