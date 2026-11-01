extends Node

# Grabación determinística del comportamiento, para comparar antes y después de reorganizar código.
# Simula una secuencia fija de controles y eventos, y registra al jugador cada cuadro y a los
# guardias cada 10 cuadros. Dos grabaciones del mismo código tienen que salir idénticas.
#
# Uso:
#   godot --headless --fixed-fps 60 --path . res://pruebas/probe.tscn -- tester=res://pruebas/t_grabacion.gd salida=C:/ruta/grabacion.txt
#   python pruebas/comparar_grabaciones.py antes.txt despues.txt

const CUADROS = 3000

var cuadro = -1
var j = null
var lineas = PackedStringArray()
var salida = "user://grabacion.txt"
var eventos = {}   # cuadro -> Array de Callable

func enemigo(nombre):
	for n in get_tree().get_nodes_in_group("enemigo"):
		if n.name == nombre:
			return n

func en(c, f):
	if not eventos.has(c):
		eventos[c] = []
	eventos[c].append(f)

func tocar(c, accion):
	en(c, func(): Input.action_press(accion))
	en(c + 1, func(): Input.action_release(accion))

func mantener(desde, hasta, accion):
	en(desde, func(): Input.action_press(accion))
	en(hasta, func(): Input.action_release(accion))

func llevar(c, pos):
	en(c, func():
		j.set_physics_process(true)
		j.global_position = pos
		j.is_hanging = false
		j.velocity = Vector2.ZERO)

func guardar(c):
	# Saca a la jugadora del mapa sin que caiga
	en(c, func():
		j.set_physics_process(false)
		j.global_position = Vector2(-3000, -3000)
		j.velocity = Vector2.ZERO)

func _ready():
	process_physics_priority = -100
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("salida="):
			salida = arg.substr(7)
	while not Navegacion.listo or get_tree().current_scene == null or get_tree().current_scene.name == "Probe":
		await get_tree().process_frame
	seed(12345)
	Ruido.mostrar_circulos = false
	j = get_tree().get_first_node_in_group("jugador")
	armar_guion()
	cuadro = 0

func armar_guion():
	# --- Movimiento en la rama inicial ---
	mantener(20, 60, "mover_der")
	tocar(70, "saltar")
	mantener(70, 110, "mover_der")
	mantener(120, 160, "mover_izq")
	tocar(170, "cambiar_postura")             # sigilo
	mantener(175, 215, "mover_der")
	tocar(220, "cambiar_postura")             # vuelve a combate
	mantener(230, 270, "abajo")               # acostada
	mantener(240, 265, "mover_izq")
	mantener(280, 340, "mover_izq")           # cae de la rama
	# --- Rehén: agarrar por la espalda, caminar y matar ---
	en(400, func():
		var e = enemigo("enemigo6")
		e.volver_a_patrulla()
		e.terminar_vuelta()
		j.global_position = e.global_position - Vector2(30 * e.direccion_x, 0)
		j.velocity = Vector2.ZERO
		j.facing_left = e.direccion_x < 0
		j.es_sigilo = true)
	tocar(402, "agarre")
	mantener(420, 450, "mover_izq")
	tocar(460, "atacar")
	# --- Combo de puño por la espalda ---
	en(520, func():
		var e = enemigo("enemigo7")
		j.global_position = e.global_position - Vector2(30 * e.direccion_x, 0)
		j.velocity = Vector2.ZERO
		j.facing_left = e.direccion_x < 0
		j.es_sigilo = true)
	tocar(522, "atacar")
	tocar(527, "atacar")
	tocar(534, "atacar")
	tocar(560, "atacar")
	# --- Arco: tensar y disparar; tensar y cancelar ---
	llevar(600, Vector2(10600, 950))
	en(600, func(): j.es_sigilo = false)
	mantener(610, 700, "apuntar")
	mantener(620, 660, "disparar")
	mantener(710, 780, "apuntar")
	mantener(720, 790, "disparar")            # suelta apuntar antes: cancela
	# --- Piedra y humo ---
	en(800, func(): j.inventario.equipar_arma("distraccion"))
	mantener(805, 850, "apuntar")
	mantener(810, 840, "disparar")
	en(860, func(): j.inventario.equipar_arma("humo"))
	mantener(865, 910, "apuntar")
	mantener(870, 900, "disparar")
	# --- Golpes de cuchillo por la espalda ---
	en(950, func():
		j.inventario.equipar_objeto("cuchillo")
		var e = enemigo("enemigo8")
		j.global_position = e.global_position - Vector2(40 * e.direccion_x, 0)
		j.is_hanging = false
		j.velocity = Vector2.ZERO
		j.facing_left = e.direccion_x < 0)
	tocar(951, "atacar")
	tocar(956, "atacar")
	llevar(966, Vector2(12400, 950))
	# --- Escalera ---
	llevar(1050, Vector2(12957, 950))
	mantener(1055, 1200, "arriba")
	tocar(1210, "saltar")
	# --- Atraer ---
	llevar(1300, Vector2(15379 - 400, 950))
	tocar(1310, "atraer")
	guardar(1350)
	# --- Eventos directos sobre guardias ---
	en(1400, func():
		var e = enemigo("enemigo12")
		e.recibir_dano(e.global_position.x - 30, "cuchillo")
		e.recibir_dano(e.global_position.x - 30, "cuchillo"))
	en(1420, func(): enemigo("enemigo13").caer_desmayado())
	en(1430, func(): enemigo("tirador1").recibir_flechazo("desmayante", Vector2(1, 0)))
	en(1440, func(): enemigo("tirador1").recibir_flechazo("desmayante", Vector2(1, 0)))
	en(1450, func(): Ruido.emitir(Vector2(19800, 1024), "atraer", null))
	en(1460, func(): enemigo("enemigo18").ser_agarrado())
	en(1500, func(): enemigo("enemigo18").ser_soltado(Vector2(300, -300)))
	en(1600, func(): enemigo("enemigo14").recibir_flechazo("letal", Vector2(-1, 0)))
	en(1601, func(): enemigo("enemigo14").recibir_flechazo("letal", Vector2(-1, 0)))
	# --- Jugadora vista por un guardia (persecución y muerte) ---
	llevar(2200, enemigo("enemigo5").global_position + Vector2(250, 0))

