module qtr_calibration (
    input wire clk,
    input wire rst,
    input wire btn2,                // Physical push button on the Tang Nano
    input wire [15:0] calib_time_ms,  // Adjustable calibration time (in milliseconds)
    input wire data_ready,            // From Module 1
    input wire [127:0] sensor_values, // From Module 1
    
    output reg [127:0] min_values,
    output reg [127:0] max_values,
    output reg is_calibrating         // Wire this to an LED on your board!
);

    // State Machine Definitions
    localparam STATE_IDLE        = 2'd0;
    localparam STATE_WAIT        = 2'd1;
    localparam STATE_CALIBRATING = 2'd2;
    localparam STATE_DONE        = 2'd3;

    reg [1:0] state = STATE_IDLE;

    // Timing Constants for 27 MHz Clock
    parameter ONE_SECOND_TICKS = 32'd27_000_000; 
    parameter TICKS_PER_MS     = 32'd27_000;

    reg [31:0] timer;
    reg button_prev; 
    reg [15:0] current_val;
    integer i;

    // Edge detector: triggers only once exactly when the button is pushed down
    wire button_pressed = (btn2 == 1'b1 && button_prev == 1'b0);

    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            timer <= 0;
            is_calibrating <= 0;
            button_prev <= 0;
            
            // Set safe default values on reset
            for (i = 0; i < 8; i = i + 1) begin
                min_values[i*16 +: 16] <= 16'hFFFF;
                max_values[i*16 +: 16] <= 16'h0000;
            end
        end else begin
            // Keep track of the button's previous state for the edge detector
            button_prev <= btn2;

            case (state)
                STATE_IDLE: begin
                    is_calibrating <= 0;
                    if (button_pressed) begin
                        state <= STATE_WAIT;
                        timer <= 0;
                    end
                end

                STATE_WAIT: begin
                    // Count up to exactly 1 second
                    if (timer < ONE_SECOND_TICKS) begin
                        timer <= timer + 1;
                    end else begin
                        state <= STATE_CALIBRATING;
                        timer <= 0;
                        is_calibrating <= 1'b1; // Turn on the LED!
                        
                        // We must reset the arrays BEFORE taking new readings, 
                        // otherwise old calibrations will pollute the new ones.
                        for (i = 0; i < 8; i = i + 1) begin
                            min_values[i*16 +: 16] <= 16'hFFFF;
                            max_values[i*16 +: 16] <= 16'h0000;
                        end
                    end
                end

                STATE_CALIBRATING: begin
                    // Keep counting time to see when calibration should end
                    timer <= timer + 1;
                    
                    // If we get fresh data from Module 1, update the min/max arrays
                    if (data_ready) begin
                        for (i = 0; i < 8; i = i + 1) begin
                            current_val = sensor_values[i*16 +: 16];
                            
                            if (current_val < min_values[i*16 +: 16]) begin
                                min_values[i*16 +: 16] <= current_val;
                            end
                            
                            if (current_val > max_values[i*16 +: 16]) begin
                                max_values[i*16 +: 16] <= current_val;
                            end
                        end
                    end

                    // Check if our adjustable timer has expired
                    // Target ticks = (Milliseconds * 27,000)
                    if (timer >= (calib_time_ms * TICKS_PER_MS)) begin
                        state <= STATE_DONE;
                        is_calibrating <= 0; // Turn off the LED
                    end
                end

                STATE_DONE: begin
                    // Do nothing with the data, just hold the locked min/max values forever.
                    // If the user pushes the button again, restart the 1-second timer!
                    if (button_pressed) begin
                        state <= STATE_WAIT;
                        timer <= 0;
                    end
                end
            endcase
        end
    end
endmodule