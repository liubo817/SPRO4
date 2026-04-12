import sys
import numpy as np
from PyQt5 import QtWidgets, QtCore
import pyqtgraph as pg
import serial

# --------------------------
# Configuration
# --------------------------
USE_FAKE = True  # Set False to read from COM port
COM_PORT = "COM5"  # Receiver port (from com0com)
BAUD_RATE = 115200

# --------------------------
# Oscilloscope App
# --------------------------
class OscilloscopeApp(QtWidgets.QMainWindow):
    def __init__(self):
        super().__init__()

        self.setWindowTitle("Python Oscilloscope")

        # Plot widget
        self.plot_widget = pg.PlotWidget()
        self.setCentralWidget(self.plot_widget)
        self.plot_widget.setYRange(0, 255)
        self.plot_widget.setTitle("Live Signal")
        self.curve = self.plot_widget.plot(pen='y')

        # Data buffer
        self.buffer_size = 256
        self.data = np.zeros(self.buffer_size)

        # Serial setup (optional)
        if not USE_FAKE:
            self.ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=0.1)

        # Timer
        self.timer = QtCore.QTimer()
        self.timer.timeout.connect(self.update_plot)
        self.timer.start(30)  # ~33 FPS

    # --------------------------
    # Fake data generator
    # --------------------------
    def get_fake_data(self):
        t = np.linspace(0, 2*np.pi, self.buffer_size)
        noise = np.random.normal(0, 5, self.buffer_size)
        signal = 127 + 50 * np.sin(t + np.random.rand()) + noise
        return signal

    # --------------------------
    # UART / real data
    # --------------------------
    def get_uart_data(self):
        """Read one packet from UART with header + length + checksum"""
        while True:
            byte = self.ser.read()
            if byte == b'\xAA':
                if self.ser.read() == b'\x55':  # header matched
                    length_byte = self.ser.read()
                    if not length_byte:
                        continue
                    length = int.from_bytes(length_byte, 'big')
                    data_bytes = self.ser.read(length)
                    checksum = self.ser.read(1)
                    if not data_bytes or not checksum:
                        continue
                    # verify checksum
                    if checksum == bytes([sum(data_bytes) % 256]):
                        return list(data_bytes)

    # --------------------------
    # Unified data getter
    # --------------------------
    def get_data(self):
        if USE_FAKE:
            return self.get_fake_data()
        else:
            return self.get_uart_data()

    # --------------------------
    # Update plot
    # --------------------------
    def update_plot(self):
        new_data = self.get_data()
        # Scroll effect
        self.data = np.roll(self.data, -len(new_data))
        self.data[-len(new_data):] = new_data
        self.curve.setData(self.data)


# --------------------------
# Main
# --------------------------
if __name__ == "__main__":
    app = QtWidgets.QApplication(sys.argv)
    window = OscilloscopeApp()
    window.show()
    sys.exit(app.exec_())