import serial

# Configure the serial port settings
COM_PORT = 'COM11'
# IMPORTANT: Change this baudrate to match the one configured in your Verilog uart_tx module!
# Common values are 9600 or 115200.
BAUD_RATE = 115200 

def read_and_convert():
    try:
        # Open the serial port
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=1)
        print(f"Successfully connected to {COM_PORT} at {BAUD_RATE} baud.")
        print("Waiting for data... (Press Ctrl+C to stop)\n")
        
        while True:
            # Check if there is data waiting in the serial buffer
            if ser.in_waiting > 0:
                # Read a line up to the \n character
                raw_data = ser.readline()
                
                try:
                    # 1. Decode the raw bytes into a string
                    # 2. .strip() removes the \r, \n, and any spaces
                    hex_string = raw_data.decode('ascii').strip()
                    
                    if hex_string:
                        # Convert the Hexadecimal string to a Decimal integer
                        # The '16' tells Python to interpret the string as Base-16
                        decimal_value = int(hex_string, 16)
                        
                        # Print the result
                        print(f"Received Hex: {hex_string}  ->  Decimal: {decimal_value}")
                        
                except ValueError:
                    # Triggered if the FPGA sends incomplete/corrupted data that isn't valid hex
                    print(f"Skipped invalid data: {raw_data}")
                except UnicodeDecodeError:
                    # Triggered if baud rates mismatch or line noise creates garbage bytes
                    print(f"Garbage bytes received: {raw_data}")

    except serial.SerialException as e:
        print(f"Error opening serial port {COM_PORT}. Is it being used by another program like PuTTY?")
        print(f"Details: {e}")
    except KeyboardInterrupt:
        print("\nExiting program...")
    finally:
        # Ensure the port is closed when the script is stopped
        if 'ser' in locals() and ser.is_open:
            ser.close()
            print("Serial port closed.")

if __name__ == '__main__':
    read_and_convert()