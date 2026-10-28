extends Node

# --- SISTEMA DE RUIDO ---
# Cualquier acción ruidosa llama a Ruido.emitir(posicion, radio).
# Los enemigos dentro del radio reciben oir_ruido() y reaccionan.
# F1 muestra/oculta los círculos de ruido (útil para ajustar radios).

const RADIO = {
	"paso_combate": 260.0,
	"aterrizaje": 300.0,
	"caida_fuerte": 500.0,
	"ataque": 380.0,
	"matar_rehen": 420.0,
	"arrojar_rehen": 350.0,
	"atraer": 520.0,
	"flecha_impacto": 300.0,
	"distraccion": 480.0,
	"humo": 350.0,
}

var mostrar_circulos = true
var _f1_previo = false

func _process(_delta):
	var f1 = Input.is_physical_key_pressed(KEY_F1)
	if f1 and not _f1_previo:
		mostrar_circulos = not mostrar_circulos
	_f1_previo = f1

func emitir(posicion: Vector2, radio, fuente = null):
	if radio is String:
		radio = RADIO.get(radio, 300.0)
	for enemigo in get_tree().get_nodes_in_group("enemigo"):
		if enemigo == fuente or not enemigo.has_method("oir_ruido"):
			continue
		if enemigo.global_position.distance_to(posicion) <= radio:
			enemigo.oir_ruido(posicion, radio)
	if mostrar_circulos:
		_dibujar_circulo(posicion, radio)

func _dibujar_circulo(posicion, radio):
	var escena = get_tree().current_scene
	if escena == null or not escena is Node2D:
		return
	var circulo = Node2D.new()
	circulo.set_script(preload("res://scripts/circulo_ruido.gd"))
	circulo.radio = radio
	circulo.global_position = posicion
	escena.add_child(circulo)
