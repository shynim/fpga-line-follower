`timescale 1ns / 1ps

module test;

    reg clk;
    reg rst;
    reg steer_ready;
    reg signed [15:0] steering_correction;

    wire [7:0] speed_a;
    wire [7:0] speed_b;
    wire [1:0] dir_a;
    wire [1:0] dir_b;

    // Instantiate the Mixer (Base Speed 100, Shift 6)
    apply_pid #(
        .BASE_SPEED(8'd100),
        .SHIFT(3'd6)
    ) uut (
        .clk(clk),
        .rst(rst),
        .steer_ready(steer_ready),
        .steering_correction(steering_correction),
        .speed_a(speed_a),
        .speed_b(speed_b),
        .dir_a(dir_a),
        .dir_b(dir_b)
    );

    // 50 MHz Clock generation
    always #10 clk = ~clk;

    // Helper task to send a steering command
    task send_steer(input signed [15:0] steer_val);
        begin
            @(posedge clk);
            #1; // Golden Rule: Delay assignment to prevent simulation race conditions!
            steering_correction = steer_val;
            steer_ready = 1;
            
            @(posedge clk);
            #1;
            steer_ready = 0;
            
            // Wait one clock cycle for the mixer to process the math
            @(posedge clk);
            #1;
            
            // Print the results cleanly
            $display("PID IN: %6d | L_SPD: %3d, L_DIR: %b | R_SPD: %3d, R_DIR: %b", 
                     steer_val, speed_a, dir_a, speed_b, dir_b);
        end
    endtask

    initial begin
        // Setup for GTKWave
        $dumpfile("mixer_test.vcd");
        $dumpvars(0, test);

        // Initialize Inputs
        clk = 0;
        rst = 1;
        steer_ready = 0;
        steering_correction = 0;

        // Hold reset
        #100;
        rst = 0;
        #20;

        $display("--- Starting Motor Mixer Test ---");
        $display("Base Speed = 100 | Shift = 6 (Divide by 64)");
        $display("Dir Legend: 00=Stop, 01=Fwd, 10=Rev");
        $display("---------------------------------------------------------");

        // TEST 1: Driving Straight
        // Steer: 0. 
        // Expected: Left 100 (Fwd), Right 100 (Fwd)
        send_steer(16'sd0);

        // TEST 2: Mild Right Turn
        // Steer: +1280 (1280 / 64 = 20).
        // Expected: Left 120 (Fwd), Right 80 (Fwd)
        send_steer(16'sd1280);

        // TEST 3: Mild Left Turn
        // Steer: -1280 (-1280 / 64 = -20).
        // Expected: Left 80 (Fwd), Right 120 (Fwd)
        send_steer(-16'sd1280);

        // TEST 4: Hard Right Turn (Drops a wheel into reverse!)
        // Steer: +12800 (12800 / 64 = 200).
        // Left math: 100 + 200 = 300 (Clamps to 255!)
        // Right math: 100 - 200 = -100 (Becomes +100 in Reverse!)
        // Expected: Left 255 (Fwd 01), Right 100 (Rev 10)
        send_steer(16'sd12800);

        // TEST 5: Extreme Left Turn (Both wheels maxed out!)
        // Steer: -32000 (-32000 / 64 = -500).
        // Left math: 100 - 500 = -400 (Clamps to 255 Reverse!)
        // Right math: 100 + 500 = 600 (Clamps to 255 Forward!)
        // Expected: Left 255 (Rev 10), Right 255 (Fwd 01)
        send_steer(-16'sd32000);

        $display("---------------------------------------------------------");
        $display("--- Motor Mixer Test Finished ---");
        $finish;
    end
endmodule