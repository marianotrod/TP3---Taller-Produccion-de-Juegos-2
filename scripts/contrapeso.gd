extends StaticBody2D

func _ready():
	add_to_group("enemigo")

# Lo llama el cuchillo
func recibir_dano(_atacante_x = null, _arma = null, _golpe_final = false):
	owner.caer_puente()

# Lo llama la flecha
func recibir_flechazo(_tipo_flecha, _direccion = Vector2.ZERO):
	owner.caer_puente()
