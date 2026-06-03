import serial
import time
import math
import os

# ==========================================
# CONFIGURACIÓN DE LA MÁQUINA (¡Ajústalo!)
# ==========================================
PUERTO_SERIAL = 'COM10'
BAUDIOS = 115200

# Pasos por milímetro:
# Motor 1.8º (200p/v) + TB6600 a 1/4 micropaso (800p/v) + polea GT2 20 dientes (40 mm/v)
# -> 800 / 40 = 20 pasos/mm
PASOS_POR_MM = 20.0

# ==========================================
# PARÁMETROS DE HOMING
# ==========================================
# Distancia máxima de búsqueda del home (en mm).
# La máquina se moverá como máximo esta distancia antes de declarar fallo.
# Ponlo un poco mayor que el recorrido físico real de tus ejes.
HOMING_BUSQUEDA_MAX_MM_X = 350.0
HOMING_BUSQUEDA_MAX_MM_Y = 350.0

# Velocidad de homing: la FPGA usa SYS_MOT_FREQ para todos los movimientos,
# así que la velocidad es fija por hardware. Aquí solo definimos el timeout
# en segundos que espera el Python antes de declarar la comunicación perdida.
HOMING_TIMEOUT_SEG = 60.0

# ==========================================
# RESPUESTAS DE LA FPGA
# ==========================================
RESP_OK      = b'K'   # 0x4B - Movimiento normal completado
RESP_HOMING  = b'H'   # 0x48 - Homing completado con éxito
RESP_HFAIL   = b'F'   # 0x46 - Homing fallido (timeout sin encontrar final de carrera)
RESP_ERROR   = b'E'   # 0x45 - Error de checksum

# ==========================================
# INICIALIZACIÓN
# ==========================================
try:
    print(f"Abriendo conexión en {PUERTO_SERIAL} a {BAUDIOS} baudios...")
    ser = serial.Serial(PUERTO_SERIAL, BAUDIOS, timeout=5)
    time.sleep(2)
    print("¡Conexión establecida con la FPGA!")
except Exception as e:
    print(f"Error fatal: No se pudo abrir el puerto {PUERTO_SERIAL}.")
    print(f"Detalle: {e}")
    exit()

# Variables de estado del plotter
pos_x_actual_mm = 0.0
pos_y_actual_mm = 0.0
boli_abajo = False     # False = Arriba, True = Abajo
homing_realizado = False

# ==========================================
# FUNCIÓN CORE: HABLAR CON LA FPGA
# ==========================================
def _construir_trama(pasos_x, pasos_y, dir_x, dir_y, pen_down, homing=False):
    """
    Construye la trama de 9 bytes con checksum XOR.

    Byte 0:    0xAA (SYNC)
    Byte 1:    Flags [bit0=dir_x | bit1=dir_y | bit2=pen | bit3=homing]
    Byte 2-3:  Pasos X (16-bit Big Endian)
    Byte 4-5:  Pasos Y (16-bit Big Endian)
    Byte 6-7:  Padding 0x00
    Byte 8:    Checksum XOR (bytes 0-7)
    """
    byte0 = 0xAA
    b_dir_x  = 1 if dir_x    else 0
    b_dir_y  = 1 if dir_y    else 0
    b_pen    = 1 if pen_down  else 0
    b_homing = 1 if homing   else 0
    byte1 = b_dir_x | (b_dir_y << 1) | (b_pen << 2) | (b_homing << 3)

    byte2 = (pasos_x >> 8) & 0xFF
    byte3 =  pasos_x       & 0xFF
    byte4 = (pasos_y >> 8) & 0xFF
    byte5 =  pasos_y       & 0xFF
    byte6 = 0x00
    byte7 = 0x00

    trama = [byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7]
    checksum = 0
    for b in trama:
        checksum ^= b
    trama.append(checksum)
    return bytes(trama)


def _esperar_respuesta(timeout_seg=10.0):
    """
    Espera un byte de respuesta de la FPGA.
    Devuelve el byte recibido o None si hay timeout.
    """
    ser.timeout = timeout_seg
    respuesta = ser.read(1)
    ser.timeout = 5  # Restaurar timeout por defecto
    if len(respuesta) == 0:
        print("ERROR: Timeout esperando respuesta de la FPGA.")
        return None
    return respuesta


