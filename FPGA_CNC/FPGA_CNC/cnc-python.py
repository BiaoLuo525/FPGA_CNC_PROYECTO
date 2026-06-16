import serial
import time
import math
import os

# ==========================================
# CONFIGURACIÓN DE LA MÁQUINA
# ==========================================
PUERTO_SERIAL = 'COM8'  # Tu puerto serial configurado
BAUDIOS = 115200
PASOS_POR_MM = 20.0      # Resolución de tu mecánica (ajustable)

# ==========================================
# INICIALIZACIÓN DEL PUERTO SERIAL
# ==========================================
try:
    print(f"Abriendo conexión en {PUERTO_SERIAL} a {BAUDIOS} baudios...")
    ser = serial.Serial(PUERTO_SERIAL, BAUDIOS, timeout=5)
    time.sleep(2) # Esperar a que el puerto de la Basys 3 se estabilice
    print("¡Conexión establecida con la FPGA!")
except Exception as e:
    print(f"Error fatal: No se pudo abrir el puerto {PUERTO_SERIAL}. ¿Está conectada la Basys3?")
    print(f"Detalle: {e}")
    exit()

# Variables de estado global del plotter
pos_x_actual_mm = 0.0
pos_y_actual_mm = 0.0
boli_abajo = False # False = Arriba (G0 / Z>0), True = Abajo (G1 / Z<=0)

# ==========================================
# FUNCIÓN CORE: TRANSMISIÓN DE TRAMAS BINARIAS
# ==========================================
def enviar_comando_fpga(pasos_x, pasos_y, dir_x, dir_y, pen_down):
    """Construye la trama exacta de 9 bytes que espera tu FSM_Main.vhd,
    calcula el Checksum XOR y espera la respuesta 'K' (0x4B) de éxito."""
    
    byte0 = 0xAA # Byte de Sincronismo (SYNC)
    
    # Banderas de control en Byte 1: bit 0 (Dir X), bit 1 (Dir Y), bit 2 (Pen State)
    b_dir_x = 1 if dir_x else 0
    b_dir_y = 1 if dir_y else 0
    b_pen   = 1 if pen_down else 0
    byte1 = b_dir_x | (b_dir_y << 1) | (b_pen << 2)
    
    # Descomposición de Pasos a 16-bits (Formato Big Endian)
    byte2 = (pasos_x >> 8) & 0xFF # MSB Eje X
    byte3 = pasos_x & 0xFF        # LSB Eje X
    byte4 = (pasos_y >> 8) & 0xFF # MSB Eje Y
    byte5 = pasos_y & 0xFF        # LSB Eje Y
    
    # Bytes de relleno (Padding)
    byte6 = 0x00
    byte7 = 0x00
    
    # Empaquetado y cálculo del Checksum mediante operación XOR sucesiva
    trama = [byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7]
    checksum = 0
    for b in trama:
        checksum ^= b
    trama.append(checksum) # El noveno byte es el resultado del Checksum
    
    # Envío físico de los 9 bytes por el bus serial
    ser.write(bytes(trama))
    ser.flush()
    
    # Bucle de escucha esperando el retorno del token 'K' desde la FPGA
    while True:
        respuesta = ser.read(1)
        if respuesta == b'K':
            break # Comando completado con éxito por la FPGA
        elif len(respuesta) == 0:
            print("ERROR: Timeout esperando respuesta de la FPGA. El sistema se ha congelado.")
            break

