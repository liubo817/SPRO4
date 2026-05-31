import sys
import math
import struct
import numpy as np
from PyQt5 import QtWidgets, QtCore, QtGui
import pyqtgraph as pg

try:
    import serial
    SERIAL_AVAILABLE = True
except ImportError:
    SERIAL_AVAILABLE = False

# --------------------------
# Configuration
# --------------------------
USE_FAKE         = False
COM_PORT         = "COM8"
BAUD_RATE        = 115200
BASE_SAMPLE_RATE = 1_000_000   
ADC_MAX_VOLTAGE  = 10.0        
ADC_COUNTS       = 4096

def counts_to_volts(c):
    return (np.asarray(c, dtype=np.float64) - ADC_COUNTS / 2) / (ADC_COUNTS / 2) * ADC_MAX_VOLTAGE

def volts_to_counts(v):
    return v / ADC_MAX_VOLTAGE * (ADC_COUNTS / 2) + ADC_COUNTS / 2

# --------------------------
# Packet layout
# --------------------------
# Python → FPGA  (6 bytes):
#   AA 55  TRIG_HI TRIG_LO  DEC  FF
#   TRIG word (16-bit BE):
#     bit 15       : edge  — 1 = rising, 0 = falling
#     bits 14–12   : reserved
#     bits 11– 0   : trigger level 12-bit (0–4095)
#
# FPGA → Python:
#   AA 55  <4096 × uint16 BE>  (8194 B total)

SAMPLES_PER_PACKET = 4096
RAW_DATA_BYTES     = SAMPLES_PER_PACKET * 2

TIMESCALE_STEPS = [
    (1e-6,   "1 µs"),  (2e-6,  "2 µs"),  (5e-6,  "5 µs"),
    (10e-6,  "10 µs"), (20e-6, "20 µs"), (50e-6, "50 µs"),
    (100e-6, "100 µs"),(200e-6,"200 µs"),(500e-6,"500 µs"),
    (1e-3,   "1 ms"),  (2e-3,  "2 ms"),  (5e-3,  "5 ms"),
    (10e-3,  "10 ms"), (20e-3, "20 ms"), (50e-3, "50 ms"),
]

# ── Colour palette ────────────────────────────────────────────────────────────
C_BG        = "#0d0d18"   # window background
C_PANEL     = "#131320"   # control panel background
C_PLOT_BG   = "#0a0a14"   # plot background
C_GRID      = "#252540"   # grid lines
C_AXIS_TXT  = "#9090b8"   # axis tick labels
C_WAVE      = "#00ff99"   # waveform — bright green
C_TRIG_LINE = "#ff4444"   # trigger line
C_SCALE     = "#cc66ff"   # SCALE knob accent
C_TRIGGER   = "#ff4444"   # TRIGGER knob accent
C_DEC       = "#00ccff"   # DECIMATOR knob accent
C_TIME      = "#ffcc00"   # TIME/DIV knob accent
C_RISE      = "#00ff99"   # RISE edge colour
C_FALL      = "#cc66ff"   # FALL edge colour


def build_config_packet(trigger: int, dec: int, edge: int) -> bytes:
    trig    = max(0, min(4095, int(trigger)))
    dec_val = max(0, min(9,   int(dec)))
    trig_val    = ((1 if edge else 0) << 15) | (trig & 0x0FFF)
    return bytes([0xAA, 0x55, (trig_val >> 8) & 0xFF, trig_val & 0xFF, dec_val, 0xFF])


