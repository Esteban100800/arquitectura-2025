import serial
import serial.tools.list_ports
import threading

def listar_puertos():
    puertos = serial.tools.list_ports.comports()
    if not puertos:
        print("No se encontraron puertos COM.")
        return None
    print("Puertos disponibles:")
    for i, p in enumerate(puertos):
        print(f"  [{i}] {p.device} - {p.description}")
    idx = int(input("Selecciona el indice [0, 1, ...]: "))
    return puertos[idx].device

def hilo_recepcion(ser):
    count = 0
    print(f"\n{'#':>4}  {'HEX':>6}  {'DEC':>5}  {'BIN':>10}  ASCII")
    print("-" * 40)
    while True:
        byte = ser.read(1)
        if byte:
            count += 1
            valor = byte[0]
            ascii_char = chr(valor) if 32 <= valor <= 126 else '.'
            print(f"{count:>4}  0x{valor:02X}  {valor:>5}  {valor:08b}  {ascii_char}")

def main():
    puerto = listar_puertos()
    if puerto is None:
        return

    baud = 9600
    print(f"\nConectando a {puerto} a {baud} baud...")

    with serial.Serial(puerto, baud, timeout=1) as ser:
        # hilo de recepcion en segundo plano
        t = threading.Thread(target=hilo_recepcion, args=(ser,), daemon=True)
        t.start()

        print("\nEscribi un valor para enviar a la FPGA:")
        print("  Decimal:     42")
        print("  Hexadecimal: 0x2A")
        print("  Binario:     0b00101010")
        print("  Texto:       hola  (envia cada caracter)")
        print("  'salir' para terminar\n")

        while True:
            entrada = input("> ").strip()
            if entrada.lower() == "salir":
                break
            try:
                # detectar formato
                if entrada.startswith("0x") or entrada.startswith("0X"):
                    valor = int(entrada, 16)
                    ser.write(bytes([valor & 0xFF]))
                    print(f"  Enviado: 0x{valor:02X} ({valor})")
                elif entrada.startswith("0b") or entrada.startswith("0B"):
                    valor = int(entrada, 2)
                    ser.write(bytes([valor & 0xFF]))
                    print(f"  Enviado: 0x{valor:02X} ({valor})")
                elif entrada.isdigit():
                    valor = int(entrada)
                    ser.write(bytes([valor & 0xFF]))
                    print(f"  Enviado: 0x{valor:02X} ({valor})")
                else:
                    # enviar como texto
                    ser.write(entrada.encode())
                    print(f"  Enviado: '{entrada}' ({len(entrada)} bytes)")
            except ValueError:
                print("  Formato invalido. Usa decimal, 0x.., 0b.. o texto.")

if __name__ == "__main__":
    main()
