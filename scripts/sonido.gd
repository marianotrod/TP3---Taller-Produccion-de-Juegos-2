extends Node

# --- EFECTOS DE SONIDO ---
# Sonido.reproducir("nombre", posicion) busca res://assets/sonidos/nombre.wav
# (y variantes nombre_2.wav, nombre_3.wav... elegidas al azar).
# Sin posición suena como sonido de interfaz (no posicional).

const CARPETA = "res://assets/sonidos/"
var cache = {}

func _variantes(nombre):
	if cache.has(nombre):
		return cache[nombre]
	var lista = []
	var base = CARPETA + nombre + ".wav"
	if ResourceLoader.exists(base):
		lista.append(load(base))
	var i = 2
	while ResourceLoader.exists(CARPETA + "%s_%d.wav" % [nombre, i]):
		lista.append(load(CARPETA + "%s_%d.wav" % [nombre, i]))
		i += 1
	cache[nombre] = lista
	return lista

func reproducir(nombre, posicion = null, volumen_db = 0.0):
	var variantes = _variantes(nombre)
	if variantes.is_empty():
		return
	var escena = get_tree().current_scene
	if escena == null:
		return
	var reproductor
	if posicion == null:
		reproductor = AudioStreamPlayer.new()
	else:
		reproductor = AudioStreamPlayer2D.new()
		reproductor.max_distance = 2200.0
		reproductor.attenuation = 1.5
	reproductor.stream = variantes.pick_random()
	reproductor.volume_db = volumen_db
	reproductor.pitch_scale = randf_range(0.94, 1.06)
	reproductor.process_mode = Node.PROCESS_MODE_ALWAYS
	reproductor.finished.connect(reproductor.queue_free)
	escena.add_child(reproductor)
	if posicion != null:
		reproductor.global_position = posicion
	reproductor.play()
