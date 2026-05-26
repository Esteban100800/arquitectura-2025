# ALU 8 bits

ALU combinacional de 8 bits con opcode de 6 bits. Soporta operaciones aritméticas, lógicas y de desplazamiento. Está envuelta en un `top_alu` que carga los operandos A, B y el opcode desde un banco de switches usando tres botones.

## Interfaz

### `Top ALU`

| Señal       | Dirección | Ancho | Descripción                                              |
|-------------|-----------|-------|----------------------------------------------------------|
| `i_clk`     | in        | 1     | Reloj del sistema                                        |
| `i_reset`   | in        | 1     | Reset síncrono activo en alto                            |
| `i_sw`      | in        | 8     | Switches para cargar A, B u opcode                       |
| `i_btn[0]`  | in        | 1     | Carga el valor de `i_sw` en el registro A                |
| `i_btn[1]`  | in        | 1     | Carga el valor de `i_sw` en el registro B                |
| `i_btn[2]`  | in        | 1     | Carga `i_sw[5:0]` en el registro de opcode               |
| `o_Result`  | out       | 8     | Resultado de la operación                                |
| `o_Zero`    | out       | 1     | Flag: vale 1 si `o_Result == 0`                          |
| `o_Carry`   | out       | 1     | Flag: carry de la suma o borrow de la resta              |

### `ALU` (parametrizable)

- `NBDATA` (default 8): ancho de los operandos y el resultado.
- `NBOP` (default 6): ancho del opcode.

## Operaciones

| Opcode (bin) | Opcode (hex) | Mnemónico | Operación        | Notas                              |
|--------------|--------------|-----------|------------------|------------------------------------|
| `100000`     | `0x20`       | ADD       | `A + B`          | Actualiza `Carry` con el bit 8     |
| `100010`     | `0x22`       | SUB       | `A - B`          | `Carry` actúa como borrow          |
| `100100`     | `0x24`       | AND       | `A & B`          | `Carry = 0`                        |
| `100101`     | `0x25`       | OR        | `A \| B`         | `Carry = 0`                        |
| `101000`     | `0x28`       | XOR       | `A ^ B`          | `Carry = 0`                        |
| `000010`     | `0x02`       | SLL       | `A << 1`         | Desplazamiento lógico izquierda    |
| `000011`     | `0x03`       | SRL       | `A >> 1`         | Desplazamiento lógico derecha      |
| `100111`     | `0x27`       | NOR       | `~(A \| B)`      | `Carry = 0`                        |

Cualquier opcode no listado devuelve `Result = 0` (default del `case`).

## Flags

- **Zero**: se activa cuando `o_Result` es cero, sin importar la operación.
- **Carry**: solo se actualiza en suma y resta; en el resto de operaciones queda en 0.

## Testplan implementado

Los tests están en `tb_alu.py` y se ejecutan con `make`. Hay un test por operación.

| Test                | Operación  | Operandos (A, B) | Resultado esperado | Flags verificados |
|---------------------|------------|------------------|--------------------|-------------------|
| `test_suma`         | ADD (0x20) | 200, 100         | `0x2C` (44)        | Carry = 1         |
| `test_resta`        | SUB (0x22) | 90, 30           | `0x3C` (60)        | Carry = 0         |
| `test_and`          | AND (0x24) | `0xCC`, `0xAA`   | `0x88`             | —                 |
| `test_or`           | OR  (0x25) | `0xC0`, `0x0F`   | `0xCF`             | —                 |
| `test_xor`          | XOR (0x28) | `0xF0`, `0xAA`   | `0x5A`             | —                 |
| `test_shift_left`   | SLL (0x02) | `0x15`, —        | `0x2A`             | —                 |
| `test_shift_right`  | SRL (0x03) | `0xAA`, —        | `0x55`             | —                 |
| `test_nor`          | NOR (0x27) | `0xFF`, `0x00`   | `0x00`             | Zero = 1          |