# ==========================================
# FUNCIÓN DE PLANIFICACIÓN DE MOVIMIENTOS
# ==========================================
def mover_a(target_x_mm, target_y_mm, bajar_boli):
    global pos_x_actual_mm, pos_y_actual_mm, boli_abajo
    
    # --- 1. GESTIÓN EXCLUSIVA DEL SERVO (Eje Z) ---
    # Si detectamos un cambio en el estado del bolígrafo, enviamos una trama previa.
    if bajar_boli != boli_abajo:
        # ¡HACK DE INGENIERÍA!: Forzamos 1 paso en X en lugar de 0.
        # Esto hace que el módulo Bresenham de la FPGA compute un movimiento real,
        # active la señal 'motion_done' y libere la FSM devolviendo la 'K'.
        enviar_comando_fpga(1, 0, True, True, bajar_boli)
        time.sleep(0.3) # Retardo físico: tiempo para que el servo complete el giro mecánico
        boli_abajo = bajar_boli

    # --- 2. CÁLCULO DE DISTANCIAS Y DIRECCIÓN EN ESPACIO MÉTRICO ---
    delta_x_mm = target_x_mm - pos_x_actual_mm
    delta_y_mm = target_y_mm - pos_y_actual_mm
    
    # Conversión de milímetros a pulsos discretos (Pasos de motor)
    pasos_x = int(abs(delta_x_mm) * PASOS_POR_MM)
    pasos_y = int(abs(delta_y_mm) * PASOS_POR_MM)
    
    # Determinación del sentido de giro (True = Positivo / False = Negativo)
    dir_x = True if delta_x_mm >= 0 else False
    dir_y = True if delta_y_mm >= 0 else False
    
    # Protección contra desbordamiento de registros en el hardware (Max 16 bits = 65535)
    if pasos_x > 65535 or pasos_y > 65535:
        print("ADVERTENCIA: Movimiento excede el límite de 16 bits, truncando a 65535 pasos.")
        pasos_x = min(pasos_x, 65535)
        pasos_y = min(pasos_y, 65535)

    # --- 3. TRANSFERENCIA DE COORDENADAS DE TRACCIÓN ---
    if pasos_x > 0 or pasos_y > 0:
        enviar_comando_fpga(pasos_x, pasos_y, dir_x, dir_y, boli_abajo)
        # Actualización de la posición virtual del sistema
        pos_x_actual_mm = target_x_mm
        pos_y_actual_mm = target_y_mm

# ==========================================
# INTERPRÉTE PRO DE ARCHIVOS G-CODE
# ==========================================
def procesar_gcode(archivo):
    if not os.path.exists(archivo):
        print(f"Error: No se encuentra el archivo {archivo}")
        return

    print(f"Empezando trabajo: {archivo}")
    # Forzamos codificación UTF-8 para evitar errores con tildes y comentarios en Windows
    with open(archivo, 'r', encoding='utf-8') as f:
        lineas = f.readlines()
        
    for linea in lineas:
        linea = linea.strip().upper()
        if not linea or linea.startswith(';'):
            continue # Ignorar líneas vacías y comentarios de texto
            
        partes = linea.split()
        comando = partes[0]
        
        # Filtrado de comandos de interpolación lineal admisibles
        if comando in ['G0', 'G00', 'G1', 'G01']:
            nuevo_x = pos_x_actual_mm
            nuevo_y = pos_y_actual_mm
            
            # Comportamiento G-Code estándar: G0 levanta herramienta por defecto, G1 la baja.
            boli_abj = True if comando in ['G1', 'G01'] else False
            
            # Extracción inteligente de parámetros de la línea
            for p in partes[1:]:
                if p.startswith('X'):
                    nuevo_x = float(p[1:])
                elif p.startswith('Y'):
                    nuevo_y = float(p[1:])
                elif p.startswith('Z'):
                    # ¡PARSER DE EJE Z ACTIVADO! 
                    # Z > 0 es Bolígrafo Arriba (False). Z <= 0 es Bolígrafo Abajo (True)
                    boli_abj = False if float(p[1:]) > 0 else True
            
            # Ejecutar el bloque de movimiento coordinado
            mover_a(nuevo_x, nuevo_y, boli_abj)

# ==========================================
# BLOQUE PRINCIPAL DE EJECUCIÓN
# ==========================================
if __name__ == '__main__':
    try:
        # Lanza las pruebas en orden secuencial
        
        procesar_gcode("test_servo.gcode")
        procesar_gcode("test_completo.gcode")
        
    except KeyboardInterrupt:
        print("\nTrabajo abortado de emergencia por el usuario (Ctrl+C).")
        # Medida de protección: Levanta el bolígrafo inmediatamente al cancelar
        mover_a(pos_x_actual_mm, pos_y_actual_mm, False)
        
    finally:
        ser.close()
        print("Puerto serial cerrado correctamente.")