# --------------------------
# Serial reader thread
# --------------------------
class SerialReaderThread(QtCore.QThread):
    data_ready = QtCore.pyqtSignal(np.ndarray)
    status     = QtCore.pyqtSignal(str, str)

    def __init__(self, port, baud, parent=None):
        super().__init__(parent)
        self._port = port; self._baud = baud
        self._running = True; self._ser = None
        self._write_queue: list[bytes] = []
        self._queue_lock = QtCore.QMutex()

    def send(self, packet):
        QtCore.QMutexLocker(self._queue_lock)
        self._write_queue.append(packet)

    def stop(self):
        self._running = False
        if self._ser and self._ser.is_open: self._ser.close()
        self.wait(2000)

    def run(self):
        if not SERIAL_AVAILABLE:
            self.status.emit("pyserial not installed", "#ff4444"); return
        try:
            self._ser = serial.Serial(self._port, self._baud, timeout=1.5)
            self.status.emit(f"UART  ·  {self._port}  ✓", C_RISE)
        except serial.SerialException as e:
            self.status.emit(f"UART ERR  ·  {e}", "#ff4444"); return
        while self._running:
            locker = QtCore.QMutexLocker(self._queue_lock)
            pending = list(self._write_queue); self._write_queue.clear()
            locker.unlock()
            for pkt in pending:
                try: self._ser.write(pkt)
                except serial.SerialException as e:
                    self.status.emit(f"TX ERR  ·  {e}", "#ff4444")
            try:
                pkt = self._read_packet()
                if pkt is not None: self.data_ready.emit(pkt)
            except serial.SerialException as e:
                self.status.emit(f"RX ERR  ·  {e}", "#ff4444"); break
        if self._ser and self._ser.is_open: self._ser.close()

    def _read_packet(self):
        if self._ser.read(1) != b'\xAA': return None
        if self._ser.read(1) != b'\x55': return None
        raw = self._ser.read(RAW_DATA_BYTES)
        if len(raw) < RAW_DATA_BYTES: return None
        counts   = np.frombuffer(raw, dtype='>u2').astype(np.float32)
        inverted = (ADC_COUNTS - 1) - counts
        return counts_to_volts(inverted).astype(np.float32)


