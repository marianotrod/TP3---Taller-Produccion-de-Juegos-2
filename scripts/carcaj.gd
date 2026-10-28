extends Area2D

# Carcaj recogible: suma flechas al inventario del jugador

@export_enum("letal", "desmayante") var tipo: String = "letal"
@export var cantidad: int = 5

var tiempo = 0.0

func _ready():
	body_entered.connect(_on_body_entered)

func _process(delta):
	tiempo += delta
	queue_redraw()

func _on_body_entered(body):
	if body.is_in_group("jugador") and body.has_method("recoger_flechas"):
		body.recoger_flechas(tipo, cantidad)
		queue_free()

func _draw():
	var flotar = Vector2(0, sin(tiempo * 3.0) * 4.0)
	var punta = Color(0.85, 0.2, 0.15) if tipo == "letal" else Color(0.3, 0.75, 0.95)
	# Flechas asomando
	for i in range(3):
		var x = -8.0 + i * 8.0
		draw_line(Vector2(x, -10) + flotar, Vector2(x, -34) + flotar, Color(0.85, 0.78, 0.6), 3.0)
		draw_rect(Rect2(Vector2(x - 3, -40) + flotar, Vector2(6, 7)), punta)
	# Cuerpo del carcaj
	draw_rect(Rect2(Vector2(-14, -12) + flotar, Vector2(28, 40)), Color(0.45, 0.28, 0.14))
	draw_rect(Rect2(Vector2(-14, -12) + flotar, Vector2(28, 6)), Color(0.3, 0.18, 0.08))
	draw_rect(Rect2(Vector2(-14, 14) + flotar, Vector2(28, 4)), punta)
