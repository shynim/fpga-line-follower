`timescale 1ns / 1ps

module test();

    reg clk;
    reg rst;
    reg data_ready;
    reg [127:0] raw_values;
    reg [127:0] min_values;
    reg [127:0] max_values;

    wire [127:0] normalized_values;
    wire norm_ready;

    // Instantiate Normalizer
    normalizer uut (
        .clk(clk),
        .rst(rst),
        .data_ready(data_ready),
        .raw_values(raw_values),
        .min_values(min_values),
        .max_values(max_values),
        .normalized_values(normalized_values),
        .norm_ready(norm_ready)
    );

    // Generate 27 MHz clock
    always #18.5 clk = ~clk;

    integer i;

    initial begin
        $dumpfile("waveform_normalizer.vcd");
        $dumpvars(0, test);

        clk = 0;
        rst = 1;
        data_ready = 0;
        raw_values = 0;
        min_values = 0;
        max_values = 0;

        // Mock Calibration Values (Min = 500, Max = 2500)
        for (i = 0; i < 8; i = i + 1) begin
            min_values[i*16 +: 16] = 16'd500;
            max_values[i*16 +: 16] = 16'd2500;
        end

        #100 rst = 0;
        #100;

        // Load specific raw values to test the math logic
        raw_values[0*16 +: 16] = 16'd500;  // Equal to Min (Expect: 0)
        raw_values[1*16 +: 16] = 16'd1500; // Exactly middle (Expect: 500)
        raw_values[2*16 +: 16] = 16'd2500; // Equal to Max (Expect: 1000)
        raw_values[3*16 +: 16] = 16'd3000; // Above Max (Expect: clamped 1000)
        raw_values[4*16 +: 16] = 16'd100;  // Below Min (Expect: clamped 0)
        
        // Trigger the math engine!
        $display("Sending data to Normalizer...");
        data_ready = 1;
        #37;
        data_ready = 0;

        // Wait until the normalizer finishes all 8 divisions
        wait(norm_ready == 1'b1);
        
        $display("===========================================");
        $display("         NORMALIZATION COMPLETE            ");
        $display("===========================================");
        $display("Sensor 0 (Raw 500)   -> Output: %d (Expected: 0)", normalized_values[0*16 +: 16]);
        $display("Sensor 1 (Raw 1500)  -> Output: %d (Expected: 500)", normalized_values[1*16 +: 16]);
        $display("Sensor 2 (Raw 2500)  -> Output: %d (Expected: 1000)", normalized_values[2*16 +: 16]);
        $display("Sensor 3 (Raw 3000)  -> Output: %d (Expected: 1000)", normalized_values[3*16 +: 16]);
        $display("Sensor 4 (Raw 100)   -> Output: %d (Expected: 0)", normalized_values[4*16 +: 16]);
        $display("===========================================");

        #500 $finish;
    end
endmodule