extends Node2D

# Bala del enemigo con arcabuz. Viaja en línea recta, choca con el mundo (capa 1)
# y con el jugador (capa 2). No toca la capa 4, así que no puede cortar la soga del puente.

const VELOCIDAD = 1100.0
const VIDA = 2.5
const MASCARA = 1 | 2

var direccion = Vector2.RIGHT
var tiempo = 0.0

func _ready():
	z_index = 6
	rotation = direccion.angle()

func _physics_process(delta):
	tiempo += delta
	if tiempo > VIDA:
		queue_free()
		return
	var avance = direccion * VELOCIDAD * delta
	var espacio = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position, global_position + avance, MASCARA)
	var choque = espacio.intersect_ray(query)
	if choque:
		global_position = choque.position
		var cuerpo = choque.collider
		if cuerpo.is_in_group("jugador"):
			if cuerpo.has_method("morir"):
				cuerpo.morir("Te alcanzó un disparo de arcabuz.", global_position - direccion * 40.0, "bala_impacto")
		else:
			Sonido.reproducir("bala_impacto", global_position)
		queue_free()
		return
	position += avance

func _draw():
	draw_line(Vector2(-22, 0), Vector2(0, 0), Color(1.0, 0.85, 0.4, 0.5), 3.0)
	draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.95, 0.7))
