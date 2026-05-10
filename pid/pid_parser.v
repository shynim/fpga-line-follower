`default_nettype none

module pid_parser (
    input wire clk,
    input wire rst,                 // Added reset pin
    input wire byte_ready,          // From your uart_rx
    input wire [7:0] data_in,       // From your uart_rx
    
    // Upgraded to 16-bit to match pid.v
    output reg [15:0] reg_p, 
    output reg [15:0] reg_i, 
    output reg [15:0] reg_d  
);

    reg [7:0] current_cmd; 
    reg [15:0] temp_val;
    reg prev_byte_ready;

    always @(posedge clk) begin
        if (rst) begin
            // Safe default tuning values on boot
            reg_p <= 16'd20; 
            reg_i <= 16'd0;
            reg_d <= 16'd0;
            current_cmd <= 0;
            temp_val <= 0;
            prev_byte_ready <= 0;
        end else begin
            // 1. Always update our memory with the current state
            prev_byte_ready <= byte_ready;

            // 2. ONLY trigger if byte_ready is HIGH *and* it was LOW on the last clock cycle
            if (byte_ready == 1'b1 && prev_byte_ready == 1'b0) begin
                
                // Is it a command letter? (p, i, or d)
                if (data_in == 8'h70 || data_in == 8'h69 || data_in == 8'h64) begin
                    current_cmd <= data_in;
                    temp_val <= 0; 
                end
                
                // Is it a number character? ('0' to '9')
                else if (data_in >= 8'h30 && data_in <= 8'h39) begin
                    temp_val <= (temp_val * 10) + (data_in - 8'h30);
                end
                
                // Is it the Enter key? (\n or \r)
                else if (data_in == 8'h0A || data_in == 8'h0D) begin
                    if (current_cmd == 8'h70) reg_p <= temp_val;
                    if (current_cmd == 8'h69) reg_i <= temp_val;
                    if (current_cmd == 8'h64) reg_d <= temp_val;
                end
            end
        end
    end

endmodule