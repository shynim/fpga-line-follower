module qtr_motor_test_top (
    input wire clk,
    input wire btn1,              // Physical reset button
    input wire btn2,              // Physical calibration button
    inout wire [7:0] s,           // The 8 QTR pins
    output wire uart_tx,          // To your computer
    output wire [5:0] led,        // LED to show calibration state!
    output wire stby              // Hardware Kill Switch
    
    // (Optional) You can uncomment your motor pins here if you want to attach the driver!
    // output wire pwma, ain1, ain2, pwmb, bin1, bin2
);

    assign stby = 1'b0; // KEEP MOTORS OFF for desktop testing!

    wire rst = ~btn1;
    wire calib_btn = ~btn2; 

    // --- 1 to 4. RUN ALL PREVIOUS MODULES ---
    wire raw_ready; wire [127:0] raw_vals;
    qtr_raw_reader reader_inst (.clk(clk), .rst(rst), .start(1'b1), .sensor_pins(s), .sensor_values(raw_vals), .data_ready(raw_ready));

    wire [127:0] calib_mins; wire [127:0] calib_maxes; wire is_calibrating;
    qtr_calibration calib_inst (.clk(clk), .rst(rst), .btn2(calib_btn), .calib_time_ms(16'd5000), .data_ready(raw_ready), .sensor_values(raw_vals), .min_values(calib_mins), .max_values(calib_maxes), .is_calibrating(is_calibrating));

    assign led[5] = ~is_calibrating;
    assign led[4:0] = 5'b11111; 

    wire norm_ready; wire [127:0] norm_vals;
    normalizer norm_inst (.clk(clk), .rst(rst), .data_ready(raw_ready), .raw_values(raw_vals), .min_values(calib_mins), .max_values(calib_maxes), .normalized_values(norm_vals), .norm_ready(norm_ready));

    wire pos_ready; wire [15:0] steering_position;
    position pos_inst (.clk(clk), .rst(rst), .norm_ready(norm_ready), .normalized_values(norm_vals), .position(steering_position), .pos_ready(pos_ready));

    // --- 5. RUN THE PID CALCULATOR ---
    wire steer_ready;
    wire signed [15:0] steering_correction;
    
    pid pid_inst (
        .clk(clk),
        .rst(rst),
        .pos_ready(pos_ready),
        .position(steering_position),
        // Hardcode some test tuning values here for now!
        .kp(16'd20), 
        .kd(16'd0),
        .steering_correction(steering_correction),
        .steer_ready(steer_ready)
    );

    // --- 6. APPLY TO MOTORS ---
    wire [7:0] speed_a;
    wire [7:0] speed_b;
    wire [1:0] dir_a;
    wire [1:0] dir_b;

    apply_pid #(
        .BASE_SPEED(8'd100), 
        .SHIFT(3'd6)
    ) apply_inst (
        .clk(clk),
        .rst(rst),
        .steer_ready(steer_ready),
        .steering_correction(steering_correction),
        .speed_a(speed_a),
        .speed_b(speed_b),
        .dir_a(dir_a),
        .dir_b(dir_b)
    );

    // ========================================================
    // UART PRINTING: Position (16-bit) and Speeds (8-bit each)
    // ========================================================
    
    // 10Hz (100ms) PRINT TIMER
    reg [21:0] sample_timer = 0;
    reg trigger_print = 0;
    
    always @(posedge clk) begin
        if (rst) begin
            sample_timer <= 0; trigger_print <= 0;
        end else begin
            if (sample_timer >= 22'd2_700_000) begin
                sample_timer <= 0; trigger_print <= 1;
            end else begin
                sample_timer <= sample_timer + 1; trigger_print <= 0;
            end
        end
    end

    // UART TRANSMITTER
    reg uart_transmit;
    reg [7:0] uart_data;
    wire uart_busy;

    uart_tx my_uart (.clk(clk), .data_in(uart_data), .transmit(uart_transmit), .uart_tx_pin(uart_tx), .tx_busy(uart_busy));

    // PRINT HEX + SPACES TO SCREEN
    reg [4:0] state = 0; // Increased to 5-bit to hold up to 24 states
    
    // We grab all 3 values at once: {16-bit Pos, 8-bit SpeedA, 8-bit SpeedB}
    reg [31:0] captured_val;
    wire [31:0] test_signal = {steering_position, speed_a, speed_b};
    
    // Combinational ASCII Lookups
    wire [7:0] char1 = (captured_val[31:28] < 10) ? (captured_val[31:28] + 8'd48) : (captured_val[31:28] + 8'd55);
    wire [7:0] char2 = (captured_val[27:24] < 10) ? (captured_val[27:24] + 8'd48) : (captured_val[27:24] + 8'd55);
    wire [7:0] char3 = (captured_val[23:20] < 10) ? (captured_val[23:20] + 8'd48) : (captured_val[23:20] + 8'd55);
    wire [7:0] char4 = (captured_val[19:16] < 10) ? (captured_val[19:16] + 8'd48) : (captured_val[19:16] + 8'd55);
    wire [7:0] char5 = (captured_val[15:12] < 10) ? (captured_val[15:12] + 8'd48) : (captured_val[15:12] + 8'd55);
    wire [7:0] char6 = (captured_val[11:8] < 10)  ? (captured_val[11:8] + 8'd48)  : (captured_val[11:8] + 8'd55);
    wire [7:0] char7 = (captured_val[7:4] < 10)   ? (captured_val[7:4] + 8'd48)   : (captured_val[7:4] + 8'd55);
    wire [7:0] char8 = (captured_val[3:0] < 10)   ? (captured_val[3:0] + 8'd48)   : (captured_val[3:0] + 8'd55);

    always @(posedge clk) begin
        if (rst) begin
            state <= 0; uart_transmit <= 0;
        end else begin
            case (state)
                0: begin
                    uart_transmit <= 0;
                    if (trigger_print) begin captured_val <= test_signal; state <= 1; end
                end
                
                // POSITION (4 Chars)
                1: if (!uart_busy && !uart_transmit) begin uart_data <= char1; uart_transmit <= 1; state <= 2; end
                2: begin uart_transmit <= 0; if (!uart_busy) state <= 3; end
                3: if (!uart_busy && !uart_transmit) begin uart_data <= char2; uart_transmit <= 1; state <= 4; end
                4: begin uart_transmit <= 0; if (!uart_busy) state <= 5; end
                5: if (!uart_busy && !uart_transmit) begin uart_data <= char3; uart_transmit <= 1; state <= 6; end
                6: begin uart_transmit <= 0; if (!uart_busy) state <= 7; end
                7: if (!uart_busy && !uart_transmit) begin uart_data <= char4; uart_transmit <= 1; state <= 8; end
                8: begin uart_transmit <= 0; if (!uart_busy) state <= 9; end
                
                // SPACE
                9:  if (!uart_busy && !uart_transmit) begin uart_data <= 8'h20; uart_transmit <= 1; state <= 10; end
                10: begin uart_transmit <= 0; if (!uart_busy) state <= 11; end
                
                // LEFT SPEED (2 Chars)
                11: if (!uart_busy && !uart_transmit) begin uart_data <= char5; uart_transmit <= 1; state <= 12; end
                12: begin uart_transmit <= 0; if (!uart_busy) state <= 13; end
                13: if (!uart_busy && !uart_transmit) begin uart_data <= char6; uart_transmit <= 1; state <= 14; end
                14: begin uart_transmit <= 0; if (!uart_busy) state <= 15; end
                
                // SPACE
                15: if (!uart_busy && !uart_transmit) begin uart_data <= 8'h20; uart_transmit <= 1; state <= 16; end
                16: begin uart_transmit <= 0; if (!uart_busy) state <= 17; end
                
                // RIGHT SPEED (2 Chars)
                17: if (!uart_busy && !uart_transmit) begin uart_data <= char7; uart_transmit <= 1; state <= 18; end
                18: begin uart_transmit <= 0; if (!uart_busy) state <= 19; end
                19: if (!uart_busy && !uart_transmit) begin uart_data <= char8; uart_transmit <= 1; state <= 20; end
                20: begin uart_transmit <= 0; if (!uart_busy) state <= 21; end
                
                // CARRIAGE RETURN / NEWLINE
                21: if (!uart_busy && !uart_transmit) begin uart_data <= 8'h0D; uart_transmit <= 1; state <= 22; end
                22: begin uart_transmit <= 0; if (!uart_busy) state <= 23; end
                23: if (!uart_busy && !uart_transmit) begin uart_data <= 8'h0A; uart_transmit <= 1; state <= 24; end
                24: begin uart_transmit <= 0; if (!uart_busy) state <= 0; end
            endcase
        end
    end
endmodule