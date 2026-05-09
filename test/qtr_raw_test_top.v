module qtr_raw_test_top (
    input wire clk,
    input wire btn1,              // Physical reset button
    inout wire [7:0] s, // The 8 QTR pins
    output wire uart_tx       // To your computer
);

    wire rst = ~btn1;

    // --- 1. RUN THE RAW READER ---
    wire raw_ready;
    wire [127:0] raw_vals;
    
    qtr_raw_reader reader_inst (
        .clk(clk),
        .rst(rst),
        .start(1'b1), // Hardwired to 1 so it scans continuously
        .sensor_pins(s),
        .sensor_values(raw_vals),
        .data_ready(raw_ready)
    );

    // Grab Sensor 0 to test (the first 16 bits)
    wire [15:0] test_signal = raw_vals[15:0]; 

    // --- 2. 10Hz (100ms) PRINT TIMER ---
    reg [21:0] sample_timer = 0;
    reg trigger_print = 0;

    always @(posedge clk) begin
        if (rst) begin
            sample_timer <= 0;
            trigger_print <= 0;
        end else begin
            // 27,000,000 clock ticks / 10 = 2,700,000
            if (sample_timer >= 22'd2_700_000) begin
                sample_timer <= 0;
                trigger_print <= 1; // Time to print!
            end else begin
                sample_timer <= sample_timer + 1;
                trigger_print <= 0;
            end
        end
    end

    // --- 3. UART TRANSMITTER ---
    reg uart_transmit;
    reg [7:0] uart_data;
    wire uart_busy;

    // Instantiate your exact UART TX module
    uart_tx my_uart (
        .clk(clk),
        .data_in(uart_data),
        .transmit(uart_transmit),
        .uart_tx_pin(uart_tx),
        .tx_busy(uart_busy)
    );

    // --- 4. PRINT HEX TO SCREEN ---
    reg [3:0] state = 0;
    reg [15:0] captured_val;
    reg [3:0] nibble;
    reg [7:0] ascii_char;

    // Convert 4-bit hex number to ASCII character
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
                        nibble <= test_signal[15:12]; // PRE-LOAD the first nibble here
                        state <= 1;
                    end
                end

                // Print Char 1 (Highest 4 bits)
                1: if (!uart_busy && !uart_transmit) begin
                    uart_data <= ascii_char; // ascii_char is now valid!
                    uart_transmit <= 1;
                    nibble <= captured_val[11:8]; // PRE-LOAD Char 2
                    state <= 2;
                end
                2: begin uart_transmit <= 0;
                    if (!uart_busy) state <= 3; end

                // Print Char 2
                3: if (!uart_busy && !uart_transmit) begin
                    uart_data <= ascii_char; 
                    uart_transmit <= 1;
                    nibble <= captured_val[7:4]; // PRE-LOAD Char 3
                    state <= 4;
                end
                4: begin uart_transmit <= 0;
                    if (!uart_busy) state <= 5; end

                // Print Char 3
                5: if (!uart_busy && !uart_transmit) begin
                    uart_data <= ascii_char;
                    uart_transmit <= 1;
                    nibble <= captured_val[3:0]; // PRE-LOAD Char 4
                    state <= 6;
                end
                6: begin uart_transmit <= 0;
                    if (!uart_busy) state <= 7; end

                // Print Char 4 (Lowest 4 bits)
                7: if (!uart_busy && !uart_transmit) begin
                    uart_data <= ascii_char; 
                    uart_transmit <= 1;
                    state <= 8;
                end
                8: begin uart_transmit <= 0;
                    if (!uart_busy) state <= 9; end

                // Print Carriage Return (\r)
                9: if (!uart_busy && !uart_transmit) begin
                    uart_data <= 8'h0D;
                    uart_transmit <= 1;
                    state <= 10;
                end
                10: begin uart_transmit <= 0;
                    if (!uart_busy) state <= 11; end

                // Print New Line (\n)
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