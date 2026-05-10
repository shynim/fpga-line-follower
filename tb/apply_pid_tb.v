`timescale 1ns / 1ps

module test;

    reg clk;
    reg rst;
    reg steer_ready;
    reg signed [15:0] steering_correction;
    
    // NEW: Dynamic speed controls for the testbench!
    reg [7:0] base_speed;
    reg [7:0] max_speed;

    wire [7:0] speed_a;
    wire [7:0] speed_b;
    wire [1:0] dir_a;
    wire [1:0] dir_b;

    // Instantiate the Mixer (BASE_SPEED parameter removed!)
    apply_pid #(
        .SHIFT(3'd6)
    ) uut (
        .clk(clk),
        .rst(rst),
        .steer_ready(steer_ready),
        .steering_correction(steering_correction),
        
        .base_speed(base_speed), // Plug in live base speed
        .max_speed(max_speed),   // Plug in live max speed
        
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
        
        // Initialize our dynamic speeds
        base_speed = 8'd100;
        max_speed = 8'd255;

        // Hold reset
        #100;
        rst = 0;
        #20;

        $display("--- Starting Motor Mixer Test (Dynamic Speeds) ---");
        $display("Initial Base Speed = 100 | Initial Max Speed = 255");
        $display("Dir Legend: 00=Stop, 01=Fwd");
        $display("---------------------------------------------------------");

        // TEST 1: Driving Straight
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

        // TEST 4: Hard Right Turn (One wheel stops!)
        // Steer: +12800 (12800 / 64 = 200).
        // Left math: 100 + 200 = 300 (Clamps to max_speed 255!)
        // Right math: 100 - 200 = -100 (Clamps to 0 Stop!)
        // Expected: Left 255 (Fwd 01), Right 0 (Stop 00)
        send_steer(16'sd12800);

        // TEST 5: Extreme Left Turn (Both wheels maxed/stopped!)
        // Steer: -32000 (-32000 / 64 = -500).
        // Left math: 100 - 500 = -400 (Clamps to 0 Stop!)
        // Right math: 100 + 500 = 600 (Clamps to max_speed 255!)
        // Expected: Left 0 (Stop 00), Right 255 (Fwd 01)
        send_steer(-16'sd32000);

        $display("---------------------------------------------------------");
        $display("--- Testing Live Dynamic Speed Changes! ---");
        
        // TEST 6: Change the Max Speed limit live!
        // We will do the exact same math as Test 4, but with a lower max limit.
        @(posedge clk);
        #1;
        max_speed = 8'd150; 
        
        $display("Max Speed dynamically lowered to 150!");
        
        // Steer: +12800 (12800 / 64 = 200).
        // Left math: 100 + 200 = 300 (Clamps to the NEW max_speed 150!)
        // Right math: 100 - 200 = -100 (Clamps to 0 Stop!)
        // Expected: Left 150 (Fwd 01), Right 0 (Stop 00)
        send_steer(16'sd12800);

        $display("---------------------------------------------------------");
        $display("--- Motor Mixer Test Finished ---");
        $finish;
    end
endmodule