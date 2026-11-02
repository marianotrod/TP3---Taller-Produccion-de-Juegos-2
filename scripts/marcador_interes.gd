extends Node2D

# Marca el último lugar donde un enemigo vio al jugador.
# El enemigo que lo dejó va a revisarlo (si puede llegar) y después lo quita.
# Se dibuja solo con la depuración visual activa (F1).

var tiempo = 0.0

func _ready():
	z_index = 45

func _process(delta):
	tiempo += delta
	queue_redraw()

func _draw():
	if not Ruido.mostrar_depuracion:
		return
	var pulso = 0.6 + 0.4 * sin(tiempo * 5.0)
	var color = Color(1.0, 0.75, 0.15, 0.9 * pulso)
	draw_arc(Vector2(0, 64), 26.0, 0, TAU, 24, color, 3.0)
	draw_line(Vector2(0, 64), Vector2(0, -10), color, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(-9, -16), "?", HORIZONTAL_ALIGNMENT_CENTER, -1, 36, color)
