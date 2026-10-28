extends Area2D

var velocity = Vector2.ZERO
var gravedad = ProjectSettings.get_setting("physics/2d/default_gravity")
var tipo = "letal"
var clavada = false

@onready var anim = $AnimatedSprite2D

func _ready():
	anim.play(tipo)
	rotation = velocity.angle()

func _physics_process(delta):
	if clavada:
		return

	velocity.y += gravedad * delta
	var avance = velocity * delta

	# Tiramos un rayo matemático un frame hacia adelante para ver si vamos a chocar
	var espacio = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position, global_position + avance)
	query.exclude = [get_rid()]
	# Usa la misma máscara de colisión que le configuraste al nodo en el Inspector
	query.collision_mask = collision_mask

	var choque = espacio.intersect_ray(query)

	if choque:
		# Si detecta impacto, teletransporta la flecha EXACTAMENTE al borde exterior del choque
		global_position = choque.position

		var cuerpo = choque.collider
		if cuerpo.is_in_group("jugador"):
			# Ignoramos al jugador para que no se dispare a sí misma
			position += avance
		elif cuerpo.is_in_group("enemigo"):
			if cuerpo.has_method("recibir_flechazo"):
				cuerpo.recibir_flechazo(tipo, velocity)
			# La letal es ruidosa al impactar; la sedante es silenciosa contra enemigos
			if tipo == "letal":
				Ruido.emitir(global_position, "flecha_impacto", cuerpo)
			Sonido.reproducir("flecha_carne", global_position)
			queue_free()
		else:
			Ruido.emitir(global_position, "flecha_impacto")
			Sonido.reproducir("flecha_impacto", global_position)
			clavar_flecha()
	else:
		# Si el camino está libre, avanzamos normal
		position += avance
		rotation = velocity.angle()

func clavar_flecha():
	clavada = true
	set_physics_process(false)
	$CollisionShape2D.set_deferred("disabled", true)

	await get_tree().create_timer(1.5).timeout
	queue_free()
