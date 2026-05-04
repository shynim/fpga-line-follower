`timescale 1ns / 1ps

module test();

    reg clk;
    reg rst;
    reg btn2;
    reg [15:0] calib_time_ms;
    reg data_ready;
    reg [127:0] sensor_values;

    wire [127:0] min_values;
    wire [127:0] max_values;
    wire is_calibrating;

    // Instantiate the module, but OVERRIDE the parameters for simulation speed!
    // 1 second becomes 500 ticks. 1 ms becomes 10 ticks.
    qtr_calibration #(
        .ONE_SECOND_TICKS(32'd500), 
        .TICKS_PER_MS(32'd10)
    ) uut (
        .clk(clk),
        .rst(rst),
        .btn2(btn2),
        .calib_time_ms(calib_time_ms),
        .data_ready(data_ready),
        .sensor_values(sensor_values),
        .min_values(min_values),
        .max_values(max_values),
        .is_calibrating(is_calibrating)
    );

    // Generate 27 MHz clock
    always #18.5 clk = ~clk;

    initial begin
        $dumpfile("waveform_calibration.vcd");
        $dumpvars(0, test);

        // 1. Initialize Default State
        clk = 0;
        rst = 1;
        btn2 = 0;
        data_ready = 0;
        sensor_values = 128'd0;
        
        // Let's set the calibration window to "50 milliseconds" (which is 500 ticks here)
        calib_time_ms = 16'd50; 

        #100 rst = 0;
        #100;

        // 2. Press the button!
        $display("Pressing btn2...");
        btn2 = 1;
        #100; 
        btn2 = 0;

        // 3. Wait for the LED to turn on (the 1-second delay)
        wait(is_calibrating == 1'b1);
        $display("LED ON: Calibration Started!");

        // 4. Fire Fake Data Packet #1 (Robot over a mostly white area)
        // Let's pretend all sensors read around 2000 ticks
        #200;
        sensor_values[15:0]   = 16'd2000; // Sensor 0
        sensor_values[31:16]  = 16'd2100; // Sensor 1
        sensor_values[47:32]  = 16'd1900; // Sensor 2
        // ... set the rest of the bus to a default 2000
        sensor_values[127:48] = {5{16'd2000}}; 
        
        // Pulse data_ready for 1 clock cycle to trigger the FSM
        data_ready = 1;
        #37; 
        data_ready = 0;

        // 5. Fire Fake Data Packet #2 (Robot swiped over the black line)
        // Sensor 1 sees black (high time), Sensor 2 sees bright white (low time)
        #200;
        sensor_values[15:0]  = 16'd2050; // Sensor 0 (stayed white)
        sensor_values[31:16] = 16'd60000; // Sensor 1 (hit pure black!)
        sensor_values[47:32] = 16'd500;   // Sensor 2 (hit pure white!)
        
        data_ready = 1;
        #37; 
        data_ready = 0;

        // 6. Wait for the LED to turn off automatically
        wait(is_calibrating == 1'b0);
        $display("LED OFF: Calibration Finished!");

        // 7. Verify the final memory states
        $display("===========================================");
        $display("Sensor 1 Final Min: %d (Expected: 2100)", min_values[31:16]);
        $display("Sensor 1 Final Max: %d (Expected: 60000)", max_values[31:16]);
        $display("-------------------------------------------");
        $display("Sensor 2 Final Min: %d (Expected: 500)", min_values[47:32]);
        $display("Sensor 2 Final Max: %d (Expected: 1900)", max_values[47:32]);
        $display("===========================================");

        #500 $finish;
    end
endmodule