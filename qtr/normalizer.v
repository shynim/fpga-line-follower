module normalizer (
    input wire clk,
    input wire rst,
    input wire data_ready,             // Triggers when fresh RAW data is available
    input wire [127:0] raw_values,     // From Module 1 (Raw Reader)
    input wire [127:0] min_values,     // From Module 2 (Calibration)
    input wire [127:0] max_values,     // From Module 2 (Calibration)
    
    // Output: 8 sensors, each scaled 0 to 1000 (Packed into 128 bits)
    output reg [127:0] normalized_values,
    output reg norm_ready              // Pulses high when all 8 sensors are scaled
);

    // State Machine
    localparam IDLE      = 2'd0;
    localparam SETUP_DIV = 2'd1;
    localparam WAIT_DIV  = 2'd2;
    localparam DONE      = 2'd3;

    reg [1:0] state = IDLE;
    reg [3:0] sensor_idx; // Counts 0 to 7 to process each sensor

    // Wires to control our custom sequential divider
    reg div_start;
    reg [31:0] div_num;
    reg [31:0] div_den;
    wire [31:0] div_quotient;
    wire [31:0] div_remainder;
    wire div_ready;

    // Instantiate the custom Sequential Divider you wrote earlier!
    // Make sure sequential_divider.v is in your src/ folder.
    seq_divider my_divider (
        .clk(clk),
        .rst(rst),
        .start(div_start),
        .num(div_num),
        .den(div_den),
        .quotient(div_quotient),
        .remainder(div_remainder),
        .ready(div_ready)
    );

    // Temporary registers for the math
    reg [31:0] raw, min_val, max_val, numerator, denominator;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            sensor_idx <= 0;
            div_start <= 0;
            norm_ready <= 0;
            normalized_values <= 128'd0;
        end else begin
            case (state)
                IDLE: begin
                    norm_ready <= 0;
                    div_start <= 0;
                    // Wait until Module 1 shouts that fresh data is ready
                    if (data_ready) begin
                        sensor_idx <= 0;
                        state <= SETUP_DIV;
                    end
                end

                SETUP_DIV: begin
                    // 1. Extract the specific 16-bit slice for the current sensor
                    raw     = raw_values[sensor_idx*16 +: 16];
                    min_val = min_values[sensor_idx*16 +: 16];
                    max_val = max_values[sensor_idx*16 +: 16];

                    // 2. Perform Subtraction & Multiplication (Numerator: Raw - Min)
                    // If raw is lower than our calibrated min, treat it as 0 to prevent negative math
                    if (raw > min_val) begin
                        numerator = (raw - min_val) * 1000; 
                    end else begin
                        numerator = 0; 
                    end

                    // 3. Perform Subtraction (Denominator: Max - Min)
                    if (max_val > min_val) begin
                        denominator = max_val - min_val;
                    end else begin
                        denominator = 1; // NEVER divide by zero!
                    end

                    // 4. Load the numbers into the hardware divider and pulse start
                    div_num <= numerator;
                    div_den <= denominator;
                    div_start <= 1;
                    state <= WAIT_DIV;
                end

                WAIT_DIV: begin
                    div_start <= 0; // Turn off the start pulse
                    
                    // Wait for the divider to finish its 32 clock cycles
                    if (div_ready) begin
                        // Clamp the result to a maximum of 1000 just in case
                        if (div_quotient > 1000) begin
                            normalized_values[sensor_idx*16 +: 16] <= 16'd1000;
                        end else begin
                            normalized_values[sensor_idx*16 +: 16] <= div_quotient[15:0];
                        end

                        // Move to the next sensor, or finish if we did all 8
                        if (sensor_idx == 7) begin
                            state <= DONE;
                        end else begin
                            sensor_idx <= sensor_idx + 1;
                            state <= SETUP_DIV;
                        end
                    end
                end

                DONE: begin
                    norm_ready <= 1; // Tell the final Position Calculator the data is clean!
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule