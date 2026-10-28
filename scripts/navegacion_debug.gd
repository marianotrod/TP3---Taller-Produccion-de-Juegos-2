extends Node2D

# Dibuja el grafo de navegación (se activa con F2)

const COLORES = {
	0: Color(0.3, 1.0, 0.3, 0.6),   # caminar
	1: Color(1.0, 0.6, 0.1, 0.6),   # caer
	2: Color(0.3, 0.6, 1.0, 0.7),   # saltar
	3: Color(1.0, 1.0, 0.2, 0.9),   # escalera
}

func _draw():
	var nav = Navegacion
	for clave in nav.aristas:
		var partes = clave.split(":")
		var a = nav.nodos[int(partes[0])]
		var b = nav.nodos[int(partes[1])]
		var datos = nav.aristas[clave]
		if datos.tipo == nav.Tipo.SALTAR:
			var previo = a
			for i in range(1, 9):
				var t = datos.t * i / 8.0
				var punto = a + Vector2(datos.vx * t, nav._altura_en(datos.vy, t))
				draw_line(previo, punto, COLORES[2], 2.0)
				previo = punto
		else:
			draw_line(a, b, COLORES[datos.tipo], 3.0)
	for n in nav.nodos:
		draw_circle(n, 3.0, Color.WHITE)
