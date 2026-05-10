module qtr_motor_test_top (
    input wire clk,
    input wire btn1,              // Physical reset button
    input wire btn2,              // Physical calibration button
    inout wire [7:0] s,           // The 8 QTR pins
    output wire uart_tx,          // To your computer
    input wire uart_rx,           // NEW: Receive data from your computer
    output wire [5:0] led,        // LED to show calibration state
    output wire stby              // Hardware Kill Switch
    
    // (Optional) Uncomment your motor pins here if you want to attach the driver!
    // output wire pwma, ain1, ain2, pwmb, bin1, bin2
);

    // ==========================================
    // HARDWARE KILL SWITCH: KEEP MOTORS OFF FOR DESK TESTING
    // ==========================================
    assign stby = 1'b0; 

    wire rst = ~btn1;
    wire calib_btn = ~btn2; 

    // --- 1. RUN RAW READER ---
    wire raw_ready; wire [127:0] raw_vals;
    qtr_raw_reader reader_inst (.clk(clk), .rst(rst), .start(1'b1), .sensor_pins(s), .sensor_values(raw_vals), .data_ready(raw_ready));

    // --- 2. RUN CALIBRATION ---
    wire [127:0] calib_mins; wire [127:0] calib_maxes; wire is_calibrating;
    qtr_calibration calib_inst (.clk(clk), .rst(rst), .btn2(calib_btn), .calib_time_ms(16'd5000), .data_ready(raw_ready), .sensor_values(raw_vals), .min_values(calib_mins), .max_values(calib_maxes), .is_calibrating(is_calibrating));

    assign led[5] = ~is_calibrating;
    assign led[4:0] = 5'b11111; 

    // --- 3. RUN NORMALIZER ---
    wire norm_ready; wire [127:0] norm_vals;
    normalizer norm_inst (.clk(clk), .rst(rst), .data_ready(raw_ready), .raw_values(raw_vals), .min_values(calib_mins), .max_values(calib_maxes), .normalized_values(norm_vals), .norm_ready(norm_ready));

    // --- 4. RUN POSITION CALCULATOR ---
    wire pos_ready; wire [15:0] steering_position;
    position pos_inst (.clk(clk), .rst(rst), .norm_ready(norm_ready), .normalized_values(norm_vals), .position(steering_position), .pos_ready(pos_ready));

    // --- NEW: UART RECEIVER ---
    wire rx_ready;
    wire [7:0] rx_data;
    
    // Uses your specific uart_rx.v file
    uart_rx my_rx (
        .clk(clk),
        .uart_rx_pin(uart_rx),
        .data_out(rx_data),
        .byte_ready(rx_ready)
    );

    // --- LIVE PID PARSER ---
    wire [15:0] live_kp;
    wire [15:0] live_ki;
    wire [15:0] live_kd;
    wire [7:0] live_base_speed; // NEW
    wire [7:0] live_max_speed;  // NEW
    
    pid_parser live_tune (
        .clk(clk),
        .rst(rst),
        .byte_ready(rx_ready),
        .data_in(rx_data),
        .reg_p(live_kp),
        .reg_i(live_ki),
        .reg_d(live_kd),
        .reg_b(live_base_speed), // NEW
        .reg_m(live_max_speed)   // NEW
    );

    // --- 5. RUN PID CALCULATOR ---
    wire steer_ready;
    wire signed [15:0] steering_correction;
    
    pid pid_inst (
        .clk(clk),
        .rst(rst),
        .pos_ready(pos_ready),
        .position(steering_position),
        // Hooked up to our live parser!
        .kp(live_kp), 
        .kd(live_kd),
        .steering_correction(steering_correction),
        .steer_ready(steer_ready)
    );

    // --- 6. APPLY TO MOTORS ---
    wire [7:0] speed_a;
    wire [7:0] speed_b;
    wire [1:0] dir_a;
    wire [1:0] dir_b;

    apply_pid #(
        .SHIFT(3'd6) // BASE_SPEED was removed from here!
    ) apply_inst (
        .clk(clk),
        .rst(rst),
        .steer_ready(steer_ready),
        .steering_correction(steering_correction),
        
        .base_speed(live_base_speed), // NEW: Plug live base speed in
        .max_speed(live_max_speed),   // NEW: Plug live max speed in
        
        .speed_a(speed_a),
        .speed_b(speed_b),
        .dir_a(dir_a),
        .dir_b(dir_b)
    );

    // ========================================================
    // UART PRINTING: Position (16-bit) and Speeds (8-bit each)
    // ========================================================
    
    reg [21:0] sample_timer = 0;
    reg trigger_print = 0;
    
    always @(posedge clk) begin
        if (rst) begin
            sample_timer <= 0; trigger_print <= 0;
        end else begin
            if (sample_timer >= 22'd2_700_000) begin // 10Hz
                sample_timer <= 0; trigger_print <= 1;
            end else begin
                sample_timer <= sample_timer + 1; trigger_print <= 0;
            end
        end
    end

    reg uart_transmit;
    reg [7:0] uart_data;
    wire uart_busy;

    uart_tx my_uart (.clk(clk), .data_in(uart_data), .transmit(uart_transmit), .uart_tx_pin(uart_tx), .tx_busy(uart_busy));

    reg [4:0] state = 0; 
    
    // Grab all 3 values at once: {16-bit Pos, 8-bit SpeedA, 8-bit SpeedB}
    reg [31:0] captured_val;
    wire [31:0] test_signal = {steering_position, speed_a, speed_b};
    
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
                
                1: if (!uart_busy && !uart_transmit) begin uart_data <= char1; uart_transmit <= 1; state <= 2; end
                2: begin uart_transmit <= 0; if (!uart_busy) state <= 3; end
                3: if (!uart_busy && !uart_transmit) begin uart_data <= char2; uart_transmit <= 1; state <= 4; end
                4: begin uart_transmit <= 0; if (!uart_busy) state <= 5; end
                5: if (!uart_busy && !uart_transmit) begin uart_data <= char3; uart_transmit <= 1; state <= 6; end
                6: begin uart_transmit <= 0; if (!uart_busy) state <= 7; end
                7: if (!uart_busy && !uart_transmit) begin uart_data <= char4; uart_transmit <= 1; state <= 8; end
                8: begin uart_transmit <= 0; if (!uart_busy) state <= 9; end
                
                9:  if (!uart_busy && !uart_transmit) begin uart_data <= 8'h20; uart_transmit <= 1; state <= 10; end
                10: begin uart_transmit <= 0; if (!uart_busy) state <= 11; end
                
                11: if (!uart_busy && !uart_transmit) begin uart_data <= char5; uart_transmit <= 1; state <= 12; end
                12: begin uart_transmit <= 0; if (!uart_busy) state <= 13; end
                13: if (!uart_busy && !uart_transmit) begin uart_data <= char6; uart_transmit <= 1; state <= 14; end
                14: begin uart_transmit <= 0; if (!uart_busy) state <= 15; end
                
                15: if (!uart_busy && !uart_transmit) begin uart_data <= 8'h20; uart_transmit <= 1; state <= 16; end
                16: begin uart_transmit <= 0; if (!uart_busy) state <= 17; end
                
                17: if (!uart_busy && !uart_transmit) begin uart_data <= char7; uart_transmit <= 1; state <= 18; end
                18: begin uart_transmit <= 0; if (!uart_busy) state <= 19; end
                19: if (!uart_busy && !uart_transmit) begin uart_data <= char8; uart_transmit <= 1; state <= 20; end
                20: begin uart_transmit <= 0; if (!uart_busy) state <= 21; end
                
                21: if (!uart_busy && !uart_transmit) begin uart_data <= 8'h0D; uart_transmit <= 1; state <= 22; end
                22: begin uart_transmit <= 0; if (!uart_busy) state <= 23; end
                23: if (!uart_busy && !uart_transmit) begin uart_data <= 8'h0A; uart_transmit <= 1; state <= 24; end
                24: begin uart_transmit <= 0; if (!uart_busy) state <= 0; end
            endcase
        end
    end
endmodule