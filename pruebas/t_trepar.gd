extends Node

# Cornisas, carrera por la pared (experimental), ruido de aterrizaje y de golpes.
# Arma su propio escenario (piso y paredes de 1.5, 2 y 3 tiles) arriba del nivel.
# Uso: godot --headless --path . res://pruebas/probe.tscn -- tester=res://pruebas/t_trepar.gd

const TILE = 128.0
const PISO_Y = -2000.0     # Arriba del nivel: ahí no hay nada
const X0 = 4000.0

var fallas = 0
var j

func check(cond, texto):
	print(("OK    " if cond else "FALLA ") + texto)
	if not cond:
		fallas += 1

func cuadros(n):
	for i in range(n):
		await get_tree().physics_frame

func tocar(accion):
	Input.action_press(accion)
	await cuadros(1)
	Input.action_release(accion)
	await cuadros(1)

func bloque(x, y, ancho, alto):
	var cuerpo = StaticBody2D.new()
	var forma = CollisionShape2D.new()
	forma.shape = RectangleShape2D.new()
	forma.shape.size = Vector2(ancho, alto)
	cuerpo.add_child(forma)
	get_tree().current_scene.add_child(cuerpo)
	cuerpo.global_position = Vector2(x + ancho / 2.0, y + alto / 2.0)

func circulos():
	var radios = []
	for n in get_tree().current_scene.get_children():
		if n.get("radio") != null and n.get_script() == preload("res://scripts/circulo_ruido.gd"):
			radios.append(n.radio)
			n.queue_free()
	return radios

func soltar_todo():
	for a in ["mover_der", "mover_izq", "arriba", "abajo", "saltar"]:
		Input.action_release(a)

func parar_frente_a(pared_x):
	soltar_todo()
	j.is_hanging = false
	j.accion_bloqueante = false
	j.es_sigilo = false
	j.facing_left = false
	j.velocity = Vector2.ZERO
	j.global_position = Vector2(pared_x - 60, PISO_Y - 64)
	await cuadros(10)
	circulos()

# Salta contra la pared empujando hacia ella; si soltar_al_colgar, suelta todo al agarrarse
func saltar_contra_pared(soltar_al_colgar):
	Input.action_press("mover_der")
	await cuadros(2)
	Input.action_press("saltar")
	for i in range(90):
		await cuadros(1)
		if soltar_al_colgar and i == 12:
			Input.action_release("mover_der")   # Ya contra la pared: suelta la palanca para quedar colgada sin trepar
		if j.is_hanging and soltar_al_colgar:
			soltar_todo()
			await cuadros(2)
			return true
		if j.is_hanging or j.accion_bloqueante:
			break
	return j.is_hanging or j.accion_bloqueante

func esperar_trepada():
	var n = 0
	while (j.accion_bloqueante or j.is_hanging) and n < 200:
		await cuadros(1)
		n += 1
	soltar_todo()
	await cuadros(10)
	return n

