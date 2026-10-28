extends Area2D

@export_enum("Solo Dar Vuelta", "Frenar y Seguir", "Frenar y Dar Vuelta", "Saltar Obstaculo", "Caer al Vacio", "Subir Escalera", "Bajar Escalera") var orden: int = 0
@export var tiempo_de_espera: float = 2.0

func _ready():
	hide()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func _on_body_entered(body):
	if body.is_in_group("enemigo") and body.has_method("recibir_orden_marcador"):
		body.recibir_orden_marcador(orden, tiempo_de_espera, self)
		
	# --- NUEVO: Detecta al jugador ---
	elif body.is_in_group("jugador") and body.has_method("entrar_zona_escalera"):
		body.entrar_zona_escalera(self.global_position.x)

func _on_body_exited(body):
	if orden == 5 or orden == 6:
		if body.is_in_group("enemigo") and body.has_method("soltar_escalera"):
			body.soltar_escalera()
			
	# --- NUEVO: Detecta si el jugador se alejó ---
	if body.is_in_group("jugador") and body.has_method("salir_zona_escalera"):
		body.salir_zona_escalera()
