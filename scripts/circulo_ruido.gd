extends Node2D

# Onda que muestra el alcance de un ruido y se desvanece

var radio = 300.0
var tiempo = 0.0
const DURACION = 0.6

func _ready():
	z_index = 40

func _process(delta):
	tiempo += delta
	if tiempo >= DURACION:
		queue_free()
	queue_redraw()

func _draw():
	var t = tiempo / DURACION
	var color = Color(1.0, 0.9, 0.4, 0.25 * (1.0 - t))
	draw_arc(Vector2.ZERO, radio * (0.6 + 0.4 * t), 0, TAU, 48, color, 3.0)
