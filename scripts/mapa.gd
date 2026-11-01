extends RefCounted

# Consultas sobre el mapa del nivel que usan varios scripts.
# Uso: const Mapa = preload("res://scripts/mapa.gd")

const CAPA_OCULTAMIENTO = "TileMapLayer2"   # Capa con el dato "tipo_ocultamiento" (1 pasto, 2 arbusto)

# Tipo de ocultamiento del tile en ese punto (0 si no hay nada o no hay mapa)
static func ocultamiento_en(nodo: Node, punto: Vector2) -> int:
	var escena = nodo.get_tree().current_scene if nodo.is_inside_tree() else null
	if escena == null:
		return 0
	var mapa = escena.get_node_or_null(CAPA_OCULTAMIENTO)
	if mapa == null:
		return 0
	var datos = mapa.get_cell_tile_data(mapa.local_to_map(mapa.to_local(punto)))
	if datos == null:
		return 0
	return datos.get_custom_data("tipo_ocultamiento")
