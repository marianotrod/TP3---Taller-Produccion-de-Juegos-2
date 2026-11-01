extends Area2D

@onready var popup_boton = $PopupBoton
@onready var menu_interfaz = $CapaMenu/MenuInterfaz

var jugador_cerca = false

func _ready():
	popup_boton.hide()
	popup_boton.stop()
	menu_interfaz.hide()
	menu_interfaz.add_to_group("musica_pausa")
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta):
	if jugador_cerca and Input.is_action_just_pressed("saltar"):
		menu_interfaz.visible = not menu_interfaz.visible
		# Si tenés el shader en un nodo de pantalla completa:
		var crt = get_tree().current_scene.get_node_or_null("EfectoCRT") # Ajustá el nombre de tu nodo CRT
		if crt:
			crt.visible = not menu_interfaz.visible

func _on_body_entered(body):
	if body.is_in_group("jugador"):
		jugador_cerca = true
		popup_boton.show()
		popup_boton.play()
		# Le aplicamos el seguro al personaje para que no pueda saltar
		if "en_zona_interactiva" in body:
			body.en_zona_interactiva = true

func _on_body_exited(body):
	if body.is_in_group("jugador"):
		jugador_cerca = false
		popup_boton.hide()
		popup_boton.stop()
		menu_interfaz.hide()
		# Le sacamos el seguro cuando se aleja
		if "en_zona_interactiva" in body:
			body.en_zona_interactiva = false