func _physics_process(_delta):
	if cuadro < 0:
		return
	for f in eventos.get(cuadro, []):
		f.call()
	registrar()
	cuadro += 1
	if cuadro >= CUADROS:
		var archivo = FileAccess.open(salida, FileAccess.WRITE)
		archivo.store_string("\n".join(lineas) + "\n")
		archivo.close()
		print("grabación: ", lineas.size(), " líneas en ", salida)
		get_tree().quit()

func f2(v):
	return "(%.1f,%.1f)" % [v.x, v.y]

var murio = false

func registrar():
	if not is_instance_valid(j):
		lineas.append("%d RECARGA" % cuadro)
		j = get_tree().get_first_node_in_group("jugador")
		if j == null:
			return
	if j.esta_muerto and not murio:
		murio = true
		print("muere en el cuadro ", cuadro, " en ", j.global_position)
	# El estado se toma antes del paso de física de este cuadro (el tester corre primero)
	lineas.append("%d J %s v%s %s:%d sig=%s aco=%s col=%s blo=%s apu=%s esc=%s mue=%s reh=%s arma=%s obj=%s mun=%s vis=%s" % [
		cuadro, f2(j.global_position), f2(j.velocity), j.anim.animation, j.anim.frame,
		j.es_sigilo, j.esta_acostado, j.is_hanging, j.accion_bloqueante, j.is_aiming,
		j.trepando_escalera, j.esta_muerto, j.enemigo_agarrado != null,
		j.inventario.arma_actual, j.inventario.objeto_actual, j.inventario.municion, j.visible])
	if cuadro % 10 != 0:
		return
	for e in get_tree().get_nodes_in_group("enemigo"):
		if not "estado_actual" in e:
			continue
		lineas.append("%d E %s %s %s dir=%d %s:%d vida=%d casco=%s her=%s int=%s" % [
			cuadro, e.name, f2(e.global_position), e.Estado.keys()[e.estado_actual], e.direccion_x,
			e.anim.animation, e.anim.frame, e.vida, e.tiene_gorro, e.esta_herido,
			f2(e.punto_interes) if e.punto_interes != null else "-"])
	var proyectiles = 0
	for n in get_tree().current_scene.get_children():
		if n.get_script() in [preload("res://scripts/flecha.gd"), preload("res://scripts/arrojable.gd"), preload("res://scripts/bala.gd")]:
			proyectiles += 1
	lineas.append("%d P %d" % [cuadro, proyectiles])
