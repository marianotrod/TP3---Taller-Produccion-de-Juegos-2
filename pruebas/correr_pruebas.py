"""Corre las pruebas automáticas del juego y resume el resultado.

Uso (desde la carpeta del juego):
    python pruebas/correr_pruebas.py                     # pruebas con OK/FALLA
    python pruebas/correr_pruebas.py --grabar base.txt   # además graba el comportamiento
    python pruebas/correr_pruebas.py --comparar base.txt # además compara contra una grabación

Las pruebas cargan res://scenes/mundo.tscn a través de pruebas/probe.tscn.
t_nav.gd y t_escalones.gd son diagnósticos (imprimen datos, no aprueban ni fallan).
"""
import os
import re
import subprocess
import sys
import tempfile

PRUEBAS = ["t_mecanicas", "t_nuevos", "t_persecucion", "t_ia", "t_titulo_combate"]
ARGS_EXTRA = {"t_titulo_combate": ["con_titulo"]}
GODOT = os.environ.get("GODOT", "godot")


def correr(tester, extra=(), fixed_fps=False):
    cmd = [GODOT, "--headless", "--path", "."]
    if fixed_fps:
        cmd += ["--fixed-fps", "60"]
    cmd += ["res://pruebas/probe.tscn", "--", f"tester=res://pruebas/{tester}.gd", *extra]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600)
    return r.stdout + r.stderr


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    args = sys.argv[1:]
    fallas_total = 0
    for t in PRUEBAS:
        salida = correr(t, ARGS_EXTRA.get(t, []))
        ok = len(re.findall(r"^OK ", salida, re.M))
        fallas = re.findall(r"^FALLA (.*)$", salida, re.M)
        errores = len(re.findall(r"^SCRIPT ERROR", salida, re.M))
        llegaron = re.search(r"LLEGARON (\d+) / (\d+)", salida)
        if llegaron and llegaron.group(1) != llegaron.group(2):
            fallas.append(f"no llegaron todos ({llegaron.group(0)})")
        if llegaron:
            ok += 1
        estado = "OK   " if not fallas and not errores else "FALLA"
        print(f"{estado} {t}: {ok} bien, {len(fallas)} mal, {errores} errores de script")
        for f in fallas:
            print(f"        - {f}")
        fallas_total += len(fallas) + errores

    if "--grabar" in args or "--comparar" in args:
        modo = "--grabar" if "--grabar" in args else "--comparar"
        ruta = os.path.abspath(args[args.index(modo) + 1])
        destino = ruta if modo == "--grabar" else os.path.join(tempfile.gettempdir(), "grabacion_actual.txt")
        salida = correr("t_grabacion", [f"salida={destino.replace(os.sep, '/')}"], fixed_fps=True)
        if "grabación:" not in salida:
            print("FALLA grabación: no terminó\n" + salida[-2000:])
            fallas_total += 1
        elif modo == "--grabar":
            print(f"OK    grabación guardada en {ruta}")
        else:
            r = subprocess.run([sys.executable, "pruebas/comparar_grabaciones.py", ruta, destino],
                               capture_output=True, env={**os.environ, "PYTHONIOENCODING": "utf-8"}, text=True, encoding="utf-8", errors="replace")
            print(("OK    " if r.returncode == 0 else "DIFIERE ") + "grabación: " + r.stdout.strip())
            if r.returncode != 0:
                fallas_total += 1

    sys.exit(1 if fallas_total else 0)


if __name__ == "__main__":
    main()
