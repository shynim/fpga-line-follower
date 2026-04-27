module qtr_raw_reader (
    input wire clk,             // 27 MHz clock from Tang Nano 9K
    input wire rst,             // Active high reset
    input wire start,           // Pulse high to start a reading
    
    inout wire [7:0] sensor_pins, // The 8 physical pins connected to the QTR-8RC
    
    // Output is a flat 128-bit bus (8 sensors * 16 bits each)
    output reg [127:0] sensor_values, 
    output reg data_ready       // Pulses high when reading is complete
);

    // State Machine definitions
    localparam STATE_IDLE    = 2'd0;
    localparam STATE_CHARGE  = 2'd1;
    localparam STATE_MEASURE = 2'd2;
    localparam STATE_DONE    = 2'd3;

    reg [1:0] state = STATE_IDLE;

    // Timing Constants for a 27 MHz clock (~37ns per tick)
    // 10 microseconds = 270 clock cycles
    // 2500 microseconds timeout = 67,500 clock cycles
    localparam CHARGE_TICKS = 16'd270;
    localparam TIMEOUT_TICKS = 16'd65535;
    
    reg [16:0] timer;
    reg [7:0] pin_state_sync; 
    reg [7:0] done_mask; // Tracks which of the 8 sensors have finished discharging
    reg [15:0] times [7:0]; // Internal array to store the 8 individual times

    integer i;

    // --- Tri-State Pin Logic ---
    // If state is CHARGE, drive pins HIGH (8'b11111111). 
    // Otherwise, set to high-impedance (8'bZZZZZZZZ) so they act as inputs.
    assign sensor_pins = (state == STATE_CHARGE) ? 8'hFF : 8'hZZ;

    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            data_ready <= 0;
            timer <= 0;
            done_mask <= 0;
            sensor_values <= 0;
            for (i = 0; i < 8; i = i + 1) begin
                times[i] <= 0;
            end
        end else begin
            // Synchronize the external pins to the clock domain
            pin_state_sync <= sensor_pins;

            case (state)
                STATE_IDLE: begin
                    data_ready <= 0;
                    if (start) begin
                        state <= STATE_CHARGE;
                        timer <= 0;
                        done_mask <= 0;
                        for (i = 0; i < 8; i = i + 1) times[i] <= 0;
                    end
                end

                STATE_CHARGE: begin
                    if (timer < CHARGE_TICKS) begin
                        timer <= timer + 1;
                    end else begin
                        state <= STATE_MEASURE;
                        timer <= 0; // Reset timer for the measurement phase
                    end
                end

                STATE_MEASURE: begin
                    timer <= timer + 1;

                    // Check all 8 pins simultaneously
                    for (i = 0; i < 8; i = i + 1) begin
                        // If the pin went LOW and we haven't recorded it yet
                        if (pin_state_sync[i] == 1'b0 && done_mask[i] == 1'b0) begin
                            times[i] <= timer[15:0];
                            done_mask[i] <= 1'b1; // Mark this sensor as complete
                        end
                    end

                    // Stop if all pins are LOW, or if we hit the maximum timeout limit
                    if (done_mask == 8'hFF || timer >= TIMEOUT_TICKS) begin
                        // For any sensor over a completely black line that never discharged,
                        // force its time to the maximum timeout value.
                        for (i = 0; i < 8; i = i + 1) begin
                            if (done_mask[i] == 1'b0) begin
                                times[i] <= TIMEOUT_TICKS[15:0];
                            end
                        end
                        state <= STATE_DONE;
                    end
                end

                STATE_DONE: begin
                    // Standard Verilog does not easily allow 2D arrays (like int array) 
                    // in module outputs. So, we pack the 8 16-bit values into a single 128-bit wire.
                    sensor_values[15:0]   <= times[0];
                    sensor_values[31:16]  <= times[1];
                    sensor_values[47:32]  <= times[2];
                    sensor_values[63:48]  <= times[3];
                    sensor_values[79:64]  <= times[4];
                    sensor_values[95:80]  <= times[5];
                    sensor_values[111:96] <= times[6];
                    sensor_values[127:112]<= times[7];

                    data_ready <= 1; // Tell the next module the data is ready!
                    state <= STATE_IDLE;
                end
            endcase
        end
    end
endmodule