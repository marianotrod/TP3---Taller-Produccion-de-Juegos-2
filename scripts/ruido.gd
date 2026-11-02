extends Node

# --- SISTEMA DE RUIDO ---
# Cualquier acción ruidosa llama a Ruido.emitir(posicion, radio).
# Los enemigos dentro del radio reciben oir_ruido() y reaccionan.
# Los círculos de ruido son parte del juego: muestran qué tan lejos se oyó cada acción.
# F1 (en mundo.gd) muestra/oculta la depuración: conos de visión y marcadores de los guardias.

const RADIO = {
	"paso_combate": 260.0,
	"aterrizaje": 300.0,
	"caida_fuerte": 500.0,
	"ataque": 380.0,          # Solo si el golpe pega en un guardia
	"golpe_pared": 250.0,
	"trepada_rapida": 220.0,
	"wall_run": 200.0,
	"matar_rehen": 420.0,
	"arrojar_rehen": 350.0,
	"atraer": 520.0,
	"flecha_impacto": 300.0,
	"distraccion": 480.0,
	"humo": 350.0,
	"disparo": 700.0,
}

var mostrar_circulos = true      # Siempre activos (las pruebas los apagan)
var mostrar_depuracion = false   # Conos de visión y marcadores de interés (F1)

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
