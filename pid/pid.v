module pid (
    input wire clk,
    input wire rst,
    input wire pos_ready,             // From the position module
    input wire [15:0] position,       // 0 to 7000 (Unsigned)

    // PID Tuning Parameters (Now 16-bit for Fixed-Point Math!)
    input wire [15:0] kp,              
    input wire [15:0] kd,              

    output reg signed [15:0] steering_correction, // The final output! (Signed)
    output reg steer_ready
);

    // State Machine
    localparam IDLE = 2'd0;
    localparam CALC = 2'd1;
    localparam DONE = 2'd2;

    reg [1:0] state = IDLE;

    // --- SIGNED MATH REGISTERS ---
    reg signed [15:0] current_error;
    reg signed [15:0] last_error;
    reg signed [15:0] error_diff;

    // UPGRADED to 32-bit so the multiplication doesn't overflow before we divide!
    reg signed [31:0] p_term;
    reg signed [31:0] d_term;

    // A wire to safely cast the unsigned position (0-7000) into a signed number
    wire signed [16:0] signed_pos = {1'b0, position}; 
    wire signed [16:0] setpoint   = 17'sd3500; // Perfect center

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            current_error <= 0;
            last_error <= 0;
            steering_correction <= 0;
            steer_ready <= 0;
            p_term <= 0;
            d_term <= 0;
        end else begin
            case (state)
                IDLE: begin
                    steer_ready <= 0;
                    if (pos_ready) begin
                        // 1. Calculate the Error (Distance from 3500)
                        current_error <= signed_pos - setpoint;
                        state <= CALC;
                    end
                end

                CALC: begin
                    // 2. Calculate P-Term (Error * Kp)
                    // Multiply first (creating a huge number), then shift right by 4 (divide by 16)
                    p_term <= (current_error * $signed({1'b0, kp})) >>> 4;

                    // 3. Calculate D-Term ((Error - Last Error) * Kd)
                    error_diff = current_error - last_error;
                    d_term <= (error_diff * $signed({1'b0, kd})) >>> 4;

                    state <= DONE;
                end

                DONE: begin
                    // 4. Add them together and cast back to 16-bit for the final steering correction!
                    steering_correction <= p_term[15:0] + d_term[15:0];
                    
                    // 5. Save the current error to become the "last error" for the next loop
                    last_error <= current_error;
                    
                    steer_ready <= 1; // Tell the motor driver we are ready!
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule


