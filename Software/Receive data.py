import sys
import math
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
USE_FAKE  = False
COM_PORT  = "COM8"
BAUD_RATE = 115200

# --------------------------
# Config packet
# --------------------------
# Format (8 bytes):
#   AA 55  VOLT  TRIG_HI TRIG_LO  EDGE  CHK  FF
#
#   AA 55                : header
#   VOLT                 : voltage scale 8-bit (1–100 V)
#   TRIG_HI TRIG_LO      : trigger level 12-bit big-endian (0–4095)
#   EDGE                 : 0 = rising, 1 = falling
#   CHK                  : (VOLT + TRIG_HI + TRIG_LO + EDGE) % 256
#   FF                   : end marker
#
def build_config_packet(voltage: int, trigger: int, edge: int) -> bytes:
    volt    = max(1,    min(100,  int(voltage)))
    trig    = max(0,    min(4095, int(trigger)))
    edge_b  = 1 if edge else 0
    trig_hi = (trig >> 8) & 0xFF
    trig_lo =  trig       & 0xFF
    chk     = (volt + trig_hi + trig_lo + edge_b) % 256
    return bytes([0xAA, 0x55, volt, trig_hi, trig_lo, edge_b, chk, 0xFF])


# --------------------------
# Async serial reader thread
# --------------------------
class SerialReaderThread(QtCore.QThread):
    """
    Runs in a background thread.  Emits data_ready(list[int]) for every valid
    incoming packet, and error(str) on serial faults.
    Call send(bytes) from any thread to write a packet out.
    """
    data_ready = QtCore.pyqtSignal(list)
    status     = QtCore.pyqtSignal(str, str)   # (message, colour)

    def __init__(self, port: str, baud: int, parent=None):
        super().__init__(parent)
        self._port    = port
        self._baud    = baud
        self._running = True
        self._ser     = None
        self._write_queue: list[bytes] = []
        self._queue_lock = QtCore.QMutex()

    # ---- public API (called from main thread) ----
    def send(self, packet: bytes):
        lock = QtCore.QMutexLocker(self._queue_lock)
        self._write_queue.append(packet)

    def stop(self):
        self._running = False
        if self._ser and self._ser.is_open:
            self._ser.close()
        self.wait(2000)

    # ---- thread body ----
    def run(self):
        if not SERIAL_AVAILABLE:
            self.status.emit("pyserial not installed", "#ff5555")
            return
        try:
            self._ser = serial.Serial(self._port, self._baud, timeout=0.05)
            self.status.emit(f"UART  ·  {self._port}  ✓", "#00e5ff")
        except serial.SerialException as exc:
            self.status.emit(f"UART ERR  ·  {exc}", "#ff5555")
            return

        while self._running:
            # flush any queued writes first
            lock = QtCore.QMutexLocker(self._queue_lock)
            pending = list(self._write_queue)
            self._write_queue.clear()
            lock.unlock()

            for pkt in pending:
                try:
                    self._ser.write(pkt)
                except serial.SerialException as exc:
                    self.status.emit(f"TX ERR  ·  {exc}", "#ff5555")

            # non-blocking peek for incoming data
            try:
                if self._ser.in_waiting:
                    pkt = self._read_packet()
                    if pkt:
                        self.data_ready.emit(pkt)
            except serial.SerialException as exc:
                self.status.emit(f"RX ERR  ·  {exc}", "#ff5555")
                break

        if self._ser and self._ser.is_open:
            self._ser.close()

    def _read_packet(self) -> list[int] | None:
        """
        Packet framing:  AA 55  <length>  <data × length>  <checksum>
        Returns the payload as a list of ints, or None on framing/checksum error.
        """
        b = self._ser.read(1)
        if b != b'\xAA':
            return None
        if self._ser.read(1) != b'\x55':
            return None
        length_b = self._ser.read(1)
        if not length_b:
            return None
        length = length_b[0]
        payload = self._ser.read(length)
        chk_b   = self._ser.read(1)
        if len(payload) < length or not chk_b:
            return None
        if chk_b[0] == sum(payload) % 256:
            return list(payload)
        return None


# --------------------------
# Virtual Knob Widget
# --------------------------
class KnobWidget(QtWidgets.QWidget):
    """
    Rotary knob: click-drag (vertical) or scroll wheel.
    Emits valueChanged(int) whenever the value changes.
    """
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
# Edge Toggle Button
# --------------------------
class EdgeToggle(QtWidgets.QPushButton):
    """
    Toggles between RISE (0) and FALL (1).
    Styled to match the control panel aesthetic.
    """
    edgeChanged = QtCore.pyqtSignal(int)   # 0 = rising, 1 = falling

    _STYLES = {
        0: ("↑  RISE", "#00e5ff"),   # rising
        1: ("↓  FALL", "#a78bfa"),   # falling
    }

    def __init__(self, parent=None):
        super().__init__(parent)
        self._edge = 0
        self.setFixedSize(90, 52)
        self.setCursor(QtCore.Qt.PointingHandCursor)
        self.clicked.connect(self._toggle)
        self._refresh()

    @property
    def edge(self) -> int:
        return self._edge

    def _toggle(self):
        self._edge = 1 - self._edge
        self._refresh()
        self.edgeChanged.emit(self._edge)

    def _refresh(self):
        label, colour = self._STYLES[self._edge]
        self.setText(label)
        self.setStyleSheet(f"""
            QPushButton {{
                color: {colour};
                background: #1a1a28;
                border: 1px solid {colour};
                border-radius: 6px;
                font-family: Consolas;
                font-size: 11px;
                font-weight: bold;
                letter-spacing: 1px;
                padding: 4px 8px;
            }}
            QPushButton:hover {{
                background: #22223a;
            }}
            QPushButton:pressed {{
                background: #0d0d18;
            }}
        """)


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
        root.setSpacing(10)

        # ── Plot ─────────────────────────────────────────────────────────────
        self.plot_widget = pg.PlotWidget()
        self.plot_widget.setBackground("#0b0b12")
        self.plot_widget.setTitle(
            "<span style='color:#00e5ff;font-family:Consolas;"
            "font-size:11pt;letter-spacing:2px'>OSCILLOSCOPE DISPLAY</span>")
        for axis in ('left', 'bottom'):
            self.plot_widget.getAxis(axis).setPen(pg.mkPen("#2a2a3e"))
            self.plot_widget.getAxis(axis).setTextPen(pg.mkPen("#555566"))
        self.plot_widget.showGrid(x=True, y=True, alpha=0.12)
        self.plot_widget.setYRange(0, 4095)

        self.curve = self.plot_widget.plot(pen=pg.mkPen("#00e5ff", width=1.5))
        root.addWidget(self.plot_widget, stretch=1)

        self.trigger_line = pg.InfiniteLine(
            angle=0, movable=False,
            pen=pg.mkPen(color="#ff5555", width=1,
                         style=QtCore.Qt.DashLine))
        self.plot_widget.addItem(self.trigger_line)

        # ── Control panel ────────────────────────────────────────────────────
        panel = QtWidgets.QWidget()
        panel.setStyleSheet("background:#10101a; border-radius:10px;")
        panel_layout = QtWidgets.QHBoxLayout(panel)
        panel_layout.setContentsMargins(20, 10, 20, 10)
        panel_layout.setSpacing(0)

        lbl = QtWidgets.QLabel("CONTROLS")
        lbl.setStyleSheet(
            "color:#2a2a44; font-family:Consolas; font-size:9px;"
            "letter-spacing:3px;")
        lbl.setAlignment(QtCore.Qt.AlignLeft | QtCore.Qt.AlignVCenter)
        panel_layout.addWidget(lbl)
        panel_layout.addStretch()

        # Voltage knob  (no timebase knob)
        self.knob_voltage = KnobWidget(
            "VOLTAGE", 1, 100, 25, " V", accent="#a78bfa")

        # 12-bit trigger knob
        self.knob_trigger = KnobWidget(
            "TRIGGER", 0, 4095, 2048, "", accent="#ff5555")

        for knob in (self.knob_voltage, self.knob_trigger):
            panel_layout.addWidget(knob)
            panel_layout.addSpacing(10)

        # Edge toggle
        edge_col = QtWidgets.QVBoxLayout()
        edge_lbl = QtWidgets.QLabel("EDGE")
        edge_lbl.setStyleSheet(
            "color:#888899; font-family:Consolas; font-size:8px;"
            "letter-spacing:1.5px;")
        edge_lbl.setAlignment(QtCore.Qt.AlignCenter)
        self.edge_toggle = EdgeToggle()
        edge_col.addStretch()
        edge_col.addWidget(edge_lbl, alignment=QtCore.Qt.AlignCenter)
        edge_col.addSpacing(4)
        edge_col.addWidget(self.edge_toggle, alignment=QtCore.Qt.AlignCenter)
        edge_col.addStretch()
        panel_layout.addLayout(edge_col)
        panel_layout.addSpacing(10)

        panel_layout.addStretch()

        self.uart_status = QtWidgets.QLabel("UART  ·  not connected")
        self.uart_status.setStyleSheet(
            "color:#2a2a44; font-family:Consolas; font-size:9px;")
        self.uart_status.setAlignment(
            QtCore.Qt.AlignRight | QtCore.Qt.AlignVCenter)
        panel_layout.addWidget(self.uart_status)

        root.addWidget(panel)

        # ── Connect control signals ──────────────────────────────────────────
        self.knob_voltage.valueChanged.connect(self._on_controls_changed)
        self.knob_trigger.valueChanged.connect(self._on_controls_changed)
        self.edge_toggle.edgeChanged.connect(self._on_controls_changed)

        # ── Data buffer ──────────────────────────────────────────────────────
        self.buffer_size = 512
        self.data = np.zeros(self.buffer_size)
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
            # send initial config once the thread is running
            QtCore.QTimer.singleShot(
                100, lambda: self._send_config(log=False))

        # ── Plot refresh timer (UI only, always running) ──────────────────────
        self._plot_timer = QtCore.QTimer(self)
        self._plot_timer.timeout.connect(self._refresh_plot)
        self._plot_timer.start(30)

        self.resize(960, 620)

    # --------------------------
    # Helpers
    # --------------------------
    def _set_status(self, text: str, colour: str = "#2a2a44"):
        self.uart_status.setText(text)
        self.uart_status.setStyleSheet(
            f"color:{colour}; font-family:Consolas; font-size:9px;")

    def _apply_visuals(self):
        v_range = self.knob_voltage.value * 40   # 25 V → 0–1000 counts (12-bit)
        self.plot_widget.setYRange(0, min(v_range, 4095))
        self.trigger_line.setValue(self.knob_trigger.value)

    def _send_config(self, log: bool = True):
        volt = self.knob_voltage.value
        trig = self.knob_trigger.value
        edge = self.edge_toggle.edge
        pkt  = build_config_packet(volt, trig, edge)
        if self._serial_thread:
            self._serial_thread.send(pkt)
        if log:
            edge_str = "RISE" if edge == 0 else "FALL"
            self._set_status(
                f"TX  ·  V={volt}V  TR={trig}  EDGE={edge_str}"
                f"  [{pkt.hex(' ').upper()}]",
                "#00e5ff")

    # --------------------------
    # Slots
    # --------------------------
    def _on_controls_changed(self, _=None):
        self._apply_visuals()
        self._send_config()

    def _on_serial_data(self, payload: list[int]):
        """Called from the serial thread via Qt signal (thread-safe)."""
        arr = np.array(payload, dtype=np.float32)
        self.data = np.roll(self.data, -len(arr))
        self.data[-len(arr):] = arr

    def _on_fake_tick(self):
        v_scale = self.knob_voltage.value / 25.0
        t = np.linspace(0, 2 * np.pi * 2, 32)
        noise  = np.random.normal(0, 12, 32)
        signal = 2048 + (800 * v_scale) * np.sin(t + np.random.rand() * 0.05) + noise
        arr = np.clip(signal, 0, 4095)
        self.data = np.roll(self.data, -len(arr))
        self.data[-len(arr):] = arr

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