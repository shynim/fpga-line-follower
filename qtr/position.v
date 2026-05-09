module position (
    input wire clk,
    input wire rst,
    input wire norm_ready,                 // Pulses when Module 3 finishes
    input wire [127:0] normalized_values,  // From Module 3

    output reg [15:0] position,            // The final steering value! (0 to 7000)
    output reg pos_ready                   // Pulses when position is calculated
);
    // State Machine
    localparam IDLE       = 3'd0;
    localparam ACCUMULATE = 3'd1;
    localparam START_DIV  = 3'd2;
    localparam WAIT_DIV   = 3'd3;
    localparam DONE       = 3'd4;

    reg [2:0] state = IDLE;
    reg [3:0] idx; // Loops 0 to 7

    // OPTIMIZATION: Reduced from 32-bit down to 26-bit
    reg [25:0] weighted_sum;
    reg [25:0] total_sum;
    reg [15:0] last_pos; // "Memory" for when the robot loses the line

    // Setup our trusted hardware divider!
    reg div_start;
    reg [25:0] div_num;
    reg [25:0] div_den;
    wire [25:0] div_quot;
    wire [25:0] div_rem;
    wire div_ready;

    // OPTIMIZATION: Call the divider and force it to synthesize at 26 bits
    seq_divider #(.WIDTH(26)) pos_div (
        .clk(clk),
        .rst(rst),
        .start(div_start),
        .num(div_num),
        .den(div_den),
        .quotient(div_quot),
        .remainder(div_rem),
        .ready(div_ready)
    );

    // --- THE DSP MULTIPLIER TRICK ---
    wire [15:0] current_val_16 = normalized_values[idx*16 +: 16];
    wire [15:0] weight_16      = idx * 16'd1000;
    // --------------------------------

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            position <= 16'd3500; // Default to perfect center
            last_pos <= 16'd3500;
            pos_ready <= 0;
            div_start <= 0;
        end else begin
            case (state)
                IDLE: begin
                    pos_ready <= 0;
                    div_start <= 0;
                    if (norm_ready) begin
                        state <= ACCUMULATE;
                        idx <= 0;
                        weighted_sum <= 0;
                        total_sum <= 0;
                    end
                end

                ACCUMULATE: begin
                    // Noise Filter: We only care about sensors that actually see a line.
                    if (current_val_16 > 50) begin
                        weighted_sum <= weighted_sum + (current_val_16 * weight_16);
                        total_sum <= total_sum + current_val_16;
                    end

                    if (idx == 7) begin
                        state <= START_DIV;
                    end else begin
                        idx <= idx + 1;
                    end
                end

                START_DIV: begin
                    if (total_sum == 0) begin
                        // CRITICAL ROBOTIC LOGIC: We lost the line!
                        if (last_pos < 3500) begin
                            position <= 16'd0;    // Steer hard left!
                        end else begin
                            position <= 16'd7000; // Steer hard right!
                        end
                        state <= DONE; 
                    end else begin
                        // We see the line. Fire up the hardware divider!
                        div_num <= weighted_sum;
                        div_den <= total_sum;
                        div_start <= 1;
                        state <= WAIT_DIV;
                    end
                end

                WAIT_DIV: begin
                    div_start <= 0; // Turn off the pulse
                    if (div_ready) begin
                        position <= div_quot[15:0];
                        last_pos <= div_quot[15:0]; // Save this position to memory!
                        state <= DONE;
                    end
                end

                DONE: begin
                    pos_ready <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule