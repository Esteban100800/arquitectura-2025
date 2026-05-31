"""
debug_gui.py — Interfaz gráfica para el debugger RISC-V 5 etapas

Uso:  python debug_gui.py [PORT [BAUD]]
      python debug_gui.py COM4 9600

Teclas:
  Enter  → Step
"""

import sys
import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext

BG      = "#1e1e2e"
BASE    = "#181825"
SURFACE = "#313244"
OVERLAY = "#45475a"
TEXT    = "#cdd6f4"
SUBTEXT = "#a6adc8"
BLUE    = "#89b4fa"
GREEN   = "#a6e3a1"
RED     = "#f38ba8"
YELLOW  = "#f9e2af"
PEACH   = "#fab387"
MAUVE   = "#cba6f7"
TEAL    = "#94e2d5"

STAGE_BG = {
    "IF/ID":  "#1a2f4a",
    "ID/EX":  "#1a4a2f",
    "EX/MEM": "#4a2f1a",
    "MEM/WB": "#4a1a2f",
}

MONO    = ("Consolas", 9)
MONO_LG = ("Consolas", 10, "bold")
MONO_SM = ("Consolas", 8)

REG_NAMES = [
    "zero", "ra",  "sp",  "gp",  "tp",  "t0",  "t1",  "t2",
    "s0",   "s1",  "a0",  "a1",  "a2",  "a3",  "a4",  "a5",
    "a6",   "a7",  "s2",  "s3",  "s4",  "s5",  "s6",  "s7",
    "s8",   "s9",  "s10", "s11", "t3",  "t4",  "t5",  "t6",
]

DEFAULT_PROGRAM = """\
# Suma 0+1+2+...+(N-1) en x10, guarda en mem[0]
# x5=i  x6=N  x10=acumulador
ADDI x5,  x0, 0
ADDI x6,  x0, 5
ADDI x10, x0, 0
ADD  x10, x10, x5
ADDI x5,  x5,  1
BNE  x5,  x6, -8
SW   x0,  x10, 0
NOP
NOP
NOP
HALT
"""


def s32(v: int) -> int:
    return v if v < 0x80000000 else v - 0x100000000


def h32(v: int) -> str:
    return f"0x{v & 0xFFFFFFFF:08X}"