def enviar_comando_fpga(pasos_x, pasos_y, dir_x, dir_y, pen_down):
    """Envía un movimiento normal y espera la confirmación 'K'."""
    trama = _construir_trama(pasos_x, pasos_y, dir_x, dir_y, pen_down, homing=False)
    ser.write(trama)
    ser.flush()

    while True:
        respuesta = _esperar_respuesta()
        if respuesta is None:
            break
        if respuesta == RESP_OK:
            break
        elif respuesta == RESP_ERROR:
            print("ADVERTENCIA: La FPGA reportó error de checksum. Reintentando...")
            ser.write(trama)
            ser.flush()

# ==========================================
# FUNCIÓN DE HOMING
# ==========================================
def hacer_homing():
    """
    Envía la orden de homing a la FPGA y espera la respuesta.

    La FPGA moverá ambos ejes en dirección negativa (hacia los finales de carrera)
    hasta que los detecte o hasta que se agoten los pasos de timeout.

    Retorna True si el homing fue exitoso, False en caso contrario.
    """
    global pos_x_actual_mm, pos_y_actual_mm, boli_abajo, homing_realizado

    print("=" * 50)
    print("  INICIANDO SECUENCIA DE HOMING")
    print("=" * 50)

    # Calculamos los pasos de timeout (máximo recorrido de búsqueda)
    timeout_pasos_x = int(HOMING_BUSQUEDA_MAX_MM_X * PASOS_POR_MM)
    timeout_pasos_y = int(HOMING_BUSQUEDA_MAX_MM_Y * PASOS_POR_MM)

    # Protección de 16 bits
    timeout_pasos_x = min(timeout_pasos_x, 65535)
    timeout_pasos_y = min(timeout_pasos_y, 65535)

    print(f"  Timeout de búsqueda: X={timeout_pasos_x} pasos, Y={timeout_pasos_y} pasos")
    print(f"  Distancia máxima:    X={HOMING_BUSQUEDA_MAX_MM_X} mm, Y={HOMING_BUSQUEDA_MAX_MM_Y} mm")
    print(f"  Esperando respuesta (máx. {HOMING_TIMEOUT_SEG}s)...")

    # Construimos la trama de homing:
    # - dir_x / dir_y = False (0): dirección hacia el origen
    # - pen_down = False: la FPGA subirá el boli antes de moverse
    # - homing = True: activa el bit 3 del byte de flags
    trama = _construir_trama(
        pasos_x  = timeout_pasos_x,
        pasos_y  = timeout_pasos_y,
        dir_x    = False,
        dir_y    = False,
        pen_down = False,
        homing   = True
    )

    ser.write(trama)
    ser.flush()

    # Esperamos la respuesta con un timeout largo (movimiento físico lento)
    respuesta = _esperar_respuesta(timeout_seg=HOMING_TIMEOUT_SEG)

    if respuesta == RESP_HOMING:
        print("  ✓ HOMING COMPLETADO CON ÉXITO")
        print("  La máquina está ahora en la posición de origen (0, 0).")
        # Actualizamos el estado interno: estamos en el origen
        pos_x_actual_mm = 0.0
        pos_y_actual_mm = 0.0
        boli_abajo = False
        homing_realizado = True
        print("=" * 50)
        return True

    elif respuesta == RESP_HFAIL:
        print("  ✗ HOMING FALLIDO: La FPGA no encontró los finales de carrera.")
        print("  Posibles causas:")
        print("    - Los finales de carrera no están conectados o están mal cableados.")
        print("    - HOMING_BUSQUEDA_MAX_MM es insuficiente para el recorrido real.")
        print("    - La dirección de homing está invertida (revisa DIR_INVERT en tb6600_axis_driver).")
        homing_realizado = False
        print("=" * 50)
        return False

    elif respuesta is None:
        print("  ✗ HOMING FALLIDO: Timeout de comunicación (sin respuesta de la FPGA).")
        homing_realizado = False
        print("=" * 50)
        return False

    else:
        print(f"  ✗ HOMING FALLIDO: Respuesta inesperada: 0x{respuesta.hex()}")
        homing_realizado = False
        print("=" * 50)
        return False