# --------------------------
# Knob Widget
# --------------------------
class KnobWidget(QtWidgets.QWidget):
    valueChanged = QtCore.pyqtSignal(int)

    def __init__(self, label, min_val, max_val, default,
                 unit="", accent=C_DEC, parent=None):
        super().__init__(parent)
        self.label = label; self.unit = unit
        self.accent = QtGui.QColor(accent)
        self.min_val = min_val; self.max_val = max_val
        self._value = default
        self._dragging = False; self._last_y = 0
        self.setFixedSize(150, 168)
        self.setCursor(QtCore.Qt.SizeVerCursor)
        self.setToolTip(f"Drag ↑↓ or scroll  •  {min_val}–{max_val}{unit}")

    @property
    def value(self): return self._value

    @value.setter
    def value(self, v):
        v = max(self.min_val, min(self.max_val, int(v)))
        if v != self._value:
            self._value = v; self.valueChanged.emit(v); self.update()

    def mousePressEvent(self, e):
        if e.button() == QtCore.Qt.LeftButton:
            self._dragging = True; self._last_y = e.y()

    def mouseMoveEvent(self, e):
        if self._dragging:
            dy = self._last_y - e.y()
            self.value = self._value + dy * max(1, (self.max_val - self.min_val) // 150)
            self._last_y = e.y()

    def mouseReleaseEvent(self, _): self._dragging = False

    def wheelEvent(self, e):
        self.value = self._value + (max(1, (self.max_val - self.min_val) // 150)
                                    * (1 if e.angleDelta().y() > 0 else -1))

    def paintEvent(self, _):
        p = QtGui.QPainter(self)
        p.setRenderHint(QtGui.QPainter.Antialiasing)
        W, H   = self.width(), self.height()
        cx, cy = W // 2, 66
        R_arc = 52; R_knob = 38
        START = 225.0; SWEEP = -270.0

        norm         = (self._value - self.min_val) / max(1, self.max_val - self.min_val)
        filled_sweep = SWEEP * norm

        # glow halo
        glow = QtGui.QRadialGradient(cx, cy, R_arc + 14)
        glow.setColorAt(0.0, QtGui.QColor(self.accent.red(), self.accent.green(),
                                          self.accent.blue(), 28))
        glow.setColorAt(1.0, QtGui.QColor(0, 0, 0, 0))
        p.setBrush(glow); p.setPen(QtCore.Qt.NoPen)
        p.drawEllipse(QtCore.QPointF(cx, cy), R_arc + 14, R_arc + 14)

        arc_rect = QtCore.QRectF(cx - R_arc, cy - R_arc, 2*R_arc, 2*R_arc)

        # track
        p.setPen(QtGui.QPen(QtGui.QColor("#1e1e38"), 7,
                            QtCore.Qt.SolidLine, QtCore.Qt.RoundCap))
        p.drawArc(arc_rect, int(START * 16), int(SWEEP * 16))

        # filled arc
        p.setPen(QtGui.QPen(self.accent, 7,
                            QtCore.Qt.SolidLine, QtCore.Qt.RoundCap))
        p.drawArc(arc_rect, int(START * 16), int(filled_sweep * 16))

        # knob body
        grad = QtGui.QRadialGradient(cx - 9, cy - 9, R_knob * 1.7)
        grad.setColorAt(0.0, QtGui.QColor("#3a3a58"))
        grad.setColorAt(1.0, QtGui.QColor("#111120"))
        p.setBrush(grad)
        p.setPen(QtGui.QPen(QtGui.QColor(self.accent.red(), self.accent.green(),
                                         self.accent.blue(), 80), 2))
        p.drawEllipse(QtCore.QPointF(cx, cy), R_knob, R_knob)

        # indicator dot
        angle_rad = math.radians(-(START + filled_sweep))
        p.setBrush(self.accent); p.setPen(QtCore.Qt.NoPen)
        p.drawEllipse(QtCore.QPointF(
            cx + (R_knob - 7) * math.cos(angle_rad),
            cy + (R_knob - 7) * math.sin(angle_rad)), 5, 5)

        # label
        p.setPen(QtGui.QColor("#7070a0"))
        f = QtGui.QFont("Consolas", 9)
        f.setLetterSpacing(QtGui.QFont.AbsoluteSpacing, 2)
        f.setBold(True)
        p.setFont(f)
        p.drawText(0, H - 52, W, 20, QtCore.Qt.AlignCenter, self.label)

        # value
        p.setPen(self.accent)
        p.setFont(QtGui.QFont("Consolas", 13, QtGui.QFont.Bold))
        p.drawText(0, H - 30, W, 26, QtCore.Qt.AlignCenter,
                   f"{self._value}{self.unit}")
        p.end()


# --------------------------
# Edge Toggle Button
# --------------------------
class EdgeToggle(QtWidgets.QPushButton):
    edgeChanged = QtCore.pyqtSignal(int)   # 1=rise, 0=fall

    def __init__(self, parent=None):
        super().__init__(parent)
        self._edge = 1
        self.setFixedSize(110, 64)
        self.setCursor(QtCore.Qt.PointingHandCursor)
        self.clicked.connect(self._toggle)
        self._refresh()

    @property
    def edge(self): return self._edge

    def _toggle(self):
        self._edge = 1 - self._edge
        self._refresh(); self.edgeChanged.emit(self._edge)

    def _refresh(self):
        label  = "↑  RISE" if self._edge else "↓  FALL"
        colour = C_RISE    if self._edge else C_FALL
        self.setText(label)
        self.setStyleSheet(f"""
            QPushButton {{
                color: {colour};
                background: #1a1a2e;
                border: 2px solid {colour};
                border-radius: 8px;
                font-family: Consolas;
                font-size: 14px;
                font-weight: bold;
                letter-spacing: 2px;
                padding: 6px 12px;
            }}
            QPushButton:hover   {{ background: #242440; }}
            QPushButton:pressed {{ background: #0d0d1a; }}
        """)


# --------------------------
# Timescale Knob
# --------------------------
class TimescaleKnob(QtWidgets.QWidget):
    indexChanged = QtCore.pyqtSignal(int)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.accent = QtGui.QColor(C_TIME)
        self._index = 0; self._dragging = False
        self._last_y = 0; self._accum = 0
        self.setFixedSize(150, 168)
        self.setCursor(QtCore.Qt.SizeVerCursor)
        self.setToolTip("Drag ↑↓ or scroll  •  time / division")

    @property
    def index(self): return self._index

    @index.setter
    def index(self, v):
        v = max(0, min(len(TIMESCALE_STEPS) - 1, int(v)))
        if v != self._index:
            self._index = v; self.indexChanged.emit(v); self.update()

    @property
    def seconds_per_div(self): return TIMESCALE_STEPS[self._index][0]

    def mousePressEvent(self, e):
        if e.button() == QtCore.Qt.LeftButton:
            self._dragging = True; self._last_y = e.y(); self._accum = 0

    def mouseMoveEvent(self, e):
        if self._dragging:
            self._accum += self._last_y - e.y()
            self._last_y = e.y()
            steps = self._accum // 12
            if steps: self.index = self._index + steps; self._accum -= steps * 12

    def mouseReleaseEvent(self, _): self._dragging = False

    def wheelEvent(self, e):
        self.index = self._index + (1 if e.angleDelta().y() > 0 else -1)

    def paintEvent(self, _):
        p = QtGui.QPainter(self)
        p.setRenderHint(QtGui.QPainter.Antialiasing)
        W, H = self.width(), self.height()
        cx, cy = W // 2, 66
        R_arc = 52; R_knob = 38
        START = 225.0; SWEEP = -270.0
        norm         = self._index / max(1, len(TIMESCALE_STEPS) - 1)
        filled_sweep = SWEEP * norm

        glow = QtGui.QRadialGradient(cx, cy, R_arc + 14)
        glow.setColorAt(0.0, QtGui.QColor(self.accent.red(), self.accent.green(),
                                          self.accent.blue(), 28))
        glow.setColorAt(1.0, QtGui.QColor(0, 0, 0, 0))
        p.setBrush(glow); p.setPen(QtCore.Qt.NoPen)
        p.drawEllipse(QtCore.QPointF(cx, cy), R_arc + 14, R_arc + 14)

        arc_rect = QtCore.QRectF(cx - R_arc, cy - R_arc, 2*R_arc, 2*R_arc)
        p.setPen(QtGui.QPen(QtGui.QColor("#1e1e38"), 7,
                            QtCore.Qt.SolidLine, QtCore.Qt.RoundCap))
        p.drawArc(arc_rect, int(START * 16), int(SWEEP * 16))
        p.setPen(QtGui.QPen(self.accent, 7,
                            QtCore.Qt.SolidLine, QtCore.Qt.RoundCap))
        p.drawArc(arc_rect, int(START * 16), int(filled_sweep * 16))

        grad = QtGui.QRadialGradient(cx - 9, cy - 9, R_knob * 1.7)
        grad.setColorAt(0.0, QtGui.QColor("#3a3a58"))
        grad.setColorAt(1.0, QtGui.QColor("#111120"))
        p.setBrush(grad)
        p.setPen(QtGui.QPen(QtGui.QColor(self.accent.red(), self.accent.green(),
                                         self.accent.blue(), 80), 2))
        p.drawEllipse(QtCore.QPointF(cx, cy), R_knob, R_knob)

        angle_rad = math.radians(-(START + filled_sweep))
        p.setBrush(self.accent); p.setPen(QtCore.Qt.NoPen)
        p.drawEllipse(QtCore.QPointF(
            cx + (R_knob - 7) * math.cos(angle_rad),
            cy + (R_knob - 7) * math.sin(angle_rad)), 5, 5)

        p.setPen(QtGui.QColor("#7070a0"))
        f = QtGui.QFont("Consolas", 9)
        f.setLetterSpacing(QtGui.QFont.AbsoluteSpacing, 2); f.setBold(True)
        p.setFont(f)
        p.drawText(0, H - 52, W, 20, QtCore.Qt.AlignCenter, "TIME/DIV")
        p.setPen(self.accent)
        p.setFont(QtGui.QFont("Consolas", 13, QtGui.QFont.Bold))
        p.drawText(0, H - 30, W, 26, QtCore.Qt.AlignCenter,
                   TIMESCALE_STEPS[self._index][1])
        p.end()


# --------------------------
# Stats Bar
# --------------------------
class StatsBar(QtWidgets.QWidget):
    _STATS = [
        ("MAX",  C_TRIGGER),
        ("MIN",  C_SCALE),
        ("P-P",  "#ffcc00"),
        ("MEAN", "#aaaacc"),
        ("RMS",  C_DEC),
        ("FREQ", "#00ff88"),
        ("DC%",  "#ff8844"),
    ]

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(
            f"background:{C_PANEL}; border-radius:10px;"
            f"border: 1px solid #252540;")
        layout = QtWidgets.QHBoxLayout(self)
        layout.setContentsMargins(24, 10, 24, 10)
        layout.setSpacing(0)
        self._val_labels: dict[str, QtWidgets.QLabel] = {}

        for i, (name, colour) in enumerate(self._STATS):
            if i:
                sep = QtWidgets.QFrame()
                sep.setFrameShape(QtWidgets.QFrame.VLine)
                sep.setStyleSheet(f"color:{C_GRID}; background:{C_GRID}; max-width:1px;")
                layout.addWidget(sep)

            col = QtWidgets.QVBoxLayout()
            col.setSpacing(3)

            lbl = QtWidgets.QLabel(name)
            lbl.setStyleSheet(
                f"color:#6060a0; font-family:Consolas; font-size:11px;"
                "font-weight:bold; letter-spacing:2px; background:transparent;")
            lbl.setAlignment(QtCore.Qt.AlignCenter)

            val = QtWidgets.QLabel("—")
            val.setStyleSheet(
                f"color:{colour}; font-family:Consolas; font-size:18px;"
                "font-weight:bold; background:transparent;")
            val.setAlignment(QtCore.Qt.AlignCenter)
            val.setMinimumWidth(130)

            col.addWidget(lbl); col.addWidget(val)
            layout.addLayout(col)
            self._val_labels[name] = val

        layout.addStretch()

    def update_stats(self, data: np.ndarray, sample_rate: float):
        if data is None or len(data) == 0: return
        mx   = float(np.max(data));  mn = float(np.min(data))
        pp   = mx - mn;              mean = float(np.mean(data))
        rms  = float(np.sqrt(np.mean(data**2)))
        windowed = (data - mean) * np.hanning(len(data))
        fft_mag  = np.abs(np.fft.rfft(windowed))
        freqs    = np.fft.rfftfreq(len(data), d=1.0 / sample_rate)
        freq     = float(freqs[int(np.argmax(fft_mag[1:])) + 1]) if len(fft_mag) > 1 else 0.0
        dc_pct   = mean / ADC_MAX_VOLTAGE * 100.0

        freq_str = (f"{freq/1e6:.3f} MHz" if freq >= 1e6 else
                    f"{freq/1e3:.2f} kHz"  if freq >= 1e3 else
                    f"{freq:.1f} Hz"        if freq >= 1   else
                    f"{freq*1e3:.1f} mHz")

        self._val_labels["MAX" ].setText(f"{mx:+.3f} V")
        self._val_labels["MIN" ].setText(f"{mn:+.3f} V")
        self._val_labels["P-P" ].setText(f"{pp:.3f} V")
        self._val_labels["MEAN"].setText(f"{mean:+.3f} V")
        self._val_labels["RMS" ].setText(f"{rms:.3f} V")
        self._val_labels["FREQ"].setText(freq_str)
        self._val_labels["DC%" ].setText(f"{dc_pct:+.1f} %")


# --------------------------
# Oscilloscope App
# --------------------------
class OscilloscopeApp(QtWidgets.QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Python Oscilloscope")
        self.setStyleSheet(f"background-color:{C_BG};")

        central = QtWidgets.QWidget()
        self.setCentralWidget(central)
        root = QtWidgets.QVBoxLayout(central)
        root.setContentsMargins(16, 16, 16, 16)
        root.setSpacing(10)

        # ── Plot ─────────────────────────────────────────────────────────────
        self.plot_widget = pg.PlotWidget()
        self.plot_widget.setBackground(C_PLOT_BG)
        self.plot_widget.setTitle(
            "<span style='color:#00ff99;font-family:Consolas;"
            "font-size:13pt;font-weight:bold;letter-spacing:3px'>"
            "OSCILLOSCOPE</span>")

        for axis in ('left', 'bottom'):
            ax = self.plot_widget.getAxis(axis)
            ax.setPen(pg.mkPen(C_GRID, width=1))
            ax.setTextPen(pg.mkPen(C_AXIS_TXT))
            ax.tickFont = QtGui.QFont("Consolas", 10)

        self.plot_widget.getAxis('left').setLabel(
            'Voltage', units='V',
            **{'color': C_AXIS_TXT, 'font-size': '11pt', 'font-family': 'Consolas'})
        self.plot_widget.showGrid(x=True, y=True, alpha=0.25)
        self.plot_widget.setYRange(-ADC_MAX_VOLTAGE, ADC_MAX_VOLTAGE)

        # subtle border around plot
        self.plot_widget.setStyleSheet(
            f"border: 1px solid {C_GRID}; border-radius: 6px;")

        self.curve = self.plot_widget.plot(
            pen=pg.mkPen(C_WAVE, width=2))
        root.addWidget(self.plot_widget, stretch=1)

        self.trigger_line = pg.InfiniteLine(
            angle=0, movable=False,
            pen=pg.mkPen(color=C_TRIG_LINE, width=2,
                         style=QtCore.Qt.DashLine))
        self.plot_widget.addItem(self.trigger_line)

        # ── Stats bar ────────────────────────────────────────────────────────
        self.stats_bar = StatsBar()
        self.stats_bar.setFixedHeight(80)
        root.addWidget(self.stats_bar)

        # ── Control panel ────────────────────────────────────────────────────
        panel = QtWidgets.QWidget()
        panel.setStyleSheet(
            f"background:{C_PANEL}; border-radius:12px;"
            f"border: 1px solid {C_GRID};")
        panel_layout = QtWidgets.QHBoxLayout(panel)
        panel_layout.setContentsMargins(24, 8, 24, 8)
        panel_layout.setSpacing(0)

        hdr = QtWidgets.QLabel("CONTROLS")
        hdr.setStyleSheet(
            "color:#303060; font-family:Consolas; font-size:10px;"
            "font-weight:bold; letter-spacing:4px; background:transparent;")
        hdr.setAlignment(QtCore.Qt.AlignLeft | QtCore.Qt.AlignVCenter)
        panel_layout.addWidget(hdr)
        panel_layout.addStretch()

        self.knob_voltage = KnobWidget("SCALE",    1, 10,   1, "×", C_SCALE)
        self.knob_trigger = KnobWidget("TRIGGER",  0, 4095, 2048, "", C_TRIGGER)
        self.knob_dec     = KnobWidget("DECIMATOR",0, 9,    0, "",  C_DEC)
        self.knob_time    = TimescaleKnob()

        for knob in (self.knob_voltage, self.knob_trigger,
                     self.knob_dec, self.knob_time):
            panel_layout.addWidget(knob)
            panel_layout.addSpacing(16)

        # EDGE button column
        edge_col = QtWidgets.QVBoxLayout()
        edge_lbl = QtWidgets.QLabel("EDGE")
        edge_lbl.setStyleSheet(
            f"color:#7070a0; font-family:Consolas; font-size:11px;"
            "font-weight:bold; letter-spacing:2px; background:transparent;")
        edge_lbl.setAlignment(QtCore.Qt.AlignCenter)
        self.edge_toggle = EdgeToggle()
        edge_col.addStretch()
        edge_col.addWidget(edge_lbl, alignment=QtCore.Qt.AlignCenter)
        edge_col.addSpacing(6)
        edge_col.addWidget(self.edge_toggle, alignment=QtCore.Qt.AlignCenter)
        edge_col.addStretch()
        panel_layout.addLayout(edge_col)
        panel_layout.addSpacing(20)
        panel_layout.addStretch()

        # UART status (bottom-right)
        self.uart_status = QtWidgets.QLabel("UART  ·  not connected")
        self.uart_status.setStyleSheet(
            "color:#303060; font-family:Consolas; font-size:20px;"
            "background:transparent;")
        self.uart_status.setAlignment(QtCore.Qt.AlignRight | QtCore.Qt.AlignVCenter)
        panel_layout.addWidget(self.uart_status)

        root.addWidget(panel)

        # ── Signals ──────────────────────────────────────────────────────────
        self.knob_voltage.valueChanged.connect(self._on_controls_changed)
        self.knob_trigger.valueChanged.connect(self._on_controls_changed)
        self.knob_dec.valueChanged.connect(self._on_controls_changed)
        self.knob_time.indexChanged.connect(self._on_controls_changed)
        self.edge_toggle.edgeChanged.connect(self._on_controls_changed)

        # ── Data buffer ───────────────────────────────────────────────────────
        self._n_show = SAMPLES_PER_PACKET
        self.data    = np.zeros(SAMPLES_PER_PACKET, dtype=np.float32)
        self._apply_visuals()

        # ── Serial / fake timer ───────────────────────────────────────────────
        self._serial_thread = None
        if USE_FAKE:
            self._set_status("FAKE DATA  ·  demo mode", C_SCALE)
            self._fake_timer = QtCore.QTimer(self)
            self._fake_timer.timeout.connect(self._on_fake_tick)
            self._fake_timer.start(30)
        else:
            self._serial_thread = SerialReaderThread(COM_PORT, BAUD_RATE, self)
            self._serial_thread.data_ready.connect(self._on_serial_data)
            self._serial_thread.status.connect(self._set_status)
            self._serial_thread.start()
            QtCore.QTimer.singleShot(100, lambda: self._send_config(log=False))

        self._plot_timer = QtCore.QTimer(self)
        self._plot_timer.timeout.connect(self._refresh_plot)
        self._plot_timer.start(30)

        self.resize(1400, 820)

    # ── Helpers ───────────────────────────────────────────────────────────────
    def _set_status(self, text, colour="#303060"):
        self.uart_status.setText(text)
        self.uart_status.setStyleSheet(
            f"color:{colour}; font-family:Consolas; font-size:18px;"
            "background:transparent;")

    def _effective_sample_rate(self):
        return BASE_SAMPLE_RATE / (2 ** self.knob_dec.value)

    def _apply_visuals(self):
        scale   = max(1, self.knob_voltage.value)
        v_range = ADC_MAX_VOLTAGE / scale
        self.plot_widget.setYRange(-v_range, v_range)

        spd      = self.knob_time.seconds_per_div
        t_window = spd * 10
        sr       = self._effective_sample_rate()
        self._n_show = max(2, min(SAMPLES_PER_PACKET, int(t_window * sr)))
        self.plot_widget.setXRange(0, t_window)
        self.plot_widget.getAxis('bottom').setLabel(
            'Time', units='s',
            **{'color': C_AXIS_TXT, 'font-size': '11pt', 'font-family': 'Consolas'})

        trig_v = float(counts_to_volts(self.knob_trigger.value))
        self.trigger_line.setValue(trig_v)

    def _send_config(self, log=True):
        trig = self.knob_trigger.value
        dec  = self.knob_dec.value
        edge = self.edge_toggle.edge
        pkt  = build_config_packet(trig, dec, edge)
        if self._serial_thread: self._serial_thread.send(pkt)
        if log:
            trig_v = float(counts_to_volts(trig))
            self._set_status(
                f"TX  ·  TRIG={trig} ({trig_v:+.2f}V)  DEC={dec}"
                f"  EDGE={'RISE' if edge else 'FALL'}"
                f"  [{pkt.hex(' ').upper()}]", C_DEC)

    # ── Slots ─────────────────────────────────────────────────────────────────
    def _on_controls_changed(self, _=None):
        self._apply_visuals(); self._send_config()

    def _on_serial_data(self, data):
        self.data = data
        self.stats_bar.update_stats(self.data, self._effective_sample_rate())

    def _on_fake_tick(self):
        t      = np.linspace(0, 2 * np.pi * 3, SAMPLES_PER_PACKET, dtype=np.float32)
        noise  = np.random.normal(0, 0.15, SAMPLES_PER_PACKET).astype(np.float32)
        signal = 15.0 * np.sin(t) + noise
        self.data = np.clip(signal, -ADC_MAX_VOLTAGE, ADC_MAX_VOLTAGE)
        self.stats_bar.update_stats(self.data, self._effective_sample_rate())

    def _refresh_plot(self):
        sr     = self._effective_sample_rate()
        n      = min(getattr(self, '_n_show', SAMPLES_PER_PACKET), len(self.data))
        t_axis = np.arange(n, dtype=np.float32) / sr
        self.curve.setData(t_axis, self.data[:n])

    def closeEvent(self, event):
        if self._serial_thread: self._serial_thread.stop()
        super().closeEvent(event)


# --------------------------
# Entry point
# --------------------------
if __name__ == "__main__":
    app = QtWidgets.QApplication(sys.argv)
    app.setStyle("Fusion")
    window = OscilloscopeApp()
    window.show()
    sys.exit(app.exec_())