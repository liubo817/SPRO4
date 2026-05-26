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
# ★ FIX 3: Default to fake data so the window shows a waveform immediately
#   without hardware.  Set to False (and set COM_PORT) once your FPGA is
#   connected.
USE_FAKE         = False
COM_PORT         = "COM8"          # <-- change to your actual port (e.g. "COM3", "/dev/ttyUSB0")
BAUD_RATE        = 115200
BASE_SAMPLE_RATE = 1_000_000   # Hz — ADC clock before decimation
ADC_MAX_VOLTAGE  = 10.0        # V — full-scale voltage (4096 counts = 10 V)
ADC_COUNTS       = 4096        # counts at full scale

# Conversion helpers
# ADC midpoint (2048) → 0 V;  count 4096 → +20 V;  count 0 → -20 V
def counts_to_volts(c):
    return (np.asarray(c, dtype=np.float64) - ADC_COUNTS / 2) / (ADC_COUNTS / 2) * ADC_MAX_VOLTAGE

def volts_to_counts(v):
    return v / ADC_MAX_VOLTAGE * (ADC_COUNTS / 2) + ADC_COUNTS / 2

# --------------------------
# Packet layout
# --------------------------
# Python → FPGA  (6 bytes):
#   AA 55  TRIG_HI TRIG_LO  DEC  FF
#
#   AA 55        : header
#   TRIG_HI/LO  : trigger level 12-bit big-endian (0–4095)
#   DEC          : decimator  (0–9)
#   FF           : end marker
#
# FPGA → Python:
#   AA 55  DATA
#
#   AA 55  : header (2 B)
#   DATA   : 4096 × uint16 big-endian = 8192 B

SAMPLES_PER_PACKET = 4096
RAW_DATA_BYTES     = SAMPLES_PER_PACKET * 2   # 8192


def build_config_packet(trigger: int, dec: int) -> bytes:
    trig    = max(0,   min(4095, int(trigger)))
    dec_val = max(0,   min(9,    int(dec)))
    trig_hi = (trig >> 8) & 0xFF
    trig_lo =  trig       & 0xFF
    return bytes([0xAA, 0x55, trig_hi, trig_lo, dec_val, 0xFF])


# --------------------------
# Async serial reader thread
# --------------------------
class SerialReaderThread(QtCore.QThread):
    data_ready = QtCore.pyqtSignal(np.ndarray)
    status     = QtCore.pyqtSignal(str, str)

    def __init__(self, port: str, baud: int, parent=None):
        super().__init__(parent)
        self._port        = port
        self._baud        = baud
        self._running     = True
        self._ser         = None
        self._write_queue: list[bytes] = []
        self._queue_lock  = QtCore.QMutex()

    def send(self, packet: bytes):
        locker = QtCore.QMutexLocker(self._queue_lock)
        self._write_queue.append(packet)

    def stop(self):
        self._running = False
        if self._ser and self._ser.is_open:
            self._ser.close()
        self.wait(2000)

    def run(self):
        if not SERIAL_AVAILABLE:
            self.status.emit("pyserial not installed", "#ff5555")
            return
        try:
            # ★ FIX 1: timeout was 0.1 s — far too short.
            # 8192 bytes at 115200 baud takes ~714 ms, so serial.read(8192)
            # always returned early (~1152 bytes), _read_packet returned None,
            # and the plot stayed blank even with the FPGA connected.
            # 1.5 s gives comfortable headroom for a full frame.
            self._ser = serial.Serial(self._port, self._baud, timeout=1.5)
            self.status.emit(f"UART  ·  {self._port}  ✓", "#00e5ff")
        except serial.SerialException as exc:
            self.status.emit(f"UART ERR  ·  {exc}", "#ff5555")
            return

        while self._running:
            locker = QtCore.QMutexLocker(self._queue_lock)
            pending = list(self._write_queue)
            self._write_queue.clear()
            locker.unlock()

            for pkt in pending:
                try:
                    self._ser.write(pkt)
                except serial.SerialException as exc:
                    self.status.emit(f"TX ERR  ·  {exc}", "#ff5555")

            try:
                # ★ FIX 2: removed the `if self._ser.in_waiting:` guard.
                # in_waiting only counts bytes already in the OS buffer at
                # that instant.  Gating on it meant we'd enter _read_packet
                # when only a few bytes had arrived, consume the AA 55 header,
                # then fail the body read — permanently desyncing the stream.
                # A blocking read with the corrected timeout (Fix 1) is safe.
                pkt = self._read_packet()
                if pkt is not None:
                    self.data_ready.emit(pkt)
            except serial.SerialException as exc:
                self.status.emit(f"RX ERR  ·  {exc}", "#ff5555")
                break

        if self._ser and self._ser.is_open:
            self._ser.close()

    def _read_packet(self) -> np.ndarray | None:
        """
        FPGA → Python:  AA 55  <4096 × uint16 BE>
        Returns float32 array in volts (inverted for op-amp, centred at 0 V).
        """
        b = self._ser.read(1)
        if b != b'\xAA':
            return None
        if self._ser.read(1) != b'\x55':
            return None
        raw = self._ser.read(RAW_DATA_BYTES)
        if len(raw) < RAW_DATA_BYTES:
            return None
        counts = np.frombuffer(raw, dtype='>u2').astype(np.float32)
        inverted = (ADC_COUNTS - 1) - counts          # flip for inverting op-amp
        return counts_to_volts(inverted).astype(np.float32)


