`timescale 1ns/1ps

module test();

    reg clk;
    reg rst;
    reg [7:0] duty;
    wire pwm_out;

    // Instantiate the PWM Generator
    // We override the PRESCALER to 2 so the simulation runs much faster!
    pwm #(
        .PRESCALER(8'd10) 
    ) uut (
        .clk(clk),
        .rst(rst),
        .duty(duty),
        .pwm_out(pwm_out)
    );

    // Generate 27 MHz clock (~37ns period)
    always #18.5 clk = ~clk;

    initial begin
        // Output the waveform file for viewing in GTKWave
        $dumpfile("pwm.vcd");
        $dumpvars(0, test);

        // 1. Initialize
        clk = 0;
        rst = 1;
        duty = 8'd0;

        #100;
        rst = 0;

        // 2. Test 0% Duty Cycle
        $display("Testing 0%% Duty Cycle...");
        duty = 8'd0;
        #20000; 

        // 3. Test 25% Duty Cycle
        $display("Testing 25%% Duty Cycle (64/255)...");
        duty = 8'd64;
        #400000; 

        // 4. Test 50% Duty Cycle
        $display("Testing 50%% Duty Cycle (128/255)...");
        duty = 8'd128;
        #400000; 

        // 5. Test 100% Duty Cycle
        $display("Testing 100%% Duty Cycle (255/255)...");
        duty = 8'd255;
        #400000; 

        $display("Simulation Complete!");
        $finish;
    end

endmodule