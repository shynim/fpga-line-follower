`timescale 1ns / 1ps

module test;

    reg clk;
    reg rst;
    reg pos_ready;
    reg [15:0] position;
    reg [7:0] kp;
    reg [7:0] kd;

    wire signed [15:0] steering_correction;
    wire steer_ready;

    // Instantiate your PID Controller
    pid uut (
        .clk(clk),
        .rst(rst),
        .pos_ready(pos_ready),
        .position(position),
        .kp(kp),
        .kd(kd),
        .steering_correction(steering_correction),
        .steer_ready(steer_ready)
    );

    // 50 MHz Clock generation
    always #10 clk = ~clk;

    // A helper task to simulate the position module sending a new pulse
    task send_position(input [15:0] new_pos);
        begin
            @(posedge clk);
            #1; // PRO TIP: Always delay testbench assignments by 1 tick to prevent race conditions!
            position = new_pos;
            pos_ready = 1;
            
            @(posedge clk);
            #1;
            pos_ready = 0; // Turn off pulse
            
            // Wait specifically for the RISING EDGE of the new calculation pulse
            @(posedge steer_ready);
            
            $display("Time: %0t | Pos: %0d | Error: %0d | Steer Output: %0d", 
                     $time, position, $signed({1'b0, position}) - 3500, steering_correction);
        end
    endtask

    initial begin
        // Setup for GTKWave
        $dumpfile("pid_test.vcd");
        $dumpvars(0, test);

        // Initialize Inputs
        clk = 0;
        rst = 1;
        pos_ready = 0;
        position = 3500;
        
        // Let's test with Kp = 2, Kd = 5
        kp = 8'd2; 
        kd = 8'd5; 

        // Hold reset for 100ns
        #100;
        rst = 0;
        #20;

        $display("--- Starting PID Math Test ---");
        $display("Tuning: Kp = %0d, Kd = %0d", kp, kd);
        $display("---------------------------------------------------------");

        // TEST 1: Perfect Center
        // Error = 0. P = 0, D = 0
        // Expected Steer = 0
        send_position(3500);
        
        // TEST 2: Drifting Right
        // Error = 100. (Prev = 0). 
        // P = 100*2 = 200. D = (100 - 0)*5 = 500. 
        // Expected Steer = 700
        send_position(3600);

        // TEST 3: Still Drifting Right (Steering hasn't kicked in yet)
        // Error = 100. (Prev = 100).
        // P = 100*2 = 200. D = (100 - 100)*5 = 0. 
        // Expected Steer = 200 (Notice how the D-term dropped off!)
        send_position(3600);

        // TEST 4: The robot corrects! Moving back to center
        // Error = 50. (Prev = 100).
        // P = 50*2 = 100. D = (50 - 100)*5 = -250. 
        // Expected Steer = -150
        send_position(3550);

        // TEST 5: Hard Left turn! (Line moved way left)
        // Error = -1500. (Prev = 50).
        // P = -1500*2 = -3000. D = (-1500 - 50)*5 = -7750. 
        // Expected Steer = -10750
        send_position(2000);

        // TEST 6: Snapped perfectly back to center
        // Error = 0. (Prev = -1500).
        // P = 0*2 = 0. D = (0 - -1500)*5 = 7500. 
        // Expected Steer = 7500
        send_position(3500);

        $display("---------------------------------------------------------");
        $display("--- PID Test Finished ---");
        $finish;
    end
endmodule