# ==========================================
# FUNCIÓN DE MOVIMIENTO
# ==========================================
def mover_a(target_x_mm, target_y_mm, bajar_boli):
    global pos_x_actual_mm, pos_y_actual_mm, boli_abajo

    # Advertencia si no se ha hecho homing
    if not homing_realizado:
        print("ADVERTENCIA: Moviendo sin haber hecho homing. La posición puede ser incorrecta.")

    # --- 1. GESTIÓN DEL SERVO (Eje Z) ---
    if bajar_boli != boli_abajo:
        enviar_comando_fpga(0, 0, 0, 0, bajar_boli)
        time.sleep(0.3)
        boli_abajo = bajar_boli

    # --- 2. CÁLCULO DE PASOS Y DIRECCIÓN ---
    delta_x_mm = target_x_mm - pos_x_actual_mm
    delta_y_mm = target_y_mm - pos_y_actual_mm

    pasos_x = int(abs(delta_x_mm) * PASOS_POR_MM)
    pasos_y = int(abs(delta_y_mm) * PASOS_POR_MM)

    dir_x = delta_x_mm >= 0
    dir_y = delta_y_mm >= 0

    if pasos_x > 65535 or pasos_y > 65535:
        print("ADVERTENCIA: Movimiento demasiado largo, truncando a 65535 pasos.")
        pasos_x = min(pasos_x, 65535)
        pasos_y = min(pasos_y, 65535)

    # --- 3. EJECUCIÓN ---
    if pasos_x > 0 or pasos_y > 0:
        enviar_comando_fpga(pasos_x, pasos_y, dir_x, dir_y, boli_abajo)
        pos_x_actual_mm = target_x_mm
        pos_y_actual_mm = target_y_mm

# ==========================================
# LECTOR DE G-CODE
# ==========================================
def procesar_gcode(archivo):
    global pos_x_actual_mm, pos_y_actual_mm

    if not os.path.exists(archivo):
        print(f"No se encuentra el archivo: {archivo}")
        return

    if not homing_realizado:
        resp = input("ADVERTENCIA: No se ha hecho homing. ¿Continuar de todos modos? (s/N): ")
        if resp.strip().lower() != 's':
            print("Trabajo cancelado. Haz homing primero.")
            return

    print(f"Empezando trabajo: {archivo}")
    with open(archivo, 'r', encoding='utf-8') as f:
        lineas = f.readlines()

    for linea in lineas:
        linea = linea.strip().upper()
        if not linea or linea.startswith(';'):
            continue

        # Eliminar comentarios inline (;)
        if ';' in linea:
            linea = linea[:linea.index(';')].strip()

        partes = linea.split()
        if not partes:
            continue

        comando = partes[0]

        if comando in ['G0', 'G00', 'G1', 'G01']:
            nuevo_x = pos_x_actual_mm
            nuevo_y = pos_y_actual_mm

            for p in partes[1:]:
                if p.startswith('X'):
                    try:
                        nuevo_x = float(p[1:])
                    except ValueError:
                        pass
                elif p.startswith('Y'):
                    try:
                        nuevo_y = float(p[1:])
                    except ValueError:
                        pass

            boli_abj = comando in ['G1', 'G01']
            mover_a(nuevo_x, nuevo_y, boli_abj)

        elif comando in ['G28']:
            # G28 en G-Code estándar = ir a origen (homing)
            print("G-Code G28 detectado: ejecutando homing...")
            hacer_homing()

# ==========================================
# RUTINA PRINCIPAL
# ==========================================
if __name__ == '__main__':
    try:
        # ------------------------------------------------------------------
        # PASO 1: HOMING (siempre recomendado al arrancar)
        # ------------------------------------------------------------------
        exito = hacer_homing()

        if not exito:
            print("\nHoming fallido. Comprueba los finales de carrera y vuelve a intentarlo.")
            print("Puedes continuar sin homing, pero la posición no será fiable.")
            respuesta = input("¿Continuar sin homing? (s/N): ")
            if respuesta.strip().lower() != 's':
                raise SystemExit("Trabajo abortado.")

        # ------------------------------------------------------------------
        # PASO 2: TRABAJO (descomenta la línea que necesites)
        # ------------------------------------------------------------------

        # Opción A: Ejecutar un archivo G-Code
        procesar_gcode("ejeXY_prueba.gcode")

        # Opción B: Movimientos manuales de prueba (descomenta para usar)
        # print("Moviendo a (50, 0) con boli arriba...")
        # mover_a(50, 0, False)
        # print("Moviendo a (50, 50) con boli abajo...")
        # mover_a(50, 50, True)
        # print("Volviendo al origen con boli arriba...")
        # mover_a(0, 0, False)

    except KeyboardInterrupt:
        print("\nTrabajo abortado por el usuario (Ctrl+C).")
        mover_a(pos_x_actual_mm, pos_y_actual_mm, False)

    finally:
        ser.close()
        print("Puerto serial cerrado.")
