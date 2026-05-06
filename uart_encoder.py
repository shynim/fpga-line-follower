import serial
import time

# --- CONFIGURATION ---
# Change this to match the COM port you see in your device manager (e.g., 'COM4')
# If you are on Mac/Linux, it will look like '/dev/ttyUSB0'
PORT = 'COM11' 
BAUD_RATE = 115200 # Make sure this matches your FPGA's UART speed

try:
    # Open the serial port
    ser = serial.Serial(PORT, BAUD_RATE, timeout=1)
    print(f"Listening to FPGA on {PORT} at {BAUD_RATE} baud...")
    print("-" * 40)

    while True:
        # 1. Read the line of data coming from the FPGA
        raw_data = ser.readline()
        
        # 2. Decode it from raw bytes into a normal text string
        hex_string = raw_data.decode('utf-8', errors='ignore').strip()
        
        # 3. If we received something, convert it!
        if hex_string:
            try:
                # This is the magic line: it tells Python to convert Base-16 (Hex) to Base-10 (Decimal)
                decimal_value = int(hex_string, 16)
                
                print(f"FPGA sent: 0x{hex_string}  -->  Decimal: {decimal_value}")
                
            except ValueError:
                # If the FPGA sends garbage while booting up, we just ignore it
                print(f"Garbage data received: {hex_string}")

except serial.SerialException:
    print(f"ERROR: Could not open {PORT}.")
    print("Make sure no other terminal programs (like PuTTY) are using it!")
except KeyboardInterrupt:
    print("\nClosing connection.")
    if 'ser' in locals() and ser.is_open:
        ser.close()