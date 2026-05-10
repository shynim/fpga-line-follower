import serial

COM_PORT = 'COM11' # Change to your port if necessary
BAUD_RATE = 115200 

def read_and_convert():
    try:
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=1)
        print(f"Connected to {COM_PORT} at {BAUD_RATE} baud. Waiting for data...\n")
        
        while True:
            if ser.in_waiting > 0:
                raw_data = ser.readline()
                
                try:
                    # Decode and strip newline characters
                    ascii_string = raw_data.decode('ascii').strip()
                    
                    if ascii_string:
                        # Split the string by spaces into a list: ['0DAC', '64', '64']
                        hex_values = ascii_string.split(' ')
                        
                        # Make sure we actually received all 3 values before doing ANY math
                        if len(hex_values) == 3:
                            
                            # FIXED: Use hex_values[0] instead of hex_values
                            pos_dec = int(hex_values[0], 16)
                            spd_a_dec = int(hex_values[1], 16)
                            spd_b_dec = int(hex_values[2], 16)
                            
                            print(f"Pos: {pos_dec:4d} | Motor Left: {spd_a_dec:3d} | Motor Right: {spd_b_dec:3d}")
                            
                        else:
                            # Safely ignore partial data (like the "20" you saw)
                            print(f"Waiting for full data stream... (Ignored partial line: {ascii_string})")
                            
                except ValueError:
                    pass # Ignore line noise
                except UnicodeDecodeError:
                    pass # Ignore line noise

    except serial.SerialException as e:
        print(f"Error opening port. Is PuTTY closed? {e}")
    except KeyboardInterrupt:
        pass
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()

if __name__ == '__main__':
    read_and_convert()