# --------------------------
# Virtual Knob Widget
# --------------------------
class KnobWidget(QtWidgets.QWidget):
    valueChanged = QtCore.pyqtSignal(int)

    def __init__(self, label: str, min_val: int, max_val: int,
                 default: int, unit: str = "", accent: str = "#00e5ff",
                 parent=None):
        super().__init__(parent)
        self.label     = label
        self.unit      = unit
        self.accent    = QtGui.QColor(accent)
        self.min_val   = min_val
        self.max_val   = max_val
        self._value    = default
        self._dragging = False
        self._last_y   = 0

        self.setFixedSize(120, 140)
        self.setCursor(QtCore.Qt.SizeVerCursor)
        self.setToolTip(
            f"Drag ↑↓ or scroll  •  range {min_val}–{max_val}{unit}")

    @property
    def value(self):
        return self._value

    @value.setter
    def value(self, v):
        v = max(self.min_val, min(self.max_val, int(v)))
        if v != self._value:
            self._value = v
            self.valueChanged.emit(v)
            self.update()

    def mousePressEvent(self, e):
        if e.button() == QtCore.Qt.LeftButton:
            self._dragging = True
            self._last_y   = e.y()

    def mouseMoveEvent(self, e):
        if self._dragging:
            dy   = self._last_y - e.y()
            step = max(1, (self.max_val - self.min_val) // 120)
            self.value   = self._value + dy * step
            self._last_y = e.y()

    def mouseReleaseEvent(self, _):
        self._dragging = False

    def wheelEvent(self, e):
        step = max(1, (self.max_val - self.min_val) // 120)
        self.value = self._value + (step if e.angleDelta().y() > 0 else -step)

    def paintEvent(self, _):
        p = QtGui.QPainter(self)
        p.setRenderHint(QtGui.QPainter.Antialiasing)

        W, H   = self.width(), self.height()
        cx, cy = W // 2, 56
        R_arc  = 42
        R_knob = 30
        START  =  225.0
        SWEEP  = -270.0

        norm         = (self._value - self.min_val) / max(1, self.max_val - self.min_val)
        filled_sweep = SWEEP * norm

        glow = QtGui.QRadialGradient(cx, cy, R_arc + 8)
        glow.setColorAt(0.0, QtGui.QColor(
            self.accent.red(), self.accent.green(), self.accent.blue(), 18))
        glow.setColorAt(1.0, QtGui.QColor(0, 0, 0, 0))
        p.setBrush(glow)
        p.setPen(QtCore.Qt.NoPen)
        p.drawEllipse(QtCore.QPointF(cx, cy), R_arc + 8, R_arc + 8)

        arc_rect = QtCore.QRectF(cx - R_arc, cy - R_arc, 2*R_arc, 2*R_arc)
        p.setPen(QtGui.QPen(QtGui.QColor("#22223a"), 5,
                            QtCore.Qt.SolidLine, QtCore.Qt.RoundCap))
        p.drawArc(arc_rect, int(START * 16), int(SWEEP * 16))

        p.setPen(QtGui.QPen(self.accent, 5,
                            QtCore.Qt.SolidLine, QtCore.Qt.RoundCap))
        p.drawArc(arc_rect, int(START * 16), int(filled_sweep * 16))

        grad = QtGui.QRadialGradient(cx - 7, cy - 7, R_knob * 1.6)
        grad.setColorAt(0.0, QtGui.QColor("#38384e"))
        grad.setColorAt(1.0, QtGui.QColor("#14141c"))
        p.setBrush(grad)
        p.setPen(QtGui.QPen(QtGui.QColor("#33334a"), 1))
        p.drawEllipse(QtCore.QPointF(cx, cy), R_knob, R_knob)

        angle_rad = math.radians(-(START + filled_sweep))
        dot_x = cx + (R_knob - 6) * math.cos(angle_rad)
        dot_y = cy + (R_knob - 6) * math.sin(angle_rad)
        p.setBrush(self.accent)
        p.setPen(QtCore.Qt.NoPen)
        p.drawEllipse(QtCore.QPointF(dot_x, dot_y), 4, 4)

        p.setPen(QtGui.QColor("#888899"))
        f_lbl = QtGui.QFont("Consolas", 8)
        f_lbl.setLetterSpacing(QtGui.QFont.AbsoluteSpacing, 1.5)
        p.setFont(f_lbl)
        p.drawText(0, H - 44, W, 18, QtCore.Qt.AlignCenter, self.label)

        p.setPen(self.accent)
        p.setFont(QtGui.QFont("Consolas", 10, QtGui.QFont.Bold))
        p.drawText(0, H - 26, W, 22, QtCore.Qt.AlignCenter,
                   f"{self._value}{self.unit}")
        p.end()


# --------------------------
# Stats Bar Widget
# --------------------------
class StatsBar(QtWidgets.QWidget):
    """
    Shows MAX / MIN / P-P / MEAN / RMS / FREQ — all in volts.
    Call update_stats(data_volts, sample_rate) to refresh.
    """
    _STATS = [
        ("MAX",  "#ff5555"),
        ("MIN",  "#a78bfa"),
        ("P-P",  "#ffd700"),
        ("MEAN", "#888899"),
        ("RMS",  "#00e5ff"),
        ("FREQ", "#00ff88"),
        ("DC%",  "#ff8c00"),
    ]

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet("background:#10101a; border-radius:10px;")
        layout = QtWidgets.QHBoxLayout(self)
        layout.setContentsMargins(20, 8, 20, 8)
        layout.setSpacing(0)

        self._val_labels: dict[str, QtWidgets.QLabel] = {}

        for i, (name, colour) in enumerate(self._STATS):
            if i:
                sep = QtWidgets.QFrame()
                sep.setFrameShape(QtWidgets.QFrame.VLine)
                sep.setStyleSheet("color:#22223a;")
                layout.addWidget(sep)

            col = QtWidgets.QVBoxLayout()
            col.setSpacing(2)

            lbl = QtWidgets.QLabel(name)
            lbl.setStyleSheet(
                "color:#555566; font-family:Consolas; font-size:10px;"
                "letter-spacing:1.5px; background:transparent;")
            lbl.setAlignment(QtCore.Qt.AlignCenter)

            val = QtWidgets.QLabel("—")
            val.setStyleSheet(
                f"color:{colour}; font-family:Consolas; font-size:15px;"
                "font-weight:bold; background:transparent;")
            val.setAlignment(QtCore.Qt.AlignCenter)
            val.setMinimumWidth(110)

            col.addWidget(lbl)
            col.addWidget(val)
            layout.addLayout(col)
            self._val_labels[name] = val

        layout.addStretch()

    def update_stats(self, data: np.ndarray, sample_rate: float):
        if data is None or len(data) == 0:
            return

        mx   = float(np.max(data))
        mn   = float(np.min(data))
        pp   = mx - mn
        mean = float(np.mean(data))
        rms  = float(np.sqrt(np.mean(data ** 2)))

        # Dominant frequency via windowed FFT (skip DC bin 0)
        windowed = (data - mean) * np.hanning(len(data))
        fft_mag  = np.abs(np.fft.rfft(windowed))
        freqs    = np.fft.rfftfreq(len(data), d=1.0 / sample_rate)
        if len(fft_mag) > 1:
            peak_idx = int(np.argmax(fft_mag[1:])) + 1
            freq     = float(freqs[peak_idx])
        else:
            freq = 0.0

        dc_pct = mean / ADC_MAX_VOLTAGE * 100.0

        def vfmt(v):
            return f"{v:+.3f} V"

        freq_str = (f"{freq/1e6:.3f} MHz" if freq >= 1e6 else
                    f"{freq/1e3:.2f} kHz"  if freq >= 1e3 else
                    f"{freq:.1f} Hz"        if freq >= 1   else
                    f"{freq*1e3:.1f} mHz")

        self._val_labels["MAX" ].setText(vfmt(mx))
        self._val_labels["MIN" ].setText(vfmt(mn))
        self._val_labels["P-P" ].setText(f"{pp:.3f} V")
        self._val_labels["MEAN"].setText(vfmt(mean))
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
        self.setStyleSheet("background-color: #0b0b12;")

        central = QtWidgets.QWidget()
        self.setCentralWidget(central)
        root = QtWidgets.QVBoxLayout(central)
        root.setContentsMargins(14, 14, 14, 14)
        root.setSpacing(8)

        # ── Plot ─────────────────────────────────────────────────────────────
        self.plot_widget = pg.PlotWidget()
        self.plot_widget.setBackground("#0b0b12")
        self.plot_widget.setTitle(
            "<span style='color:#00e5ff;font-family:Consolas;"
            "font-size:11pt;letter-spacing:2px'>OSCILLOSCOPE DISPLAY</span>")
        for axis in ('left', 'bottom'):
            self.plot_widget.getAxis(axis).setPen(pg.mkPen("#2a2a3e"))
            self.plot_widget.getAxis(axis).setTextPen(pg.mkPen("#555566"))
        self.plot_widget.getAxis('left').setLabel('Voltage', units='V',
            **{'color': '#555566', 'font-size': '9pt'})
        self.plot_widget.showGrid(x=True, y=True, alpha=0.12)
        # initial Y range: 1× → -10 V to +10 V
        self.plot_widget.setYRange(-ADC_MAX_VOLTAGE, ADC_MAX_VOLTAGE)

        self.curve = self.plot_widget.plot(pen=pg.mkPen("#00e5ff", width=1.5))
        root.addWidget(self.plot_widget, stretch=1)

        # Trigger line lives in voltage space
        self.trigger_line = pg.InfiniteLine(
            angle=0, movable=False,
            pen=pg.mkPen(color="#ff5555", width=1, style=QtCore.Qt.DashLine))
        self.plot_widget.addItem(self.trigger_line)

        # ── Stats bar ────────────────────────────────────────────────────────
        self.stats_bar = StatsBar()
        self.stats_bar.setFixedHeight(68)
        root.addWidget(self.stats_bar)

        # ── Control panel ────────────────────────────────────────────────────
        panel = QtWidgets.QWidget()
        panel.setStyleSheet("background:#10101a; border-radius:10px;")
        panel_layout = QtWidgets.QHBoxLayout(panel)
        panel_layout.setContentsMargins(20, 10, 20, 10)
        panel_layout.setSpacing(0)

        lbl = QtWidgets.QLabel("CONTROLS")
        lbl.setStyleSheet(
            "color:#2a2a44; font-family:Consolas; font-size:9px; letter-spacing:3px;")
        lbl.setAlignment(QtCore.Qt.AlignLeft | QtCore.Qt.AlignVCenter)
        panel_layout.addWidget(lbl)
        panel_layout.addStretch()

        # SCALE knob:  1× = ±20 V,  2× = ±10 V, … 10× = ±2 V
        self.knob_voltage = KnobWidget(
            "SCALE", 1, 10, 1, "×", accent="#a78bfa")

        # TRIGGER knob: ADC counts (0–4095) sent to FPGA
        # Trigger line on plot is converted to volts automatically
        self.knob_trigger = KnobWidget(
            "TRIGGER", 0, 4095, 2048, "", accent="#ff5555")

        # DECIMATOR knob 0–9 → DEC byte
        self.knob_dec = KnobWidget(
            "DECIMATOR", 0, 9, 0, "", accent="#00e5ff")

        for knob in (self.knob_voltage, self.knob_trigger, self.knob_dec):
            panel_layout.addWidget(knob)
            panel_layout.addSpacing(10)

        panel_layout.addStretch()

        self.uart_status = QtWidgets.QLabel("UART  ·  not connected")
        self.uart_status.setStyleSheet(
            "color:#2a2a44; font-family:Consolas; font-size:9px;")
        self.uart_status.setAlignment(
            QtCore.Qt.AlignRight | QtCore.Qt.AlignVCenter)
        panel_layout.addWidget(self.uart_status)

        root.addWidget(panel)

        # ── Connect signals ──────────────────────────────────────────────────
        self.knob_voltage.valueChanged.connect(self._on_controls_changed)
        self.knob_trigger.valueChanged.connect(self._on_controls_changed)
        self.knob_dec.valueChanged.connect(self._on_controls_changed)

        # ── Data buffer (volts) ───────────────────────────────────────────────
        self.data = np.zeros(SAMPLES_PER_PACKET, dtype=np.float32)
        self._apply_visuals()

        # ── Serial thread or fake-data timer ─────────────────────────────────
        self._serial_thread = None
        if USE_FAKE:
            self._set_status("FAKE DATA  ·  demo mode", "#a78bfa")
            self._fake_timer = QtCore.QTimer(self)
            self._fake_timer.timeout.connect(self._on_fake_tick)
            self._fake_timer.start(30)
        else:
            self._serial_thread = SerialReaderThread(COM_PORT, BAUD_RATE, self)
            self._serial_thread.data_ready.connect(self._on_serial_data)
            self._serial_thread.status.connect(self._set_status)
            self._serial_thread.start()
            QtCore.QTimer.singleShot(100, lambda: self._send_config(log=False))

        # ── Plot refresh timer ────────────────────────────────────────────────
        self._plot_timer = QtCore.QTimer(self)
        self._plot_timer.timeout.connect(self._refresh_plot)
        self._plot_timer.start(30)

        self.resize(1100, 680)

    # --------------------------
    # Helpers
    # --------------------------
    def _set_status(self, text: str, colour: str = "#2a2a44"):
        self.uart_status.setText(text)
        self.uart_status.setStyleSheet(
            f"color:{colour}; font-family:Consolas; font-size:9px;")

    def _effective_sample_rate(self) -> float:
        return BASE_SAMPLE_RATE / (2 ** self.knob_dec.value)

    def _apply_visuals(self):
        """
        SCALE knob (1–10):
          1×  →  ±10 V  (full range, 20 Vpp)
          2×  →  ±50 V  (10 Vpp)
          10× →  ±1 V   (2 Vpp)
        Always centred at 0 V.
        Trigger line drawn at the voltage that corresponds to the ADC count.
        """
        scale   = max(1, self.knob_voltage.value)
        v_range = ADC_MAX_VOLTAGE / scale              # half-range in volts
        self.plot_widget.setYRange(-v_range, v_range)

        # Convert ADC count to voltage for the trigger line position
        trig_v = float(counts_to_volts(self.knob_trigger.value))
        self.trigger_line.setValue(trig_v)

    def _send_config(self, log: bool = True):
        trig = self.knob_trigger.value
        dec  = self.knob_dec.value
        pkt  = build_config_packet(trig, dec)
        if self._serial_thread:
            self._serial_thread.send(pkt)
        if log:
            trig_v = float(counts_to_volts(trig))
            self._set_status(
                f"TX  ·  TRIG={trig} ({trig_v:+.2f}V)  DEC={dec}"
                f"  [{pkt.hex(' ').upper()}]",
                "#00e5ff")

    # --------------------------
    # Slots
    # --------------------------
    def _on_controls_changed(self, _=None):
        self._apply_visuals()
        self._send_config()

    def _on_serial_data(self, data: np.ndarray):
        """data is already in volts (converted + inverted in _read_packet)."""
        self.data = data
        self.stats_bar.update_stats(self.data, self._effective_sample_rate())

    def _on_fake_tick(self):
        """Fake ±15 V sine wave with a bit of noise — centred at 0 V."""
        t      = np.linspace(0, 2 * np.pi * 3, SAMPLES_PER_PACKET, dtype=np.float32)
        noise  = np.random.normal(0, 0.1, SAMPLES_PER_PACKET).astype(np.float32)
        signal = 7.5 * np.sin(t) + noise          # 15 Vpp, centred at 0 V
        self.data = np.clip(signal, -ADC_MAX_VOLTAGE, ADC_MAX_VOLTAGE)
        self.stats_bar.update_stats(self.data, self._effective_sample_rate())

    def _refresh_plot(self):
        self.curve.setData(self.data)

    # --------------------------
    # Clean shutdown
    # --------------------------
    def closeEvent(self, event):
        if self._serial_thread:
            self._serial_thread.stop()
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