func _ready():
	while not Navegacion.listo or get_tree().current_scene == null or get_tree().current_scene.name == "Probe":
		await get_tree().process_frame
	j = get_tree().get_first_node_in_group("jugador")
	Ruido.mostrar_circulos = true
	# Escenario: piso largo y tres paredes
	bloque(X0 - 400, PISO_Y, 4000, 200)
	var paredes = {"1.5": X0, "2": X0 + 1000, "3": X0 + 2000}
	var alturas = {"1.5": 1.5, "2": 2.0, "3": 3.0}
	for k in paredes:
		bloque(paredes[k], PISO_Y - alturas[k] * TILE, 300, alturas[k] * TILE)
	await cuadros(5)

	# --- Colgada de una cornisa de 1.5 tiles ---
	var pared = paredes["1.5"]
	var tope = PISO_Y - 1.5 * TILE
	await parar_frente_a(pared)
	check(await saltar_contra_pared(true), "1.5 tiles: se agarra de la cornisa")
	var colgada = j.global_position
	Input.action_press("mover_izq")
	await cuadros(30)
	Input.action_release("mover_izq")
	await cuadros(2)
	check(j.is_hanging and j.global_position.distance_to(colgada) < 2.0 and not j.accion_bloqueante, "colgada, hacia atrás no hace nada (sin tirón)")
	var sigilo_antes = j.es_sigilo
	await tocar("cambiar_postura")
	await cuadros(40)
	check(not j.is_hanging and j.is_on_floor() and j.global_position.y > colgada.y + 30, "B la suelta y cae al piso")
	check(j.es_sigilo == sigilo_antes, "B colgada no cambia la postura")
	var radios = circulos()
	print("   ruido al soltarse y caer: ", radios)
	check(radios.is_empty() or radios.max() < 200, "caer de la cornisa hace poco ruido")

	# Trepada lenta (hacia la pared) y rápida (saltar)
	await parar_frente_a(pared)
	await saltar_contra_pared(true)
	Input.action_press("arriba")
	var lenta = await esperar_trepada()
	check(abs(j.global_position.y + 64 - tope) < 6 and j.global_position.x > pared, "arriba: trepa y queda sobre la pared")
	var ruido_lenta = circulos()
	await parar_frente_a(pared)
	await saltar_contra_pared(true)
	await cuadros(5)
	circulos()
	Input.action_press("saltar")
	var rapida = await esperar_trepada()
	var ruido_rapida = circulos()
	print("   trepada lenta %d cuadros, ruido %s; rápida %d cuadros, ruido %s" % [lenta, ruido_lenta, rapida, ruido_rapida])
	check(abs(j.global_position.y + 64 - tope) < 6 and j.global_position.x > pared, "saltar: trepa y queda sobre la pared")
	check(rapida < lenta * 0.7, "saltar trepa más rápido")
	check(ruido_lenta.is_empty(), "trepar normal es silencioso")
	check(not ruido_rapida.is_empty(), "trepar rápido hace ruido")

	# Empujando hacia la pared desde el salto: se agarra y trepa sola
	await parar_frente_a(pared)
	await saltar_contra_pared(false)
	await esperar_trepada()
	check(abs(j.global_position.y + 64 - tope) < 6, "manteniendo hacia la pared sube de corrido")

	# --- 1 tile: se sube saltando sin trepar ---
	bloque(X0 + 3000, PISO_Y - TILE, 300, TILE)
	await parar_frente_a(X0 + 3000)
	Input.action_press("mover_der")
	Input.action_press("saltar")
	var trepo_1 = false
	for i in range(60):
		await cuadros(1)
		if j.is_hanging or (j.accion_bloqueante and j.anim.animation == "trepa"):
			trepo_1 = true
	soltar_todo()
	await cuadros(20)
	check(abs(j.global_position.y + 64 - (PISO_Y - TILE)) < 6, "1 tile: queda arriba")
	print("   1 tile: usó la cornisa: ", trepo_1)

	# --- 2 tiles: carrera por la pared y trepada ---
	await parar_frente_a(paredes["2"])
	var corrio = false
	var se_colgo = false
	var ruido_carrera = []
	Input.action_press("mover_der")
	await cuadros(2)
	Input.action_press("saltar")
	for i in range(150):
		await cuadros(1)
		if j.timer_wall_run > 0.0:
			corrio = true
			ruido_carrera.append_array(circulos())
		if j.anim.animation == "trepa":
			se_colgo = true
		if se_colgo and not j.is_hanging and not j.accion_bloqueante and j.is_on_floor() and i > 20:
			break
	soltar_todo()
	await cuadros(10)
	check(corrio, "2 tiles: corre por la pared")
	check(se_colgo, "2 tiles: se cuelga del borde y trepa (no lo pasa de largo)")
	print("   ruido de la carrera: ", ruido_carrera)
	check(not ruido_carrera.is_empty(), "la carrera por la pared hace un poco de ruido")
	check(abs(j.global_position.y + 64 - (PISO_Y - 2 * TILE)) < 6, "2 tiles: llega arriba (y %.0f)" % j.global_position.y)

	# --- 3 tiles: no llega ---
	await parar_frente_a(paredes["3"])
	Input.action_press("mover_der")
	await cuadros(2)
	Input.action_press("saltar")
	await cuadros(120)
	soltar_todo()
	await cuadros(20)
	check(j.global_position.y + 64 > PISO_Y - 10, "3 tiles: no llega (pies %.0f, piso %.0f)" % [j.global_position.y + 64, PISO_Y])

	# --- Ramas finas: cayendo al lado, mirando hacia la rama, se cuelga (no queda parada en el aire) ---
	bloque(X0 + 2600, PISO_Y - 400, 200, 32)
	for caso in [["rama de prueba", Vector2(X0 + 2600 - 30, PISO_Y - 400 - 40)], ["rama del comienzo", Vector2(450, 268 - 40)]]:
		soltar_todo()
		j.is_hanging = false
		j.accion_bloqueante = false
		j.facing_left = false
		j.velocity = Vector2.ZERO
		j.global_position = caso[1]
		await cuadros(60)
		print("   %s: colgada %s, en piso %s, pos %s" % [caso[0], j.is_hanging, j.is_on_floor(), j.global_position])
		check(j.is_hanging, caso[0] + ": queda colgada del borde")
		# Vuelve al piso de prueba (soltarse de la rama real sería una caída mortal)
		j.is_hanging = false
		j.global_position = Vector2(X0 + 600, PISO_Y - 64)
		j.velocity = Vector2.ZERO
		await cuadros(20)

	# --- Ruido de aterrizaje según la altura ---
	var radios_por_altura = []
	for tiles in [1, 2, 3]:
		soltar_todo()
		j.velocity = Vector2.ZERO
		j.global_position = Vector2(X0 + 600, PISO_Y - 64 - tiles * TILE)
		j.estaba_en_suelo = true   # El teletransporte no es una caída desde donde estaba
		await cuadros(3)
		circulos()
		for i in range(90):
			await cuadros(1)
			if j.is_on_floor():
				break
		await cuadros(2)
		var r = circulos()
		radios_por_altura.append(r.max() if not r.is_empty() else 0.0)
	print("   radio por altura (1, 2, 3 tiles): ", radios_por_altura)
	check(radios_por_altura[0] > 0 and radios_por_altura[0] < 200, "caer 1 tile: círculo chico")
	check(radios_por_altura[0] < radios_por_altura[1] and radios_por_altura[1] < radios_por_altura[2], "más alto, más ruido")

	# --- Golpes: al aire no se oyen, contra la pared sí ---
	await parar_frente_a(X0 + 900)
	j.global_position.x = X0 + 500
	await cuadros(5)
	circulos()
	await tocar("atacar")
	await cuadros(3)   # Los círculos duran 0.6 s: mirarlos enseguida
	check(circulos().is_empty(), "golpe al aire: sin ruido")
	await cuadros(40)   # Que termine el combo antes del próximo golpe
	await parar_frente_a(paredes["2"])
	j.global_position.x = paredes["2"] - 30
	await cuadros(5)
	circulos()
	await tocar("atacar")
	print("   golpe contra la pared: combo %d, x %.0f, pared %.0f, bloqueada %s" % [j.combo_paso, j.global_position.x, paredes["2"], j.accion_bloqueante])
	await cuadros(3)
	check(not circulos().is_empty(), "golpe contra la pared: hace ruido")

	print("FALLAS: ", fallas)
	get_tree().quit()
