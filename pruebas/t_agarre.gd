extends Node

# Agarrar y desmayar: el guardia tiene que quedar en el piso.
# Uso: godot --headless --path . res://pruebas/probe.tscn -- tester=res://pruebas/t_agarre.gd

var fallas = 0

func check(cond, texto):
	print(("OK    " if cond else "FALLA ") + texto)
	if not cond:
		fallas += 1

func enemigo(nombre):
	for n in get_tree().get_nodes_in_group("enemigo"):
		if n.name == nombre:
			return n

func cuadros(n):
	for i in range(n):
		await get_tree().physics_frame

func tocar(accion):
	Input.action_press(accion)
	await cuadros(1)
	Input.action_release(accion)
	await cuadros(1)

func _ready():
	while not Navegacion.listo or get_tree().current_scene == null or get_tree().current_scene.name == "Probe":
		await get_tree().process_frame
	Ruido.mostrar_circulos = false
	var j = get_tree().get_first_node_in_group("jugador")
	for nombre in ["enemigo6", "enemigo7"]:
		var e = enemigo(nombre)
		var E = e.Estado
		e.volver_a_patrulla()
		e.terminar_vuelta()
		await cuadros(5)
		var y_piso = e.global_position.y
		j.global_position = e.global_position - Vector2(30 * e.direccion_x, 0)
		j.velocity = Vector2.ZERO
		j.facing_left = e.direccion_x < 0
		j.es_sigilo = true
		await cuadros(2)
		await tocar("agarre")
		check(j.enemigo_agarrado == e, nombre + ": lo agarra")
		await cuadros(30)
		await tocar("cambiar_postura")
		await cuadros(150)
		print("   %s: y antes %.0f, después %.0f, estado %s, jugadora bloqueada %s" % [nombre, y_piso, e.global_position.y, E.keys()[e.estado_actual], j.accion_bloqueante])
		check(e.estado_actual == E.DESMAYADO, nombre + ": queda desmayado")
		check(abs(e.global_position.y - y_piso) < 20.0 and e.is_on_floor(), nombre + ": queda apoyado en el piso")
		check(j.enemigo_agarrado == null and not j.accion_bloqueante, nombre + ": la jugadora queda libre")
		var y = e.global_position.y
		await cuadros(60)
		check(abs(e.global_position.y - y) < 2.0, nombre + ": no sigue cayendo")
	print("FALLAS: ", fallas)
	get_tree().quit()
