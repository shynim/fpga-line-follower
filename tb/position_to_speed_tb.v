`timescale 1ns / 1ps

module test;

    // Inputs
    reg clk;
    reg rst;
    reg pos_ready;
    reg [15:0] position;
    
    // NEW: Dynamic Speed Registers for testing!
    reg [7:0] base_speed;
    reg [7:0] max_speed;
    
    // Fixed-Point Tuning (Kp=2.0, Kd=5.0)
    // Formula: Value * 16
    wire [15:0] kp = 16'd32; // 2.0 * 16
    wire [15:0] kd = 16'd80; // 5.0 * 16

    // Internal Wires (The "Nerves")
    wire signed [15:0] steer_out;
    wire steer_ready;
    wire [7:0] speed_a, speed_b;
    wire [1:0] dir_a, dir_b;

    // --- 1. INSTANTIATE PID ---
    pid pid_brain(
        .clk(clk), .rst(rst),
        .pos_ready(pos_ready),
        .position(position),
        .kp(kp), .kd(kd),
        .steering_correction(steer_out),
        .steer_ready(steer_ready)
    );

    // --- 2. INSTANTIATE MIXER ---
    // FIX: Removed BASE_SPEED parameter!
    apply_pid #(
        .SHIFT(3'd6) // Divide PID by 64
    ) spinal_cord (
        .clk(clk), .rst(rst),
        .steer_ready(steer_ready),
        .steering_correction(steer_out),
        
        // FIX: Plug in our live dynamic speeds!
        .base_speed(base_speed),
        .max_speed(max_speed),
        
        .speed_a(speed_a), .speed_b(speed_b),
        .dir_a(dir_a), .dir_b(dir_b)
    );

    // Clock Generation
    always #10 clk = ~clk;

    // Automated Task
    task check_system(
        input [8*20:1] label,
        input [15:0] test_pos,
        input [7:0] exp_sa, input [1:0] exp_da,
        input [7:0] exp_sb, input [1:0] exp_db
    );
        begin
            @(posedge clk); #1; // Add the #1 delay to prevent race conditions
            position = test_pos;
            pos_ready = 1;
            
            @(posedge clk); #1;
            pos_ready = 0;

            // 1. Wait for the exact moment the Brain finishes calculating
            @(posedge steer_ready); 
            
            // 2. Give the Spinal Cord (Mixer) exactly 2 clock cycles to process the math
            repeat(2) @(posedge clk); #1;

            $display("---------------------------------------------------------");
            $display("TEST: %s | POS: %d", label, test_pos);
            
            if (speed_a === exp_sa && dir_a === exp_da && speed_b === exp_sb && dir_b === exp_db)
                $display("RESULT: [PASS]");
            else
                $display("RESULT: [FAIL] !!!");

            $display("MOTOR A -> Expected: %d (Dir %b) | Actual: %d (Dir %b)", exp_sa, exp_da, speed_a, dir_a);
            $display("MOTOR B -> Expected: %d (Dir %b) | Actual: %d (Dir %b)", exp_sb, exp_db, speed_b, dir_b);
        end
    endtask

    initial begin
        clk = 0; rst = 1; pos_ready = 0;
        
        // Initialize our live speeds to standard defaults
        base_speed = 8'd100;
        max_speed = 8'd255;
        
        #100 rst = 0;

        $display("=========================================================");
        $display("      FULL SYSTEM CONTROL TEST (DYNAMIC SPEEDS)");
        $display("=========================================================");

        // 1. Perfect Center: Error 0 -> Both motors Base Speed (100)
        check_system("Center Line", 3500, 100, 2'b01, 100, 2'b01);

        // 2. Slight Right: Error +100. (Last Error was 0, so D-Term kicks in!)
        // Total Steer = 700. Mixer = 10.
        check_system("Slight Right", 3600, 110, 2'b01, 90, 2'b01);

        // 3. Hard Left: Error -3500. (Last Error was 100, Massive D-Term!)
        // Total Steer = -25000. Mixer = -391. 
        // L = 100 + (-391) = -291 -> Clamps to 0 (Stop 00)
        // R = 100 - (-391) = 491  -> Clamps to 255 (Fwd 01)
        check_system("Hard Left", 0, 0, 2'b00, 255, 2'b01);

        $display("=========================================================");
        $display("      TESTING LIVE SPEED ADJUSTMENT");
        $display("=========================================================");

        // Lower the max speed dynamically!
        @(posedge clk); #1;
        max_speed = 8'd150;
        $display(">>> LIVE UPDATE: Max Speed capped to 150! <<<");

        // 4. Hard Left (Repeated, but with new max limit)
        // Last error was -3500. Current is -3500. Diff = 0.
        // P = -3500 * 2 = -7000. D = 0. Total Steer = -7000. Mixer = -109.
        // L = 100 + (-109) = -9  -> Clamps to 0 (Stop 00)
        // R = 100 - (-109) = 209 -> NEW LOGIC: Clamps to 150 instead of 255!
        check_system("Hard Left Capped", 0, 0, 2'b00, 150, 2'b01);

        $display("=========================================================");
        $finish;
    end
endmodule