class DebugGUI:
    def __init__(self, root: tk.Tk, default_port: str = "COM4",
                 default_baud: int = 9600):
        self.root  = root
        self.root.title("RISC-V Pipeline Debugger")
        self.root.configure(bg=BG)
        self.root.minsize(1120, 680)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

        self.dbg   = None
        self.cycle = 0

        self.port_var      = tk.StringVar(value=default_port)
        self.baud_var      = tk.StringVar(value=str(default_baud))
        self.status_var    = tk.StringVar(value="● Desconectado")
        self.cycle_var     = tk.StringVar(value="Ciclo: 0")
        self.mem_words_var = tk.StringVar(value="8")

        self._build_ui()

    # ── UI ────────────────────────────────────────────────────────
    def _build_ui(self):
        self._build_statusbar()

        content = tk.Frame(self.root, bg=BG)
        content.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        left = tk.Frame(content, bg=BG, width=234)
        left.pack(side=tk.LEFT, fill=tk.Y, padx=(0, 6))
        left.pack_propagate(False)
        self._build_connection_panel(left)
        self._build_control_panel(left)
        self._build_program_panel(left)

        right = tk.Frame(content, bg=BG)
        right.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self._build_pipeline_panel(right)

        bottom = tk.Frame(right, bg=BG)
        bottom.pack(fill=tk.BOTH, expand=True, pady=(6, 0))
        self._build_registers_panel(bottom)
        self._build_memory_panel(bottom)

    def _build_statusbar(self):
        bar = tk.Frame(self.root, bg=SURFACE, height=26)
        bar.pack(fill=tk.X, side=tk.BOTTOM)
        bar.pack_propagate(False)
        tk.Label(bar, textvariable=self.status_var, bg=SURFACE, fg=SUBTEXT,
                 font=MONO_SM, anchor=tk.W).pack(side=tk.LEFT, padx=8, pady=4)
        tk.Label(bar, textvariable=self.cycle_var, bg=SURFACE, fg=PEACH,
                 font=MONO, anchor=tk.E).pack(side=tk.RIGHT, padx=8, pady=4)

    def _build_connection_panel(self, parent):
        f = self._lf(parent, "Conexión")
        f.pack(fill=tk.X, pady=(0, 4))
        self._row_entry(f, "Puerto:", self.port_var)
        self._row_entry(f, "Baud:  ", self.baud_var)
        self.btn_connect = self._btn(f, "Conectar", self._connect, fg=GREEN)
        self.btn_connect.pack(fill=tk.X, padx=4, pady=(4, 1))
        self.btn_disconnect = self._btn(f, "Desconectar", self._disconnect,
                                        fg=RED, state=tk.DISABLED)
        self.btn_disconnect.pack(fill=tk.X, padx=4, pady=(1, 4))

    def _build_control_panel(self, parent):
        f = self._lf(parent, "Control")
        f.pack(fill=tk.X, pady=(0, 4))
        specs = [
            ("Step  [Enter]", self._step,         BLUE,   "btn_step"),
            ("Run          ", self._run,           GREEN,  "btn_run"),
            ("Halt         ", self._halt,          YELLOW, "btn_halt"),
            ("Reset        ", self._reset,         PEACH,  "btn_reset"),
            ("Cargar prog  ", self._load_program,  MAUVE,  "btn_load"),
            ("Refresh      ", self._refresh_gui,   TEAL,   "btn_refresh"),
        ]
        for text, cmd, color, attr in specs:
            btn = self._btn(f, text, cmd, fg=color, state=tk.DISABLED)
            btn.pack(fill=tk.X, padx=4, pady=1)
            setattr(self, attr, btn)
        self.root.bind("<Return>", lambda _e: self._step())

    def _build_program_panel(self, parent):
        f = self._lf(parent, "Programa (ensamblador)")
        f.pack(fill=tk.BOTH, expand=True)
        self.program_text = scrolledtext.ScrolledText(
            f, bg=BASE, fg=TEXT, font=MONO_SM, insertbackground=TEXT,
            wrap=tk.NONE, height=14, selectbackground=OVERLAY,
            selectforeground=TEXT,
        )
        self.program_text.pack(fill=tk.BOTH, expand=True, padx=4, pady=4)
        self.program_text.insert("1.0", DEFAULT_PROGRAM)

        mem_row = tk.Frame(f, bg=BG)
        mem_row.pack(fill=tk.X, padx=4, pady=(0, 4))
        tk.Label(mem_row, text="Words mem:", bg=BG, fg=SUBTEXT,
                 font=MONO_SM).pack(side=tk.LEFT)
        tk.Entry(mem_row, textvariable=self.mem_words_var, bg=SURFACE, fg=TEXT,
                 font=MONO_SM, width=4, insertbackground=TEXT,
                 relief=tk.FLAT).pack(side=tk.LEFT, padx=4)

    def _build_pipeline_panel(self, parent):
        f = self._lf(parent, "Pipeline")
        f.pack(fill=tk.X)

        stage_defs = [
            ("IF/ID",  BLUE, [
                ("pc",    "PC"),
                ("pc4",   "PC+4"),
                ("instr", "INSTR"),
                ("asm",   "ASM"),
            ]),
            ("ID/EX",  GREEN, [
                ("pc",   "PC"),
                ("rs1",  "RS1"),
                ("rs2",  "RS2"),
                ("imm",  "IMM"),
                ("rd",   "rd"),
                ("ctrl", "CTRL"),
            ]),
            ("EX/MEM", PEACH, [
                ("pc4",  "PC+4"),
                ("alu",  "ALU"),
                ("rs2",  "RS2"),
                ("btgt", "BTGT"),
                ("rd",   "rd"),
                ("ctrl", "CTRL"),
            ]),
            ("MEM/WB", MAUVE, [
                ("pc4",  "PC+4"),
                ("alu",  "ALU"),
                ("mem",  "MEM"),
                ("rd",   "rd"),
                ("ctrl", "CTRL"),
            ]),
        ]

        self.stage_vars = {}
        for col, (name, hdr_color, fields) in enumerate(stage_defs):
            bg = STAGE_BG[name]
            frame = tk.LabelFrame(f, text=f"  {name}  ", bg=bg, fg=hdr_color,
                                   font=MONO_LG, bd=2, relief=tk.GROOVE)
            frame.grid(row=0, column=col, padx=4, pady=6, sticky=tk.NSEW)
            f.columnconfigure(col, weight=1)
            self.stage_vars[name] = {}
            for key, label in fields:
                row = tk.Frame(frame, bg=bg)
                row.pack(fill=tk.X, padx=4, pady=1)
                tk.Label(row, text=f"{label}:", bg=bg, fg=SUBTEXT,
                         font=MONO_SM, width=7, anchor=tk.W).pack(side=tk.LEFT)
                var = tk.StringVar(value="—")
                lbl = tk.Label(row, textvariable=var, bg=bg, fg=TEXT,
                               font=MONO_SM, anchor=tk.W)
                lbl.pack(side=tk.LEFT, fill=tk.X, expand=True)
                self.stage_vars[name][key] = (var, lbl)

    def _build_registers_panel(self, parent):
        f = self._lf(parent, "Registros x0–x31")
        f.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 6))
        canvas, inner = self._scrollable(f)
        canvas.bind("<MouseWheel>",
                    lambda e: canvas.yview_scroll(-1 * (e.delta // 120), "units"))
        self.reg_vars   = []
        self.reg_labels = []
        for i in range(32):
            row = tk.Frame(inner, bg=BG)
            row.pack(fill=tk.X)
            tk.Label(row, text=f"x{i:<2d}", bg=BG, fg=SUBTEXT,
                     font=MONO_SM, width=4, anchor=tk.W).pack(side=tk.LEFT)
            tk.Label(row, text=f"{REG_NAMES[i]:<6}", bg=BG, fg=OVERLAY,
                     font=MONO_SM, width=6, anchor=tk.W).pack(side=tk.LEFT)
            var = tk.StringVar(value="0x00000000   (0)")
            lbl = tk.Label(row, textvariable=var, bg=BG, fg=TEXT,
                           font=MONO_SM, anchor=tk.W)
            lbl.pack(side=tk.LEFT, fill=tk.X)
            self.reg_vars.append(var)
            self.reg_labels.append(lbl)

    def _build_memory_panel(self, parent):
        f = self._lf(parent, "Memoria de datos")
        f.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        canvas, inner = self._scrollable(f)
        canvas.bind("<MouseWheel>",
                    lambda e: canvas.yview_scroll(-1 * (e.delta // 120), "units"))
        self.mem_inner = inner
        self.mem_vars  = []   # rebuilt when word count changes

    # ── Widget helpers ────────────────────────────────────────────
    def _lf(self, parent, title):
        return tk.LabelFrame(parent, text=f" {title} ", bg=BG, fg=BLUE,
                              font=MONO_LG, bd=1, relief=tk.RIDGE)

    def _btn(self, parent, text, command, fg=TEXT, state=tk.NORMAL, **kw):
        b = tk.Button(
            parent, text=text, command=command,
            bg=SURFACE, fg=fg, activebackground=OVERLAY, activeforeground=fg,
            font=MONO, relief=tk.FLAT, bd=0, padx=6, pady=3,
            state=state, cursor="hand2", anchor=tk.W, **kw,
        )
        b.bind("<Enter>",
               lambda e: b.config(bg=OVERLAY) if str(b["state"]) != "disabled" else None)
        b.bind("<Leave>", lambda e: b.config(bg=SURFACE))
        return b

    def _row_entry(self, parent, label, var):
        row = tk.Frame(parent, bg=BG)
        row.pack(fill=tk.X, padx=4, pady=2)
        tk.Label(row, text=label, bg=BG, fg=SUBTEXT, font=MONO_SM,
                 width=8, anchor=tk.W).pack(side=tk.LEFT)
        tk.Entry(row, textvariable=var, bg=SURFACE, fg=TEXT, font=MONO_SM,
                 insertbackground=TEXT, relief=tk.FLAT, bd=2).pack(
            side=tk.LEFT, fill=tk.X, expand=True)

    def _scrollable(self, parent):
        canvas = tk.Canvas(parent, bg=BG, highlightthickness=0)
        sb = ttk.Scrollbar(parent, orient=tk.VERTICAL, command=canvas.yview)
        canvas.configure(yscrollcommand=sb.set)
        sb.pack(side=tk.RIGHT, fill=tk.Y)
        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        inner = tk.Frame(canvas, bg=BG)
        win = canvas.create_window((0, 0), window=inner, anchor=tk.NW)
        inner.bind("<Configure>",
                   lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.bind("<Configure>",
                    lambda e: canvas.itemconfig(win, width=e.width))
        return canvas, inner

    def _set_btns(self, enabled: bool):
        s = tk.NORMAL if enabled else tk.DISABLED
        for a in ("btn_step", "btn_run", "btn_halt",
                  "btn_reset", "btn_load", "btn_refresh"):
            getattr(self, a).config(state=s)

    def _sv(self, stage, key, val, color=None):
        var, lbl = self.stage_vars[stage][key]
        var.set(val)
        if color:
            lbl.config(fg=color)

    # conexion 
    def _connect(self):
        from debug_client import DebugClient
        port = self.port_var.get().strip()
        try:
            baud = int(self.baud_var.get().strip())
        except ValueError:
            messagebox.showerror("Error", "Baud rate inválido")
            return
        try:
            self.dbg = DebugClient(port, baud)
            self.status_var.set(f"● Conectado  {port} @ {baud}")
            self.btn_connect.config(state=tk.DISABLED)
            self.btn_disconnect.config(state=tk.NORMAL)
            self._set_btns(True)
        except Exception as e:
            messagebox.showerror("Error de conexión", str(e))

    def _disconnect(self):
        if self.dbg:
            try:
                self.dbg.close()
            except Exception:
                pass
            self.dbg = None
        self.status_var.set("● Desconectado")
        self.btn_connect.config(state=tk.NORMAL)
        self.btn_disconnect.config(state=tk.DISABLED)
        self._set_btns(False)

    def _on_close(self):
        self._disconnect()
        self.root.destroy()

    # ── Commands ──────────────────────────────────────────────────
    def _need_dbg(self) -> bool:
        if not self.dbg:
            messagebox.showwarning("Sin conexión", "Primero conectate al procesador.")
            return False
        return True

    def _step(self):
        if not self._need_dbg():
            return
        try:
            self.dbg.step()
            self.cycle += 1
            self.cycle_var.set(f"Ciclo: {self.cycle}")
            self.status_var.set(f"● HALT  (ciclo {self.cycle})")
            self._refresh_gui()
        except Exception as e:
            self.status_var.set(f"Error: {e}")

    def _run(self):
        if not self._need_dbg():
            return
        try:
            # CMD_HALT primero garantiza el flanco bajante en CMD_RUN,
            # lo que dispara hdu_resume si el pipeline estaba halteado por HDU
            self.dbg.halt()
            self.dbg.run()
            self.status_var.set("▶ Ejecutando…  (Halt para detener)")
            threading.Thread(target=self._poll_halt, daemon=True).start()
        except Exception as e:
            self.status_var.set(f"Error: {e}")

    def _poll_halt(self):
        """Detecta automáticamente cuando el HDU congela el pipeline."""
        stable = 0
        last_pc = None
        while True:
            time.sleep(0.1)
            try:
                pc = self.dbg.read_ifid()["pc"]
            except Exception:
                break
            if pc == last_pc:
                stable += 1
            else:
                stable  = 0
                last_pc = pc
            if stable >= 3:           # PC inmóvil por 300 ms → pipeline congelado
                self.root.after(0, self._on_auto_halt)
                break

    def _on_auto_halt(self):
        self.cycle_var.set(f"Ciclo: {self.cycle}")
        self.status_var.set("⏹ HALT — pipeline vacío")
        self._refresh_gui()

    def _halt(self):
        if not self._need_dbg():
            return
        try:
            self.dbg.halt()
            self.status_var.set("⏸ HALT")
            self._refresh_gui()
        except Exception as e:
            self.status_var.set(f"Error: {e}")

    def _reset(self):
        if not self._need_dbg():
            return
        try:
            self.dbg.halt()
            self.dbg.reset_cpu()
            self.cycle = 0
            self.cycle_var.set("Ciclo: 0")
            self.status_var.set("↺ Reset  –  listo")
            self._refresh_gui()
        except Exception as e:
            self.status_var.set(f"Error: {e}")

    def _load_program(self):
        if not self._need_dbg():
            return
        text = self.program_text.get("1.0", tk.END)
        instrs = self._parse_program(text)
        if instrs is None:
            return
        try:
            self.dbg.load_program(instrs)
            self.cycle = 0
            self.cycle_var.set("Ciclo: 0")
            self.status_var.set(f"✓ {len(instrs)} instrucciones cargadas")
            self._refresh_gui()
        except Exception as e:
            self.status_var.set(f"Error: {e}")

    
    _REG_MAP: dict = {}   # filled at first use

    def _init_reg_map(self):
        if self._REG_MAP:
            return
        for i, name in enumerate(REG_NAMES):
            self._REG_MAP[name] = i
        self._REG_MAP["fp"] = 8   # s0/fp alias

    def _pr(self, parts, idx, line_no):
        self._init_reg_map()
        s = parts[idx].strip().lower()
        if s.startswith("x"):
            try:
                r = int(s[1:])
                if 0 <= r <= 31:
                    return r
            except ValueError:
                pass
        if s in self._REG_MAP:
            return self._REG_MAP[s]
        raise ValueError(f"Línea {line_no}: registro desconocido '{s}'")

    def _pi(self, parts, idx, line_no):
        try:
            return int(parts[idx].strip(), 0)
        except (ValueError, IndexError):
            raise ValueError(f"Línea {line_no}: immediate inválido '{parts[idx]}'")

    def _parse_program(self, text: str):
        from riscv_instr import (
            ADDI, ADD, SUB, AND, OR, XOR, SLL, SRL, SRA,
            SLLI, SRLI, SRAI,
            SLT, SLTU, ANDI, ORI, XORI, SLTI, SLTIU,
            SW, LW, BNE, BEQ, BLT, BGE,
            NOP, HALT, JAL, JALR, LUI, AUIPC,
        )
        DISPATCH = {
            "NOP":   lambda p, n: NOP(),
            "HALT":  lambda p, n: HALT(),
            "ADDI":  lambda p, n: ADDI( self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "ADD":   lambda p, n: ADD(  self._pr(p,1,n), self._pr(p,2,n), self._pr(p,3,n)),
            "SUB":   lambda p, n: SUB(  self._pr(p,1,n), self._pr(p,2,n), self._pr(p,3,n)),
            "AND":   lambda p, n: AND(  self._pr(p,1,n), self._pr(p,2,n), self._pr(p,3,n)),
            "OR":    lambda p, n: OR(   self._pr(p,1,n), self._pr(p,2,n), self._pr(p,3,n)),
            "XOR":   lambda p, n: XOR(  self._pr(p,1,n), self._pr(p,2,n), self._pr(p,3,n)),
            "SLL":   lambda p, n: SLL(  self._pr(p,1,n), self._pr(p,2,n), self._pr(p,3,n)),
            "SRL":   lambda p, n: SRL(  self._pr(p,1,n), self._pr(p,2,n), self._pr(p,3,n)),
            "SRA":   lambda p, n: SRA(  self._pr(p,1,n), self._pr(p,2,n), self._pr(p,3,n)),
            "SLLI":  lambda p, n: SLLI( self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "SRLI":  lambda p, n: SRLI( self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "SRAI":  lambda p, n: SRAI( self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "SLT":   lambda p, n: SLT(  self._pr(p,1,n), self._pr(p,2,n), self._pr(p,3,n)),
            "SLTU":  lambda p, n: SLTU( self._pr(p,1,n), self._pr(p,2,n), self._pr(p,3,n)),
            "ANDI":  lambda p, n: ANDI( self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "ORI":   lambda p, n: ORI(  self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "XORI":  lambda p, n: XORI( self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "SLTI":  lambda p, n: SLTI( self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "SLTIU": lambda p, n: SLTIU(self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "SW":    lambda p, n: SW(   self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "LW":    lambda p, n: LW(   self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "BNE":   lambda p, n: BNE(  self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "BEQ":   lambda p, n: BEQ(  self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "BLT":   lambda p, n: BLT(  self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "BGE":   lambda p, n: BGE(  self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "JAL":   lambda p, n: JAL(  self._pr(p,1,n), self._pi(p,2,n)),
            "JALR":  lambda p, n: JALR( self._pr(p,1,n), self._pr(p,2,n), self._pi(p,3,n)),
            "LUI":   lambda p, n: LUI(  self._pr(p,1,n), self._pi(p,2,n)),
            "AUIPC": lambda p, n: AUIPC(self._pr(p,1,n), self._pi(p,2,n)),
        }
        instrs = []
        for line_no, raw in enumerate(text.splitlines(), 1):
            line = raw.split("#")[0].strip()
            if not line:
                continue
            parts = line.replace(",", " ").split()
            op = parts[0].upper()
            if op not in DISPATCH:
                messagebox.showerror(
                    "Error de parseo",
                    f"Línea {line_no}: opcode desconocido '{op}'\n\n{raw}")
                return None
            try:
                instrs.append(DISPATCH[op](parts, line_no))
            except Exception as e:
                messagebox.showerror("Error de parseo", str(e))
                return None
        return instrs

    # ── State refresh ─────────────────────────────────────────────
    def _refresh_gui(self):
        if not self.dbg:
            return
        try:
            self._update_pipeline()
            self._update_registers()
            self._update_memory()
        except Exception as e:
            self.status_var.set(f"Error leyendo estado: {e}")

    def _update_pipeline(self):
        from riscv_instr import decode

        # IF/ID
        d = self.dbg.read_ifid()
        self._sv("IF/ID", "pc",    h32(d["pc"]),    BLUE)
        self._sv("IF/ID", "pc4",   h32(d["pc4"]),   SUBTEXT)
        self._sv("IF/ID", "instr", h32(d["instr"]), PEACH)
        try:
            asm = decode(d["instr"], d["pc"])
        except Exception:
            asm = "?"
        self._sv("IF/ID", "asm", asm, GREEN)

        # ID/EX
        d = self.dbg.read_idex()
        self._sv("ID/EX", "pc",
                 h32(d["pc"]), BLUE)
        self._sv("ID/EX", "rs1",
                 f"{h32(d['rs1_data'])}  (x{d['rs1_addr']})", TEXT)
        self._sv("ID/EX", "rs2",
                 f"{h32(d['rs2_data'])}  (x{d['rs2_addr']})", TEXT)
        self._sv("ID/EX", "imm",
                 f"{h32(d['imm'])}  ({s32(d['imm']):+d})", YELLOW)
        self._sv("ID/EX", "rd",
                 f"x{d['rd']}", MAUVE)
        self._sv("ID/EX", "ctrl",
                 (f"ALU={d['alu_op']:04b} S={d['alu_src']} "
                  f"MR={d['mem_read']} MW={d['mem_write']} "
                  f"RW={d['reg_write']} BR={d['branch']} JMP={d['jump']}"),
                 SUBTEXT)

        # EX/MEM
        d = self.dbg.read_exmem()
        self._sv("EX/MEM", "pc4",  h32(d["pc4"]), SUBTEXT)
        self._sv("EX/MEM", "alu",
                 f"{h32(d['alu_result'])}  ({s32(d['alu_result']):+d})", PEACH)
        self._sv("EX/MEM", "rs2",  h32(d["rs2_data"]), TEXT)
        self._sv("EX/MEM", "btgt", h32(d["branch_target"]), YELLOW)
        self._sv("EX/MEM", "rd",   f"x{d['rd']}", MAUVE)
        bt = d["branch_taken"]
        self._sv("EX/MEM", "ctrl",
                 (f"MR={d['mem_read']} MW={d['mem_write']} "
                  f"RW={d['reg_write']} M2R={d['mem2reg']} "
                  f"BT={'1 !!!' if bt else '0'}"),
                 RED if bt else SUBTEXT)

        # MEM/WB
        d = self.dbg.read_memwb()
        self._sv("MEM/WB", "pc4",  h32(d["pc4"]),        SUBTEXT)
        self._sv("MEM/WB", "alu",  h32(d["alu_result"]),  PEACH)
        self._sv("MEM/WB", "mem",  h32(d["mem_data"]),    TEAL)
        self._sv("MEM/WB", "rd",   f"x{d['rd']}",         MAUVE)
        self._sv("MEM/WB", "ctrl",
                 f"RW={d['reg_write']} M2R={d['mem2reg']}", SUBTEXT)

    def _update_registers(self):
        for i in range(32):
            val = self.dbg.read_reg(i)
            self.reg_vars[i].set(f"{h32(val)}   ({s32(val):d})")
            if i == 0:
                self.reg_labels[i].config(fg=SUBTEXT)
            elif val != 0:
                self.reg_labels[i].config(fg=PEACH)
            else:
                self.reg_labels[i].config(fg=TEXT)

    def _update_memory(self):
        try:
            words = max(1, min(64, int(self.mem_words_var.get())))
        except ValueError:
            words = 8

        if len(self.mem_vars) != words:
            for w in self.mem_inner.winfo_children():
                w.destroy()
            self.mem_vars = []
            for i in range(words):
                row = tk.Frame(self.mem_inner, bg=BG)
                row.pack(fill=tk.X)
                tk.Label(row, text=f"[{h32(i * 4)}]", bg=BG, fg=OVERLAY,
                         font=MONO_SM, width=13, anchor=tk.W).pack(side=tk.LEFT)
                var = tk.StringVar(value="0x00000000   (0)")
                lbl = tk.Label(row, textvariable=var, bg=BG, fg=TEXT,
                               font=MONO_SM, anchor=tk.W)
                lbl.pack(side=tk.LEFT, fill=tk.X)
                self.mem_vars.append((var, lbl))

        for i, (var, lbl) in enumerate(self.mem_vars):
            val = self.dbg.read_mem(i * 4)
            var.set(f"{h32(val)}   ({s32(val):d})")
            lbl.config(fg=TEAL if val != 0 else TEXT)



def main():
    port = sys.argv[1] if len(sys.argv) > 1 else "COM4"
    baud = int(sys.argv[2]) if len(sys.argv) > 2 else 9600

    root = tk.Tk()

    style = ttk.Style()
    try:
        style.theme_use("clam")
    except Exception:
        pass
    style.configure("Vertical.TScrollbar",
                     background=SURFACE, troughcolor=BASE,
                     arrowcolor=SUBTEXT, bordercolor=BASE,
                     gripcount=0)

    DebugGUI(root, port, baud)
    root.mainloop()


if __name__ == "__main__":
    main()
