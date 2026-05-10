module apply_pid #(
    // SHIFT is the only parameter left!
    parameter SHIFT = 3'd6         
)(
    input wire clk,
    input wire rst,
    input wire steer_ready,
    input wire signed [15:0] steering_correction,

    // NEW: Live dynamic speed controls from the parser!
    input wire [7:0] base_speed, 
    input wire [7:0] max_speed,

    output reg [7:0] speed_a,
    output reg [7:0] speed_b,
    output reg [1:0] dir_a,
    output reg [1:0] dir_b
);

    reg signed [15:0] scaled_steer;
    reg signed [15:0] left_raw;
    reg signed [15:0] right_raw;

    always @(posedge clk) begin
        if (rst) begin
            speed_a <= 0;
            speed_b <= 0;
            dir_a <= 2'b00;
            dir_b <= 2'b00;
        end else if (steer_ready) begin
            
            scaled_steer = steering_correction >>> SHIFT;

            // FIX: Use the dynamic 'base_speed' wire instead of the parameter
            left_raw  = $signed({1'b0, base_speed}) + scaled_steer;
            right_raw = $signed({1'b0, base_speed}) - scaled_steer;

            // --- CLAMP: Left Motor (Motor A) ---
            // FIX: Check against the dynamic 'max_speed' wire
            if (left_raw > $signed({1'b0, max_speed})) begin
                speed_a <= max_speed;   // CLAMP MAX FORWARD
                dir_a <= 2'b01;         // Forward
            end else if (left_raw > 0) begin
                speed_a <= left_raw[7:0]; // Normal Forward
                dir_a <= 2'b01;         // Forward
            end else begin
                speed_a <= 0;           // CLAMP TO ZERO
                dir_a <= 2'b00;         // Stop 
            end
            
            // --- CLAMP: Right Motor (Motor B) ---
            // FIX: Check against the dynamic 'max_speed' wire
            if (right_raw > $signed({1'b0, max_speed})) begin
                speed_b <= max_speed;   // CLAMP MAX FORWARD
                dir_b <= 2'b01;         // Forward
            end else if (right_raw > 0) begin
                speed_b <= right_raw[7:0]; // Normal Forward
                dir_b <= 2'b01;         // Forward
            end else begin
                speed_b <= 0;           // CLAMP TO ZERO
                dir_b <= 2'b00;         // Stop 
            end
            
        end
    end
endmodule