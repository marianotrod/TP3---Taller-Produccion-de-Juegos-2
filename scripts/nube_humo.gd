extends Node2D

# Nube de humo: oculta al jugador aunque no esté en sigilo, corta la línea de
# visión de los enemigos y tapa parcialmente lo que hay detrás.

const DURACION = 8.0
const EXPANSION = 0.5
const DESPEJE = 1.5
const RADIO_MAX = 190.0

var radio = 0.0
var tiempo = 0.0
var bolas = []

func _ready():
	add_to_group("humo")
	z_index = 30
	for i in range(14):
		var angulo = randf() * TAU
		var distancia = randf() * 0.7
		bolas.append({
			"pos": Vector2(cos(angulo), sin(angulo) * 0.7) * distancia,
			"tam": randf_range(0.35, 0.55),
			"fase": randf() * TAU,
		})

func _process(delta):
	tiempo += delta
	if tiempo < EXPANSION:
		radio = RADIO_MAX * ease(tiempo / EXPANSION, 0.4)
	elif tiempo > DURACION - DESPEJE:
		radio = RADIO_MAX * clamp((DURACION - tiempo) / DESPEJE, 0.0, 1.0)
	else:
		radio = RADIO_MAX
	if tiempo >= DURACION:
		queue_free()
	queue_redraw()

func _draw():
	var alfa = 0.75 if tiempo < DURACION - DESPEJE else 0.75 * clamp((DURACION - tiempo) / DESPEJE, 0.0, 1.0)
	for b in bolas:
		var oscilacion = Vector2(sin(tiempo * 0.8 + b.fase), cos(tiempo * 0.6 + b.fase)) * 8.0
		draw_circle(b.pos * radio + oscilacion, radio * b.tam, Color(0.72, 0.74, 0.7, alfa * 0.55))
