module apply_pid #(
    // You can tune these parameters from your top module later!
    parameter BASE_SPEED = 8'd100, // The cruising speed of the robot (0-255)
    parameter SHIFT = 3'd6         // Divides the massive PID number by 2^6 (64)
)(
    input wire clk,
    input wire rst,
    input wire steer_ready,
    input wire signed [15:0] steering_correction,

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
            
            // 1. SCALE: Divide the massive PID number (e.g. 10750 / 64 = ~167)
            // We use an Arithmetic Right Shift (>>>) to safely divide negative numbers
            scaled_steer = steering_correction >>> SHIFT;

            // 2. MIX: Differential Steering Equation
            left_raw  = $signed({1'b0, BASE_SPEED}) + scaled_steer;
            right_raw = $signed({1'b0, BASE_SPEED}) - scaled_steer;

            // 3. CLAMP: Left Motor (Motor A)
            if (left_raw > 255) begin
                speed_a <= 8'd255;      // CLAMP MAX FORWARD
                dir_a <= 2'b01;         // Forward
            end else if (left_raw > 0) begin
                speed_a <= left_raw[7:0]; // Normal Forward
                dir_a <= 2'b01;         // Forward
            
            // --- THE NEW NO-REVERSE LOGIC ---
            end else begin
                speed_a <= 0;           // CLAMP TO ZERO
                dir_a <= 2'b00;         // Stop (or Free-wheel)
            end
            
            // 4. CLAMP: Right Motor (Motor B)
            if (right_raw > 255) begin
                speed_b <= 8'd255;      // CLAMP MAX FORWARD
                dir_b <= 2'b01;         // Forward
            end else if (right_raw > 0) begin
                speed_b <= right_raw[7:0]; // Normal Forward
                dir_b <= 2'b01;         // Forward
                
            // --- THE NEW NO-REVERSE LOGIC ---
            end else begin
                speed_b <= 0;           // CLAMP TO ZERO
                dir_b <= 2'b00;         // Stop (or Free-wheel)
            end
            
        end
    end
endmodule