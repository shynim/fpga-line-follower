module top (
    input wire clk,
    input wire btn1,              // Physical reset button
    input wire btn2,              // Multi-function action button
    inout wire [7:0] s,           // The 8 QTR pins
    output wire uart_tx,          // To your computer
    input wire uart_rx,           // Receive tuning from your computer
    output wire [5:0] led,        // LED to show states
    
    // Motor Pins
    output wire pwma, ain1, ain2, 
    output wire pwmb, bin1, bin2,
    output wire stby              // Hardware Kill Switch (Now controlled by State Machine!)
);

    wire rst = ~btn1;
    wire raw_btn2 = ~btn2; 

    // ==========================================
    // 1. BUTTON DEBOUNCER (Filters out hardware bouncing)
    // ==========================================
    reg [15:0] btn_counter = 0;
    reg btn2_clean = 0;
    reg btn2_last = 0;
    reg btn2_pulse = 0;

    always @(posedge clk) begin
        if (rst) begin
            btn_counter <= 0;
            btn2_clean <= 0;
            btn2_last <= 0;
            btn2_pulse <= 0;
        end else begin
            // Wait for signal to be stable for 65,536 clock cycles (~2.4ms)
            if (raw_btn2 != btn2_clean) begin
                btn_counter <= btn_counter + 1;
                if (btn_counter == 16'hFFFF) begin
                    btn2_clean <= raw_btn2;
                    btn_counter <= 0;
                end
            end else begin
                btn_counter <= 0;
            end

            // Create a 1-clock-cycle pulse when the button is successfully pressed
            btn2_pulse <= (btn2_clean && !btn2_last);
            btn2_last <= btn2_clean;
        end
    end

    // ==========================================
    // 2. MASTER STATE MACHINE
    // ==========================================
    localparam BOOT        = 3'd0;
    localparam CALIBRATING = 3'd1;
    localparam READY       = 3'd2;
    localparam COUNTDOWN   = 3'd3;
    localparam RUNNING     = 3'd4;
    localparam PAUSED      = 3'd5;

    reg [2:0] robot_state = BOOT;
    
    // 27 MHz clock. 1.5 seconds = 40,500,000 ticks. We need 26 bits to hold this number.
    reg [25:0] delay_timer = 0;
    
    reg trigger_calib = 0;

    // The Kill Switch is ONLY turned on (1'b1) when the robot is in the RUNNING state!
    assign stby = (robot_state == RUNNING) ? 1'b1 : 1'b0;

    always @(posedge clk) begin
        if (rst) begin
            robot_state <= BOOT;
            delay_timer <= 0;
            trigger_calib <= 0;
        end else begin
            case (robot_state)
                BOOT: begin
                    trigger_calib <= 0;
                    if (btn2_pulse) begin
                        trigger_calib <= 1; // "Press" the fake button
                        robot_state <= CALIBRATING;
                    end
                end

                CALIBRATING: begin
                    // 1. Hold the fake button down UNTIL the calibration module actually wakes up
                    if (is_calibrating) begin
                        trigger_calib <= 0; // It woke up! "Release" the fake button.
                    end

                    // 2. Only move to READY if we released the button AND it finished calibrating
                    if (!trigger_calib && !is_calibrating) begin
                        robot_state <= READY;
                    end
                end

                READY: begin
                    if (btn2_pulse) begin
                        delay_timer <= 0;
                        robot_state <= COUNTDOWN;
                    end
                end

                COUNTDOWN: begin
                    // 1.5 Second delay before launching
                    if (delay_timer >= 26'd40_500_000) begin
                        robot_state <= RUNNING;
                    end else begin
                        delay_timer <= delay_timer + 1;
                    end
                end

                RUNNING: begin
                    // Robot is driving! Wait for a pause command.
                    if (btn2_pulse) begin
                        robot_state <= PAUSED;
                    end
                end

                PAUSED: begin
                    // Robot is stopped. You can tune it here! Wait for a resume command.
                    if (btn2_pulse) begin
                        robot_state <= RUNNING;
                    end
                end
            endcase
        end
    end

    // Use LEDs to show us what state the robot is in!
    assign led[5] = (robot_state != CALIBRATING); // LED goes OUT when calibrating
    assign led[4] = (robot_state != COUNTDOWN);   // LED goes OUT during 1.5s countdown
    assign led[3] = (robot_state != RUNNING);     // LED goes OUT when driving
    assign led[2] = (robot_state != PAUSED);      // LED goes OUT when paused
    assign led[1:0] = 2'b11;


    // ==========================================
    // 3. THE SENSOR & MATH PIPELINE
    // ==========================================

    wire raw_ready; wire [127:0] raw_vals;
    qtr_raw_reader reader_inst (.clk(clk), .rst(rst), .start(1'b1), .sensor_pins(s), .sensor_values(raw_vals), .data_ready(raw_ready));

    wire [127:0] calib_mins; wire [127:0] calib_maxes; wire is_calibrating;
    
    // FIX: Changed btn2 input to use our new State Machine trigger!
    qtr_calibration calib_inst (
        .clk(clk), .rst(rst), 
        .btn2(trigger_calib), // Triggered by Master State Machine
        .calib_time_ms(16'd5000), 
        .data_ready(raw_ready), .sensor_values(raw_vals), 
        .min_values(calib_mins), .max_values(calib_maxes), .is_calibrating(is_calibrating)
    );

    wire norm_ready; wire [127:0] norm_vals;
    normalizer norm_inst (.clk(clk), .rst(rst), .data_ready(raw_ready), .raw_values(raw_vals), .min_values(calib_mins), .max_values(calib_maxes), .normalized_values(norm_vals), .norm_ready(norm_ready));

    wire pos_ready; wire [15:0] steering_position;
    position pos_inst (.clk(clk), .rst(rst), .norm_ready(norm_ready), .normalized_values(norm_vals), .position(steering_position), .pos_ready(pos_ready));

    // ==========================================
    // 4. LIVE TUNING & UART RECEIVER
    // ==========================================
    wire rx_ready; wire [7:0] rx_data;
    uart_rx my_rx (.clk(clk), .uart_rx_pin(uart_rx), .data_out(rx_data), .byte_ready(rx_ready));

    wire [15:0] live_kp, live_ki, live_kd;
    wire [7:0] live_base_speed, live_max_speed;
    
    pid_parser live_tune (
        .clk(clk), .rst(rst), .byte_ready(rx_ready), .data_in(rx_data),
        .reg_p(live_kp), .reg_i(live_ki), .reg_d(live_kd),
        .reg_b(live_base_speed), .reg_m(live_max_speed)
    );

    wire steer_ready; wire signed [15:0] steering_correction;
    pid pid_inst (
        .clk(clk), .rst(rst), .pos_ready(pos_ready), .position(steering_position),
        .kp(live_kp), .kd(live_kd), .steering_correction(steering_correction), .steer_ready(steer_ready)
    );

    // ==========================================
    // 5. MOTOR MIXER & PHYSICAL DRIVER
    // ==========================================
    wire [7:0] speed_a, speed_b; wire [1:0] dir_a, dir_b;

    apply_pid #(
        .SHIFT(3'd6)
    ) apply_inst (
        .clk(clk), .rst(rst), .steer_ready(steer_ready), .steering_correction(steering_correction),
        .base_speed(live_base_speed), .max_speed(live_max_speed),
        .speed_a(speed_a), .speed_b(speed_b), .dir_a(dir_a), .dir_b(dir_b)
    );

    driver #(
        .PRESCALER(8'd10) 
    ) physical_motors (
        .clk(clk), .rst(rst),
        .speed_a(speed_a), .speed_b(speed_b),
        .dir_a(dir_a), .dir_b(dir_b),
        .pwma(pwma), .ain1(ain1), .ain2(ain2),
        .pwmb(pwmb), .bin1(bin1), .bin2(bin2)
    );

    // ==========================================
    // 6. UART TELEMETRY (Printing to PC)
    // ==========================================
    reg [21:0] sample_timer = 0; reg trigger_print = 0;
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

    reg uart_transmit; reg [7:0] uart_data; wire uart_busy;
    uart_tx my_uart (.clk(clk), .data_in(uart_data), .transmit(uart_transmit), .uart_tx_pin(uart_tx), .tx_busy(uart_busy));

    reg [4:0] state = 0; 
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
                0: begin uart_transmit <= 0; if (trigger_print) begin captured_val <= test_signal; state <= 1; end end
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