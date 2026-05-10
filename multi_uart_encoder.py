import serial
import threading

COM_PORT = 'COM11' # Change to your port if necessary
BAUD_RATE = 115200 

# ==========================================
# WORKER 1: Reads data FROM the FPGA
# ==========================================
def read_from_port(ser):
    """This function runs in the background and continuously reads data."""
    while True:
        try:
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
                            # Safely ignore partial data
                            print(f"Waiting for full data stream... (Ignored partial line: {ascii_string})")
                            
                except ValueError:
                    pass # Ignore line noise
                except UnicodeDecodeError:
                    pass # Ignore line noise
                    
        except serial.SerialException:
            # If the main program closes the port, this thread stops safely
            break

# ==========================================
# WORKER 2: Sends data TO the FPGA (Main Loop)
# ==========================================
def main():
    try:
        # Open the Serial Port once for both reading and writing
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=1)
        print(f"Connected to {COM_PORT} at {BAUD_RATE} baud.")
        print("Type a tuning command (e.g., 'p50', 'b150', 'm180') and press Enter.")
        print("Press Ctrl+C to exit.\n")
        
        # Start the background reading thread! (daemon=True means it closes when you exit the script)
        reader_thread = threading.Thread(target=read_from_port, args=(ser,), daemon=True)
        reader_thread.start()
        
        # The main loop now just waits for you to type!
        while True:
            # Wait for keyboard input
            user_cmd = input() 
            
            if user_cmd:
                # Add a newline character (\n) so your FPGA parser knows the command is done
                cmd_with_newline = user_cmd + '\n'
                
                # Encode the string to ASCII bytes and send it over UART
                ser.write(cmd_with_newline.encode('ascii'))
                
                # Print a confirmation so you know it sent!
                print(f"\n>>> SENT TO FPGA: {user_cmd} <<<\n")

    except serial.SerialException as e:
        print(f"Error opening port. Is PuTTY closed? {e}")
    except KeyboardInterrupt:
        print("\nExiting program...")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
            print("Port closed.")

if __name__ == '__main__':
    main()