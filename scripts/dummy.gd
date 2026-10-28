extends CharacterBody2D

@onready var anim = $AnimatedSprite2D
@onready var colision = $CollisionShape2D

enum Estado { IDLE, AGARRADO, RECUPERANDO }
var estado_actual = Estado.IDLE
var tiempo_revivir = 3.0 # Segundos que tarda en volver a pararse

func _ready():
	add_to_group("enemigo") # Crucial para que el jugador y las flechas lo reconozcan
	anim.play("idle")

func _physics_process(delta):
	# Le aplicamos gravedad para que caiga al piso si lo arrojás o lo soltás en el aire
	if not is_on_floor() and estado_actual != Estado.AGARRADO:
		velocity.y += ProjectSettings.get_setting("physics/2d/default_gravity") * delta
		move_and_slide()

# --- SISTEMA DE DAÑO Y FLECHAS ---
func recibir_dano(_atacante_x = null, _arma = null, _golpe_final = false):
	if estado_actual == Estado.RECUPERANDO: return
	
	estado_actual = Estado.RECUPERANDO
	anim.play("recibe_daño") 
	revivir_despues_de_un_rato()

func recibir_flechazo(tipo_flecha, _direccion = Vector2.ZERO):
	if estado_actual == Estado.RECUPERANDO: return
	
	estado_actual = Estado.RECUPERANDO
	if tipo_flecha == "letal":
		anim.play("muerto") # O la animación que tengas
	else:
		anim.play("desmayado")
		
	revivir_despues_de_un_rato()

# --- SISTEMA DE AGARRE (CQC) ---
func puede_recibir_takedown(player_x):
	# Solo se deja agarrar si está parado haciendo nada
	return estado_actual == Estado.IDLE

func ser_agarrado():
	estado_actual = Estado.AGARRADO
	# Desactivamos su colisión para que no trabe al jugador al caminar hacia atrás
	colision.set_deferred("disabled", true) 
	anim.play("agarrado") 

func soltar_agarre():
	estado_actual = Estado.RECUPERANDO
	colision.set_deferred("disabled", false)
	anim.play("desmayado") 
	revivir_despues_de_un_rato()

func ser_neutralizado():
	estado_actual = Estado.RECUPERANDO
	colision.set_deferred("disabled", false)
	anim.play("muerto") # Reacción a cuando lo ejecutás estando agarrado
	revivir_despues_de_un_rato()

# --- LÓGICA DE RESURRECCIÓN ---
func revivir_despues_de_un_rato():
	# Frena el código de esta función durante 'tiempo_revivir' segundos
	await get_tree().create_timer(tiempo_revivir).timeout
	
	# Si sigue existiendo, lo resetea a estado base
	estado_actual = Estado.IDLE
	anim.play("idle")
