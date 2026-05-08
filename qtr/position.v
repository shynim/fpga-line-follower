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

    reg [31:0] weighted_sum;
    reg [31:0] total_sum;
    reg [15:0] last_pos; // "Memory" for when the robot loses the line

    // Setup our trusted hardware divider!
    reg div_start;
    reg [31:0] div_num;
    reg [31:0] div_den;
    wire [31:0] div_quot;
    wire [31:0] div_rem;
    wire div_ready;

    seq_divider pos_div (
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
    // We pull these out into combinational wires so they evaluate instantly 
    // as strict 16-bit values based on the current 'idx'. 
    // This forces Yosys to map the math below to the MULT18X18 block!
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
                    // If a sensor's value is < 50, it's just background noise. Ignore it.
                    if (current_val_16 > 50) begin
                        // Add to our weighted average totals
                        // 16-bit * 16-bit maps perfectly to the DSP multiplier!
                        weighted_sum <= weighted_sum + (current_val_16 * weight_16);
                        total_sum <= total_sum + current_val_16;
                    end

                    // Move to the next sensor, or proceed to math
                    if (idx == 7) begin
                        state <= START_DIV;
                    end else begin
                        idx <= idx + 1;
                    end
                end

                START_DIV: begin
                    if (total_sum == 0) begin
                        // CRITICAL ROBOTIC LOGIC: We lost the line!
                        // If total_sum is 0, no sensors see the line. The robot ran off the track.
                        // We use our 'last_pos' memory to guess where the line went.
                        if (last_pos < 3500) begin
                            position <= 16'd0;    // It was on the left, so steer hard left!
                        end else begin
                            position <= 16'd7000; // It was on the right, so steer hard right!
                        end
                        state <= DONE; // Skip division since we already know the answer
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
                    pos_ready <= 1; // Tell the motor controller we have a new steering command!
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule