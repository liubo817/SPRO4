import sys
import numpy as np
from PyQt5 import QtWidgets, QtCore, QtGui
import pyqtgraph as pg
import serial
import math

# --------------------------
# Configuration
# --------------------------
USE_FAKE  = False    # Set False to read from COM port
COM_PORT  = "COM8"
BAUD_RATE = 115200

# --------------------------
# Combined config packet
# --------------------------
# Format (8 bytes):
#   AA 55  TB_HI TB_LO  VOLT  TRIG  CHK  FF
#
#   AA 55           : header
#   TB_HI TB_LO     : timebase 16-bit big-endian (10–500 ms)
#   VOLT            : voltage scale 8-bit (1–100 V)
#   TRIG            : trigger level 8-bit (0–255)
#   CHK             : (TB_HI + TB_LO + VOLT + TRIG) % 256
#   FF              : end marker
#
def build_config_packet(timebase: int, voltage: int, trigger: int) -> bytes:
    tb   = max(10,  min(500, int(timebase)))
    volt = max(1,   min(100, int(voltage)))
    trig = max(0,   min(255, int(trigger)))
    tb_hi = (tb >> 8) & 0xFF
    tb_lo =  tb       & 0xFF
    chk   = (tb_hi + tb_lo + volt + trig) % 256
    return bytes([0xAA, 0x55, tb_hi, tb_lo, volt, trig, chk, 0xFF])


