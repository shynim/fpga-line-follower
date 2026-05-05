`timescale 1ns / 1ps

module test();

    reg clk;
    reg rst;
    reg norm_ready;
    reg [127:0] normalized_values;

    wire [15:0] position;
    wire pos_ready;

    // Instantiate the Position Calculator
    position uut (
        .clk(clk),
        .rst(rst),
        .norm_ready(norm_ready),
        .normalized_values(normalized_values),
        .position(position),
        .pos_ready(pos_ready)
    );

    // Generate 27 MHz clock
    always #18.5 clk = ~clk;

    // Helper task to easily load sensor values
    task load_sensors(
        input [15:0] s0, input [15:0] s1, input [15:0] s2, input [15:0] s3,
        input [15:0] s4, input [15:0] s5, input [15:0] s6, input [15:0] s7
    );
        begin
            normalized_values[0*16  +: 16] = s0;
            normalized_values[1*16  +: 16] = s1;
            normalized_values[2*16  +: 16] = s2;
            normalized_values[3*16  +: 16] = s3;
            normalized_values[4*16  +: 16] = s4;
            normalized_values[5*16  +: 16] = s5;
            normalized_values[6*16  +: 16] = s6;
            normalized_values[7*16  +: 16] = s7;
            
            // BULLETPROOF SYNCHRONIZATION:
            // Wait for the exact clock edge before pulling the trigger
            @(posedge clk);
            norm_ready = 1;
            
            // Hold the trigger for exactly 1 clock cycle
            @(posedge clk);
            norm_ready = 0;
            
            // Wait for the FPGA to safely finish the math
            wait(pos_ready == 1'b1);
            
            // Give the testbench one clock cycle to catch its breath before printing
            @(posedge clk); 
        end
    endtask

    initial begin
        $dumpfile("waveform_position.vcd");
        $dumpvars(0, test);

        // Initialize
        clk = 0;
        rst = 1;
        norm_ready = 0;
        normalized_values = 128'd0;

        #100 rst = 0;
        #100;

        $display("===========================================");
        $display("     TESTING POSITION CALCULATOR           ");
        $display("===========================================");

        // Test 1: Dead Center (Sensors 3 and 4 equally see the line)
        load_sensors(0, 0, 0, 1000, 1000, 0, 0, 0);
        $display("Test 1 (Center)     -> Pos: %d (Expected: 3500)", position);

        // Test 2: Hard Left (Only Sensor 0 sees the line)
        load_sensors(1000, 0, 0, 0, 0, 0, 0, 0);
        $display("Test 2 (Hard Left)  -> Pos: %d (Expected: 0)", position);

        // Test 3: Hard Right (Only Sensor 7 sees the line)
        load_sensors(0, 0, 0, 0, 0, 0, 0, 1000);
        $display("Test 3 (Hard Right) -> Pos: %d (Expected: 7000)", position);

        // Test 4: Off-Center Right (Sensor 4 max, Sensor 5 half)
        // Math: (1000*4000 + 500*5000) / 1500 = 6500000 / 1500 = 4333
        load_sensors(0, 0, 0, 0, 1000, 500, 0, 0);
        $display("Test 4 (Off-Center) -> Pos: %d (Expected: ~4333)", position);

        // Test 5: LOST THE LINE! (Robot drove off the track)
        // Since Test 4 left the line on the right side (>3500), it should output 7000
        load_sensors(0, 0, 0, 0, 0, 0, 0, 0);
        $display("Test 5 (Lost Line)  -> Pos: %d (Expected: 7000 - Snapped Right!)", position);

        $display("===========================================");
        #500 $finish;
    end
endmodule