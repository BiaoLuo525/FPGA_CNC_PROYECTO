import serial
import time
import math
import os

# ==========================================
# CONFIGURACIÓN DE LA MÁQUINA (¡Ajústalo!)
# ==========================================
PUERTO_SERIAL = 'COM3'  # Cambia esto por tu puerto real (Ej: 'COM4', '/dev/ttyUSB0')
BAUDIOS = 115200

# Cálculo de Pasos por Milímetro:
# Si tu motor es de 1.8º (200 pasos/vuelta) y el TB6600 está a 1/4 de micropaso (800 pulsos/vuelta)
# y usas una polea GT2 de 20 dientes (40mm de avance por vuelta):
# 800 pulsos / 40 mm = 20 pasos por mm.
PASOS_POR_MM = 20.0  

# ==========================================
# INICIALIZACIÓN
# ==========================================
try:
    print(f"Abriendo conexión en {PUERTO_SERIAL} a {BAUDIOS} baudios...")
    ser = serial.Serial(PUERTO_SERIAL, BAUDIOS, timeout=5)
    time.sleep(2) # Esperar a que el puerto se estabilice
    print("¡Conexión establecida con la FPGA!")
except Exception as e:
    print(f"Error fatal: No se pudo abrir el puerto {PUERTO_SERIAL}. ¿Está conectada la Basys3?")
    print(f"Detalle: {e}")
    exit()

# Variables de estado del plotter
pos_x_actual_mm = 0.0
pos_y_actual_mm = 0.0
boli_abajo = False # False = Arriba, True = Abajo

# ==========================================
# FUNCIÓN CORE: HABLAR CON LA FPGA
# ==========================================
def enviar_comando_fpga(pasos_x, pasos_y, dir_x, dir_y, pen_down):
    """Construye la trama de 9 bytes, calcula el Checksum y espera la 'K'"""
    
    # Preparamos los bytes según tu FSM_Main.vhd
    byte0 = 0xAA # SYNC
    
    # Banderas: bit 0 (Dir X), bit 1 (Dir Y), bit 2 (Pen State)
    b_dir_x = 1 if dir_x else 0
    b_dir_y = 1 if dir_y else 0
    b_pen   = 1 if pen_down else 0
    byte1 = b_dir_x | (b_dir_y << 1) | (b_pen << 2)
    
    # Pasos a 16-bits (Big Endian)
    byte2 = (pasos_x >> 8) & 0xFF # MSB X
    byte3 = pasos_x & 0xFF        # LSB X
    byte4 = (pasos_y >> 8) & 0xFF # MSB Y
    byte5 = pasos_y & 0xFF        # LSB Y
    
    # Padding
    byte6 = 0x00
    byte7 = 0x00
    
    # Empaquetamos y calculamos Checksum (XOR)
    trama = [byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7]
    checksum = 0
    for b in trama:
        checksum ^= b
    trama.append(checksum)
    
    # Enviamos los 9 bytes
    ser.write(bytes(trama))
    ser.flush()
    
    # Esperamos la respuesta 'K' (0x4B)
    while True:
        respuesta = ser.read(1)
        if respuesta == b'K':
            break
        elif len(respuesta) == 0:
            print("ERROR: Timeout esperando respuesta de la FPGA.")
            break

# ==========================================
# FUNCIÓN DE MOVIMIENTO INTELIGENTE
# ==========================================
def mover_a(target_x_mm, target_y_mm, bajar_boli):
    global pos_x_actual_mm, pos_y_actual_mm, boli_abajo
    
    # --- 1. GESTIÓN DEL SERVO (Eje Z) ---
    # Si el estado del boli cambia, mandamos una trama con 0 pasos solo para mover el servo
    if bajar_boli != boli_abajo:
        enviar_comando_fpga(0, 0, 0, 0, bajar_boli)
        time.sleep(0.3) # TIEMPO FÍSICO: Esperamos a que el SG90 baje/suba antes de arrancar X e Y
        boli_abajo = bajar_boli

    # --- 2. CÁLCULO DE PASOS Y DIRECCIÓN (Ejes X e Y) ---
    delta_x_mm = target_x_mm - pos_x_actual_mm
    delta_y_mm = target_y_mm - pos_y_actual_mm
    
    pasos_x = int(abs(delta_x_mm) * PASOS_POR_MM)
    pasos_y = int(abs(delta_y_mm) * PASOS_POR_MM)
    
    dir_x = True if delta_x_mm >= 0 else False
    dir_y = True if delta_y_mm >= 0 else False
    
    # Protección de 16 bits de tu VHDL (Max 65535 pasos por trama)
    if pasos_x > 65535 or pasos_y > 65535:
        print("ADVERTENCIA: Movimiento demasiado largo, truncando a 65535 pasos.")
        pasos_x = min(pasos_x, 65535)
        pasos_y = min(pasos_y, 65535)

    # --- 3. EJECUCIÓN DEL MOVIMIENTO ---
    if pasos_x > 0 or pasos_y > 0:
        enviar_comando_fpga(pasos_x, pasos_y, dir_x, dir_y, boli_abajo)
        # Actualizamos la posición interna
        pos_x_actual_mm = target_x_mm
        pos_y_actual_mm = target_y_mm

# ==========================================
# LECTOR DE G-CODE
# ==========================================
def procesar_gcode(archivo):
    if not os.path.exists(archivo):
        print(f"No se encuentra el archivo {archivo}")
        return

    print(f"Empezando trabajo: {archivo}")
    with open(archivo, 'r') as f:
        lineas = f.readlines()
        
    for linea in lineas:
        linea = linea.strip().upper()
        if not linea or linea.startswith(';'):
            continue # Ignorar comentarios y líneas vacías
            
        partes = linea.split()
        comando = partes[0]
        
        # Comandos de movimiento
        if comando in ['G0', 'G00', 'G1', 'G01']:
            nuevo_x = pos_x_actual_mm
            nuevo_y = pos_y_actual_mm
            
            # Extraer coordenadas
            for p in partes[1:]:
                if p.startswith('X'):
                    nuevo_x = float(p[1:])
                elif p.startswith('Y'):
                    nuevo_y = float(p[1:])
            
            # G0 (o G00) = Movimiento rápido (Boli Arriba)
            # G1 (o G01) = Trazado (Boli Abajo)
            boli_abj = True if comando in ['G1', 'G01'] else False
            
            mover_a(nuevo_x, nuevo_y, boli_abj)

# ==========================================
# RUTINA PRINCIPAL
# ==========================================
if __name__ == '__main__':
    try:
        # TEST BÁSICO (Descomenta esto para probar tu máquina por primera vez)
        print("Haciendo test de un cuadrado de 20x20 mm...")
        mover_a(0, 0, False)   # Origen, boli arriba
        mover_a(20, 0, True)   # Dibuja linea derecha
        mover_a(20, 20, True)  # Dibuja linea arriba
        mover_a(0, 20, True)   # Dibuja linea izquierda
        mover_a(0, 0, True)    # Dibuja linea abajo
        mover_a(0, 0, False)   # Levanta boli
        print("Test terminado.")
        
        # CUANDO QUIERAS DIBUJAR UN ARCHIVO REAL, DESCOMENTA ESTO:
        # procesar_gcode("mi_dibujo.gcode")
        
    except KeyboardInterrupt:
        print("\nTrabajo abortado por el usuario (Ctrl+C).")
        # Por seguridad, subimos el boli al cancelar
        mover_a(pos_x_actual_mm, pos_y_actual_mm, False)
        
    finally:
        ser.close()
        print("Puerto serial cerrado.")