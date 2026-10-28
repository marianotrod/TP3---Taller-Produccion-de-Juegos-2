extends Node2D

# Objeto arrojable (piedra de distracción o bomba de humo).
# Usa la misma gravedad que la parábola de apuntado del personaje.

const GRAVEDAD = 1800.0
const ESCENA_HUMO = preload("res://scripts/nube_humo.gd")

var velocity = Vector2.ZERO
var tipo = "distraccion"
var detenido = false

func _ready():
	z_index = 5

func _physics_process(delta):
	if detenido:
		return
	velocity.y += GRAVEDAD * delta
	var avance = velocity * delta
	var espacio = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position, global_position + avance, 1)
	var choque = espacio.intersect_ray(query)
	if choque:
		global_position = choque.position - avance.normalized() * 4.0
		impactar()
	else:
		position += avance
		rotation += 12.0 * delta

func impactar():
	detenido = true
	if tipo == "humo":
		var nube = Node2D.new()
		nube.set_script(ESCENA_HUMO)
		get_parent().add_child(nube)
		nube.global_position = global_position + Vector2(0, -40)
		Ruido.emitir(global_position, "humo")
		Sonido.reproducir("humo", global_position)
		queue_free()
		return
	Ruido.emitir(global_position, "distraccion")
	Sonido.reproducir("piedra", global_position)
	await get_tree().create_timer(2.0).timeout
	queue_free()

func _draw():
	if tipo == "humo":
		draw_circle(Vector2.ZERO, 9.0, Color(0.18, 0.22, 0.16))
		draw_rect(Rect2(-3, -14, 6, 6), Color(0.5, 0.45, 0.3))
	else:
		draw_circle(Vector2.ZERO, 8.0, Color(0.42, 0.38, 0.33))
		draw_circle(Vector2(-2, -2), 3.0, Color(0.58, 0.54, 0.48))
