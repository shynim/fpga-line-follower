`default_nettype none

module motor_test_top (
    input wire clk,    // 27 MHz clock from the Tang Nano
    input wire btn1,       // <--- Updated to match your CST file
    
    // Hardware pins to the motor driver
    output wire pwma, ain1, ain2,
    output wire pwmb, bin1, bin2,
    output wire stby,
    output wire [5:0] led // Add this line to define the 6 LEDs
);

    // The Tang Nano buttons are "active low" (0 when pressed). 
    // We invert it here so '1' means reset for our internal modules.
    wire rst = ~btn1; 

    // A 26-bit counter is large enough to hold 54,000,000 (2 seconds at 27 MHz)
    reg [25:0] timer = 0;
    reg [1:0] state = 0;

    localparam TWO_SECONDS = 26'd54_000_000;

    // 1. The State Machine Timer
    always @(posedge clk) begin
        if (rst) begin
            timer <= 0;
            state <= 0;
        end else begin
            if (timer < TWO_SECONDS - 1) begin
                timer <= timer + 1;
            end else begin
                timer <= 0;
                state <= state + 1; // Natural overflow from 3 back to 0
            end
        end
    end

    // 2. The Command Logic
    reg [7:0] speed_a, speed_b;
    reg [1:0] dir_a, dir_b;

    always @(*) begin
        case(state)
            2'd0: begin // FORWARD at 50%
                dir_a = 2'b01; dir_b = 2'b01;
                speed_a = 8'd128; speed_b = 8'd128; 
            end
            2'd1: begin // STOP
                dir_a = 2'b00; dir_b = 2'b00;
                speed_a = 8'd0; speed_b = 8'd0;
            end
            2'd2: begin // REVERSE at 50%
                dir_a = 2'b10; dir_b = 2'b10;
                speed_a = 8'd128; speed_b = 8'd128;
            end
            2'd3: begin // SPIN (Left Reverse, Right Forward)
                dir_a = 2'b10; dir_b = 2'b01;
                speed_a = 8'd128; speed_b = 8'd128;
            end
            default: begin
                dir_a = 2'b00; dir_b = 2'b00;
                speed_a = 8'd0; speed_b = 8'd0;
            end
        endcase
    end

    // 3. Instantiate the Motor Driver
    driver #(
        .PRESCALER(8'd10) // Real-world speed!
    ) driver (
        .clk(clk),
        .rst(rst),
        .speed_a(speed_a),
        .speed_b(speed_b),
        .dir_a(dir_a),
        .dir_b(dir_b),
        .pwma(pwma), .ain1(ain1), .ain2(ain2),
        .pwmb(pwmb), .bin1(bin1), .bin2(bin2),
        .stby(stby)
    );

    // Map the first LED to the lowest bit of the state counter
    assign led[0] = state[0]; 
    // Turn the others off (LEDs on Tang Nano are active-low, so 1 = OFF)
    assign led[5:1] = 5'b11111;

endmodule