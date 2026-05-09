module qtr_calibration_test_top (
    input wire clk,
    input wire btn1,              // Physical reset button
    input wire btn2,              // Physical calibration button
    inout wire [7:0] s,           // The 8 QTR pins
    output wire uart_tx,          // To your computer
    output wire [5:0] led         // Let's use an LED to show calibration state!
);

    wire rst = ~btn1;
    wire calib_btn = ~btn2; // Invert so it triggers when pushed

    // --- 1. RUN THE RAW READER ---
    wire raw_ready;
    wire [127:0] raw_vals;
    
    qtr_raw_reader reader_inst (
        .clk(clk),
        .rst(rst),
        .start(1'b1), 
        .sensor_pins(s),
        .sensor_values(raw_vals),
        .data_ready(raw_ready)
    );
    
    // --- 2. RUN THE CALIBRATION MEMORY ---
    wire [127:0] calib_mins;
    wire [127:0] calib_maxes;
    wire is_calibrating;
    
    qtr_calibration calib_inst (
        .clk(clk),
        .rst(rst),
        .btn2(calib_btn),
        .calib_time_ms(16'd5000), // Calibrate for 5 seconds
        .data_ready(raw_ready),
        .sensor_values(raw_vals),
        .min_values(calib_mins),
        .max_values(calib_maxes),
        .is_calibrating(is_calibrating)
    );
    
    // Turn on Tang Nano LED 5 when calibrating (Active Low)
    assign led[5] = ~is_calibrating;
    assign led[4:0] = 5'b11111; // Keep others off

    // ========================================================
    // TEST SIGNAL: Looking at Sensor 0's MAX value memory!
    // ========================================================
    wire [15:0] test_signal = calib_maxes[15:0];
    
    // --- 3. 10Hz (100ms) PRINT TIMER ---
    reg [21:0] sample_timer = 0;
    reg trigger_print = 0;
    
    always @(posedge clk) begin
        if (rst) begin
            sample_timer <= 0;
            trigger_print <= 0;
        end else begin
            if (sample_timer >= 22'd2_700_000) begin
                sample_timer <= 0;
                trigger_print <= 1; // Time to print!
            end else begin
                sample_timer <= sample_timer + 1;
                trigger_print <= 0;
            end
        end
    end

    // --- 4. UART TRANSMITTER ---
    reg uart_transmit;
    reg [7:0] uart_data;
    wire uart_busy;

    uart_tx my_uart (
        .clk(clk),
        .data_in(uart_data),
        .transmit(uart_transmit),
        .uart_tx_pin(uart_tx),
        .tx_busy(uart_busy)
    );
    
    // --- 5. PRINT HEX TO SCREEN ---
    reg [3:0] state = 0;
    reg [15:0] captured_val;
    reg [3:0] nibble;
    reg [7:0] ascii_char;

    always @(*) begin
        if (nibble < 10) ascii_char = nibble + 8'd48; // '0'-'9'
        else             ascii_char = nibble + 8'd55; // 'A'-'F'
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= 0;
            uart_transmit <= 0;
        end else begin
            case (state)
                0: begin
                    uart_transmit <= 0;
                    if (trigger_print) begin
                        captured_val <= test_signal;
                        nibble <= test_signal[15:12]; // FIX: PRE-LOAD
                        state <= 1;
                    end
                end
                1: if (!uart_busy && !uart_transmit) begin 
                    uart_data <= ascii_char; 
                    uart_transmit <= 1; 
                    nibble <= captured_val[11:8]; // FIX: PRE-LOAD
                    state <= 2; 
                end
                2: begin uart_transmit <= 0;
                    if (!uart_busy) state <= 3; end
                3: if (!uart_busy && !uart_transmit) begin 
                    uart_data <= ascii_char; 
                    uart_transmit <= 1; 
                    nibble <= captured_val[7:4]; // FIX: PRE-LOAD
                    state <= 4; 
                end
                4: begin uart_transmit <= 0;
                    if (!uart_busy) state <= 5; end
                5: if (!uart_busy && !uart_transmit) begin 
                    uart_data <= ascii_char; 
                    uart_transmit <= 1; 
                    nibble <= captured_val[3:0]; // FIX: PRE-LOAD
                    state <= 6; 
                end
                6: begin uart_transmit <= 0;
                    if (!uart_busy) state <= 7; end
                7: if (!uart_busy && !uart_transmit) begin 
                    uart_data <= ascii_char; 
                    uart_transmit <= 1; 
                    state <= 8; 
                end
                8: begin uart_transmit <= 0;
                    if (!uart_busy) state <= 9; end
                9: if (!uart_busy && !uart_transmit) begin 
                    uart_data <= 8'h0D; 
                    uart_transmit <= 1; 
                    state <= 10; 
                end
                10: begin uart_transmit <= 0;
                    if (!uart_busy) state <= 11; end
                11: if (!uart_busy && !uart_transmit) begin 
                    uart_data <= 8'h0A; 
                    uart_transmit <= 1; 
                    state <= 12; 
                end
                12: begin uart_transmit <= 0;
                    if (!uart_busy) state <= 0; end
            endcase
        end
    end
endmodule