`default_nettype none

module pid_parser (
    input wire clk,
    input wire rst,             
    input wire byte_ready,          
    input wire [7:0] data_in,       
    
    output reg [15:0] reg_p, 
    output reg [15:0] reg_i, 
    output reg [15:0] reg_d,
    
    // NEW: 8-bit speed outputs
    output reg [7:0] reg_b, 
    output reg [7:0] reg_m
);

    reg [7:0] current_cmd; 
    reg [15:0] temp_val;
    reg prev_byte_ready;

    always @(posedge clk) begin
        if (rst) begin
            reg_p <= 16'd20; 
            reg_i <= 16'd0;
            reg_d <= 16'd0;
            
            reg_b <= 8'd80; // Base speed starts at 100
            reg_m <= 8'd150; // Max speed defaults to full 255
            
            current_cmd <= 0;
            temp_val <= 0;
            prev_byte_ready <= 0;
        end else begin
            prev_byte_ready <= byte_ready;

            if (byte_ready == 1'b1 && prev_byte_ready == 1'b0) begin
                
                // Add 'b' (0x62) and 'm' (0x6D) to the command letter check
                if (data_in == 8'h70 || data_in == 8'h69 || data_in == 8'h64 || data_in == 8'h62 || data_in == 8'h6D) begin
                    current_cmd <= data_in;
                    temp_val <= 0; 
                end
                
                else if (data_in >= 8'h30 && data_in <= 8'h39) begin
                    temp_val <= (temp_val * 10) + (data_in - 8'h30);
                end
                
                else if (data_in == 8'h0A || data_in == 8'h0D) begin
                    if (current_cmd == 8'h70) reg_p <= temp_val;
                    if (current_cmd == 8'h69) reg_i <= temp_val;
                    if (current_cmd == 8'h64) reg_d <= temp_val;
                    
                    // NEW: Assign the speed variables (truncate the 16-bit temp back to 8-bit)
                    if (current_cmd == 8'h62) reg_b <= temp_val[7:0];
                    if (current_cmd == 8'h6D) reg_m <= temp_val[7:0];
                end
            end
        end
    end
endmodule