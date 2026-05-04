`timescale 1ns / 1ps

module test();

    // Inputs to the UUT (Unit Under Test)
    reg clk;
    reg rst;
    reg start;

    // Inout and Outputs
    wire [7:0] sensor_pins;
    wire [127:0] sensor_values;
    wire data_ready;

    // Variable to fake the analog capacitor discharge
    reg [7:0] tb_drive;
    
    // Connect our faked analog states to the physical pins
    assign sensor_pins = tb_drive;

    // Instantiate the Raw Reader
    qtr_raw_reader uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .sensor_pins(sensor_pins),
        .sensor_values(sensor_values),
        .data_ready(data_ready)
    );

    // Generate a 27 MHz clock (~37.037 ns period -> ~18.5 ns half-period)
    always #18.5 clk = ~clk;

    initial begin
        // 1. Initialize variables
        clk = 0;
        rst = 1;
        start = 0;
        tb_drive = 8'hZZ; // High-impedance so the UUT can drive the pins during charge

        // 2. Reset the module
        #100;
        rst = 0;
        #100;

        // 3. Trigger the start signal for one clock cycle
        start = 1;
        #37; 
        start = 0;

        // 4. Wait 11 microseconds for the UUT's charge phase to fully complete
        #11000;

        // 5. The UUT is now in MEASURE mode (pins are inputs). 
        // We simulate the capacitors holding their charge by forcing the lines HIGH.
        tb_drive = 8'hFF;

        // 6. Simulate the analog discharge times
        // A fork/join block runs all these timers simultaneously in parallel
        fork
            begin #100000;  tb_drive[0] = 1'b0; end // Sensor 0: Discharges in 100 us (Fast / White line)
            begin #500000;  tb_drive[1] = 1'b0; end // Sensor 1: Discharges in 500 us
            begin #1000000; tb_drive[2] = 1'b0; end // Sensor 2: Discharges in 1000 us
            begin #2000000; tb_drive[3] = 1'b0; end // Sensor 3: Discharges in 2000 us (Slow / Dark gray line)
            
            // Sensors 4, 5, 6, and 7 are deliberately left HIGH.
            // This tests the safety timeout feature (simulating a pure black line where the capacitor never discharges).
        join
    end

    // 7. Monitor the data_ready flag and print the results
    always @(posedge clk) begin
        if (data_ready) begin
            $display("===========================================");
            $display("         QTR SENSOR READ COMPLETE          ");
            $display("===========================================");
            // We expect the tick counts to roughly equal (Time in us * 27 ticks/us)
            $display("Sensor 0 (100 us): %d ticks", sensor_values[15:0]);
            $display("Sensor 1 (500 us): %d ticks", sensor_values[31:16]);
            $display("Sensor 2 (1000 us): %d ticks", sensor_values[47:32]);
            $display("Sensor 3 (2000 us): %d ticks", sensor_values[63:48]);
            $display("Sensor 4 (Timeout): %d ticks", sensor_values[79:64]);
            $display("Sensor 5 (Timeout): %d ticks", sensor_values[95:80]);
            $display("Sensor 6 (Timeout): %d ticks", sensor_values[111:96]);
            $display("Sensor 7 (Timeout): %d ticks", sensor_values[127:112]);
            $display("===========================================");
            
            // End the simulation
            $finish;
        end
    end

endmodule