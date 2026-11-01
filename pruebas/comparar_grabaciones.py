"""Compara dos grabaciones de t_grabacion.gd y muestra dónde empiezan a diferir.

Uso: python pruebas/comparar_grabaciones.py antes.txt despues.txt [cantidad]
"""
import sys


def cargar(ruta):
    with open(ruta, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f]


def clave(linea):
    # "cuadro tipo nombre..." -> identifica la entidad para alinear líneas
    partes = linea.split(" ")
    if partes[1] == "E":
        return (int(partes[0]), "E", partes[2])
    return (int(partes[0]), partes[1], "")


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    a, b = cargar(sys.argv[1]), cargar(sys.argv[2])
    cantidad = int(sys.argv[3]) if len(sys.argv) > 3 else 15
    da = {clave(l): l for l in a}
    db = {clave(l): l for l in b}
    claves = sorted(set(da) | set(db))
    difs = [k for k in claves if da.get(k) != db.get(k)]
    print(f"{len(a)} / {len(b)} líneas, {len(difs)} distintas")
    primeras = {}
    for k in difs:
        entidad = (k[1], k[2])
        if entidad not in primeras:
            primeras[entidad] = k
    for entidad, k in sorted(primeras.items(), key=lambda x: x[1][0])[:cantidad]:
        print(f"\n== {entidad[0]} {entidad[1]} desde el cuadro {k[0]}")
        print("  antes:  ", da.get(k, "(no está)"))
        print("  después:", db.get(k, "(no está)"))
    sys.exit(1 if difs else 0)


if __name__ == "__main__":
    main()