# --------------------------
# Virtual Knob Widget
# --------------------------
class KnobWidget(QtWidgets.QWidget):
    """
    Rotary knob controlled by click-drag (vertical) or scroll wheel.
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
        self.setToolTip(f"Drag ↑↓ or scroll  •  range {min_val}–{max_val}{unit}")

    # ---- value property ----
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

    # ---- mouse / wheel ----
    def mousePressEvent(self, e):
        if e.button() == QtCore.Qt.LeftButton:
            self._dragging = True
            self._last_y   = e.y()

    def mouseMoveEvent(self, e):
        if self._dragging:
            dy   = self._last_y - e.y()          # up → positive
            step = max(1, (self.max_val - self.min_val) // 120)
            self.value   = self._value + dy * step
            self._last_y = e.y()

    def mouseReleaseEvent(self, _):
        self._dragging = False

    def wheelEvent(self, e):
        step = max(1, (self.max_val - self.min_val) // 120)
        self.value = self._value + (step if e.angleDelta().y() > 0 else -step)

    # ---- painting ----
    def paintEvent(self, _):
        p = QtGui.QPainter(self)
        p.setRenderHint(QtGui.QPainter.Antialiasing)

        W, H   = self.width(), self.height()
        cx, cy = W // 2, 56
        R_arc  = 42        # arc radius
        R_knob = 30        # knob face radius

        START  =  225.0    # degrees: arc starts bottom-left
        SWEEP  = -270.0    # clockwise total sweep

        norm         = (self._value - self.min_val) / max(1, self.max_val - self.min_val)
        filled_sweep = SWEEP * norm

        # --- background circle (subtle glow) ---
        glow = QtGui.QRadialGradient(cx, cy, R_arc + 8)
        glow.setColorAt(0.0, QtGui.QColor(self.accent.red(),
                                          self.accent.green(),
                                          self.accent.blue(), 18))
        glow.setColorAt(1.0, QtGui.QColor(0, 0, 0, 0))
        p.setBrush(glow)
        p.setPen(QtCore.Qt.NoPen)
        p.drawEllipse(QtCore.QPointF(cx, cy), R_arc + 8, R_arc + 8)

        # --- arc track ---
        arc_rect = QtCore.QRectF(cx - R_arc, cy - R_arc, 2*R_arc, 2*R_arc)
        p.setPen(QtGui.QPen(QtGui.QColor("#22223a"), 5,
                            QtCore.Qt.SolidLine, QtCore.Qt.RoundCap))
        p.drawArc(arc_rect, int(START * 16), int(SWEEP * 16))

        # --- filled arc ---
        filled_pen = QtGui.QPen(self.accent, 5,
                                QtCore.Qt.SolidLine, QtCore.Qt.RoundCap)
        p.setPen(filled_pen)
        p.drawArc(arc_rect, int(START * 16), int(filled_sweep * 16))

        # --- knob face ---
        grad = QtGui.QRadialGradient(cx - 7, cy - 7, R_knob * 1.6)
        grad.setColorAt(0.0, QtGui.QColor("#38384e"))
        grad.setColorAt(1.0, QtGui.QColor("#14141c"))
        p.setBrush(grad)
        p.setPen(QtGui.QPen(QtGui.QColor("#33334a"), 1))
        p.drawEllipse(QtCore.QPointF(cx, cy), R_knob, R_knob)

        # --- indicator dot on knob rim ---
        angle_rad = math.radians(-(START + filled_sweep))
        dot_x = cx + (R_knob - 6) * math.cos(angle_rad)
        dot_y = cy + (R_knob - 6) * math.sin(angle_rad)
        p.setBrush(self.accent)
        p.setPen(QtCore.Qt.NoPen)
        p.drawEllipse(QtCore.QPointF(dot_x, dot_y), 4, 4)

        # --- label ---
        p.setPen(QtGui.QColor("#888899"))
        f_label = QtGui.QFont("Consolas", 8)
        f_label.setLetterSpacing(QtGui.QFont.AbsoluteSpacing, 1.5)
        p.setFont(f_label)
        p.drawText(0, H - 44, W, 18, QtCore.Qt.AlignCenter, self.label)

        # --- value readout ---
        p.setPen(self.accent)
        p.setFont(QtGui.QFont("Consolas", 10, QtGui.QFont.Bold))
        p.drawText(0, H - 26, W, 22, QtCore.Qt.AlignCenter,
                   f"{self._value}{self.unit}")

        p.end()


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
            "font-size:11pt;letter-spacing:2px'>OSCILLOSCOPE</span>")
        for axis in ('left', 'bottom'):
            self.plot_widget.getAxis(axis).setPen(pg.mkPen("#2a2a3e"))
            self.plot_widget.getAxis(axis).setTextPen(pg.mkPen("#555566"))
        self.plot_widget.showGrid(x=True, y=True, alpha=0.12)
        self.plot_widget.setYRange(0, 255)

        self.curve = self.plot_widget.plot(pen=pg.mkPen("#00e5ff", width=1.5))
        root.addWidget(self.plot_widget, stretch=1)

        # trigger line
        self.trigger_line = pg.InfiniteLine(
            angle=0, movable=False,
            pen=pg.mkPen(color="#ff5555", width=1,
                         style=QtCore.Qt.DashLine))
        self.plot_widget.addItem(self.trigger_line)

        # ── Knob panel ───────────────────────────────────────────────────────
        panel = QtWidgets.QWidget()
        panel.setStyleSheet(
            "background:#10101a; border-radius:10px;")
        panel_layout = QtWidgets.QHBoxLayout(panel)
        panel_layout.setContentsMargins(20, 10, 20, 10)
        panel_layout.setSpacing(0)

        # left label
        lbl = QtWidgets.QLabel("CONTROLS")
        lbl.setStyleSheet(
            "color:#2a2a44; font-family:Consolas; font-size:9px;"
            "letter-spacing:3px;")
        lbl.setAlignment(QtCore.Qt.AlignLeft | QtCore.Qt.AlignVCenter)
        panel_layout.addWidget(lbl)
        panel_layout.addStretch()

        # three knobs with distinct accent colours
        self.knob_timebase = KnobWidget(
            "TIMEBASE", 10, 500, 100, " ms", accent="#00e5ff")
        self.knob_voltage  = KnobWidget(
            "VOLTAGE",   1, 100,  25, " V",  accent="#a78bfa")
        self.knob_trigger  = KnobWidget(
            "TRIGGER",   0, 255, 127, "",    accent="#ff5555")

        for knob in (self.knob_timebase, self.knob_voltage, self.knob_trigger):
            panel_layout.addWidget(knob)
            # spacer between knobs
            panel_layout.addSpacing(10)

        panel_layout.addStretch()

        # UART status label
        self.uart_status = QtWidgets.QLabel("UART  ·  not connected")
        self.uart_status.setStyleSheet(
            "color:#2a2a44; font-family:Consolas; font-size:9px;")
        self.uart_status.setAlignment(QtCore.Qt.AlignRight | QtCore.Qt.AlignVCenter)
        panel_layout.addWidget(self.uart_status)

        root.addWidget(panel)

        # connect knob signals — any change fires the combined packet sender
        self.knob_timebase.valueChanged.connect(self._on_any_knob_changed)
        self.knob_voltage .valueChanged.connect(self._on_any_knob_changed)
        self.knob_trigger .valueChanged.connect(self._on_any_knob_changed)

        # ── Data buffer ──────────────────────────────────────────────────────
        self.buffer_size = 256
        self.data = np.zeros(self.buffer_size)

        # apply initial knob states to the plot
        self._apply_knob_visuals()

        # ── Serial ───────────────────────────────────────────────────────────
        self.ser = None
        if not USE_FAKE:
            try:
                self.ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=0.1)
                self._set_status(f"UART  ·  {COM_PORT}  ✓", "#00e5ff")
                packet = build_config_packet(10, 0, 100)
                self._send_uart(packet)
            except serial.SerialException as exc:
                self._set_status(f"UART ERR  ·  {exc}", "#ff5555")

        # ── Timer ────────────────────────────────────────────────────────────
        self.timer = QtCore.QTimer()
        self.timer.timeout.connect(self.update_plot)
        self.timer.start(30)

        self.resize(960, 620)

    # --------------------------
    # Helpers
    # --------------------------
    def _set_status(self, text: str, color: str = "#2a2a44"):
        self.uart_status.setText(text)
        self.uart_status.setStyleSheet(
            f"color:{color}; font-family:Consolas; font-size:9px;")

    def _apply_knob_visuals(self):
        """Sync plot appearance to current knob values."""
        v_range = self.knob_voltage.value * 10      # e.g. 25 V → 0–250
        self.plot_widget.setYRange(0, v_range)
        self.trigger_line.setValue(self.knob_trigger.value)

    # --------------------------
    # Any knob changed → send combined packet
    # --------------------------
    def _on_any_knob_changed(self, _=None):
        tb   = self.knob_timebase.value
        volt = self.knob_voltage.value
        trig = self.knob_trigger.value

        self._apply_knob_visuals()

        packet = build_config_packet(tb, volt, trig)
        self._send_uart(packet)
        self._set_status(
            f"TX  ·  TB={tb}ms  V={volt}V  TR={trig}"
            f"  [{packet.hex(' ').upper()}]",
            "#00e5ff")

    def _send_uart(self, packet: bytes):
        if self.ser and self.ser.is_open:
            try:
                self.ser.write(packet)
            except serial.SerialException as exc:
                self._set_status(f"TX ERR  ·  {exc}", "#ff5555")

    # --------------------------
    # Fake data generator
    # --------------------------
    def get_fake_data(self):
        v_scale = self.knob_voltage.value / 25.0
        t = np.linspace(0, 2 * np.pi * 2, self.buffer_size)
        noise  = np.random.normal(0, 3, self.buffer_size)
        signal = 127 + (50 * v_scale) * np.sin(t + np.random.rand() * 0.05) + noise
        return np.clip(signal, 0, 255)

    # --------------------------
    # Real UART data reader
    # --------------------------
    def get_uart_data(self):
        """Read one data packet from UART (header 0xAA 0x55 + length + payload + checksum)."""
        while True:
            byte = self.ser.read()
            if byte == b'\xAA':
                if self.ser.read() == b'\x55':
                    length_byte = self.ser.read()
                    if not length_byte:
                        continue
                    length     = int.from_bytes(length_byte, 'big')
                    data_bytes = self.ser.read(length)
                    checksum   = self.ser.read(1)
                    if not data_bytes or not checksum:
                        continue
                    if checksum == bytes([sum(data_bytes) % 256]):
                        return list(data_bytes)

    def get_data(self):
        return self.get_fake_data() if USE_FAKE else self.get_uart_data()

    # --------------------------
    # Plot update (timer tick)
    # --------------------------
    def update_plot(self):
        new_data = self.get_data()
        self.data = np.roll(self.data, -len(new_data))
        self.data[-len(new_data):] = new_data
        self.curve.setData(self.data)


# --------------------------
# Entry point
# --------------------------
if __name__ == "__main__":
    app = QtWidgets.QApplication(sys.argv)
    app.setStyle("Fusion")
    window = OscilloscopeApp()
    window.show()
    sys.exit(app.exec_())