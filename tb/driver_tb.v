`timescale 1ns/1ps

module test();

    reg clk;
    reg rst;
    reg [7:0] speed_a;
    reg [7:0] speed_b;
    reg [1:0] dir_a;
    reg [1:0] dir_b;

    wire pwma, ain1, ain2;
    wire pwmb, bin1, bin2;

    // Instantiate the motor driver, overriding the prescaler for fast simulation
    driver #(
        .PRESCALER(8'd2) 
    ) uut (
        .clk(clk),
        .rst(rst),
        .speed_a(speed_a),
        .speed_b(speed_b),
        .dir_a(dir_a),
        .dir_b(dir_b),
        .pwma(pwma),
        .ain1(ain1),
        .ain2(ain2),
        .pwmb(pwmb),
        .bin1(bin1),
        .bin2(bin2)
    );

    // 27 MHz clock
    always #18.5 clk = ~clk;

    initial begin
        $dumpfile("driver.vcd");
        $dumpvars(0, test);

        // Initialize everything to zero/stop
        clk = 0;
        rst = 1;
        speed_a = 0;
        speed_b = 0;
        dir_a = 2'b00;
        dir_b = 2'b00;

        #100 rst = 0;

        // 1. Drive Forward at 50% Speed
        $display("Testing: Forward at 50%%");
        dir_a = 2'b01;
        dir_b = 2'b01;
        speed_a = 8'd128;
        speed_b = 8'd128;
        #40000;

        // 2. Drive Reverse at 25% Speed
        $display("Testing: Reverse at 25%%");
        dir_a = 2'b10;
        dir_b = 2'b10;
        speed_a = 8'd64;
        speed_b = 8'd64;
        #40000;

        // 3. Spin Turn! (Left Motor Reverse, Right Motor Forward)
        $display("Testing: Spin Turn");
        dir_a = 2'b10;
        dir_b = 2'b01;
        speed_a = 8'd128;
        speed_b = 8'd128;
        #40000;

        // 4. Hard Stop
        $display("Testing: Stop");
        dir_a = 2'b00;
        dir_b = 2'b00;
        speed_a = 8'd0;
        speed_b = 8'd0;
        #20000;

        $display("Simulation Complete!");
        $finish;
    end

endmodule