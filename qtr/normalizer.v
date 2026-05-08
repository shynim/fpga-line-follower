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
    localparam IDLE      = 3'd0;
    localparam FEED_PIPE = 3'd1;  // Feeding all 8 divisions into pipeline
    localparam DRAIN_PIPE = 3'd2; // Collecting results from pipeline
    localparam DONE      = 3'd3;

    reg [2:0] state = IDLE;
    reg [3:0] feed_idx;    // Index for feeding sensors into pipeline
    reg [3:0] drain_idx;   // Index for collecting results
    
    // Pipeline divider signals (Trimmed to 24 bits to save space!)
    reg [23:0] div_dividend;
    reg [23:0] div_divisor;
    wire [23:0] div_quotient;
    wire [23:0] div_remainder;
    
    // Pipeline wait counter
    reg [5:0] wait_counter;
    
    // Temporary registers for math calculations
    reg [15:0] raw, min_val, max_val;
    reg [15:0] diff_16; // Forces the subtraction to be exactly 16-bit
    reg [31:0] numerator, denominator;

    // Register to remember we're in the middle of processing
    reg processing;

    // Instantiate the pipelined divider (Trimmed to 24-bit width)
    pip_divider #(.WIDTH(24)) my_pip_divider (
        .clk(clk),
        .dividend(div_dividend),
        .divisor(div_divisor),
        .quotient(div_quotient),
        .remainder(div_remainder)
    );

    // Combinational logic to extract current sensor values
    always @(*) begin
        raw     = raw_values[feed_idx*16 +: 16];
        min_val = min_values[feed_idx*16 +: 16];
        max_val = max_values[feed_idx*16 +: 16];
        
        // --- THE DSP MULTIPLIER TRICK ---
        // 1. Calculate the difference as a strict 16-bit number
        if (raw > min_val) begin
            diff_16 = raw - min_val;
        end else begin
            diff_16 = 16'd0;
        end

        // 2. 16-bit * 16-bit multiplication maps perfectly to the MULT18X18 hardware block!
        numerator = diff_16 * 16'd1000; 
        // --------------------------------

        // Calculate denominator: (max - min)
        if (max_val > min_val) begin
            denominator = max_val - min_val;
        end else begin
            denominator = 1; // Avoid division by zero
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            feed_idx <= 0;
            drain_idx <= 0;
            wait_counter <= 0;
            processing <= 0;
            norm_ready <= 0;
            normalized_values <= 128'd0;
            div_dividend <= 0;
            div_divisor <= 1;
        end else begin
            case (state)
                IDLE: begin
                    norm_ready <= 0;
                    feed_idx <= 0;
                    drain_idx <= 0;
                    wait_counter <= 0;
                    processing <= 0;
                    
                    if (data_ready) begin
                        processing <= 1;
                        state <= FEED_PIPE;
                    end
                end

                FEED_PIPE: begin
                    // Feed all 8 sensors into the pipeline, one per clock cycle
                    if (feed_idx < 8) begin
                        div_dividend <= numerator[23:0]; // Cast to 24-bit
                        div_divisor <= denominator[23:0]; // Cast to 24-bit
                        
                        feed_idx <= feed_idx + 1;
                        
                        // After feeding the 8th value, transition to drain
                        if (feed_idx == 7) begin
                            // FIX: 24 pipeline stages - 8 cycles + 2 reg delays = 18
                            wait_counter <= 6'd18; 
                            state <= DRAIN_PIPE;
                        end
                    end else begin
                        // Safety: if feed_idx somehow goes past 7
                        wait_counter <= 6'd18;
                        state <= DRAIN_PIPE;
                    end
                end

                DRAIN_PIPE: begin
                    if (wait_counter > 0) begin
                        // Still waiting for pipeline to fill
                        wait_counter <= wait_counter - 1;
                    end else if (drain_idx < 8) begin
                        // Pipeline is full, results are flowing out
                        // Store the result for current drain_idx
                        if (div_quotient > 1000) begin
                            normalized_values[drain_idx*16 +: 16] <= 16'd1000;
                        end else begin
                            normalized_values[drain_idx*16 +: 16] <= div_quotient[15:0];
                        end
                        drain_idx <= drain_idx + 1;
                        
                        // Check if we've collected all 8 results
                        if (drain_idx == 7) begin
                            state <= DONE;
                        end
                    end
                end

                DONE: begin
                    norm_ready <= 1;
                    processing <= 0;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule