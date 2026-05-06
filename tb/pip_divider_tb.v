`timescale 1ns/1ps

module test();

    parameter WIDTH = 32;
    reg clk;
    reg [WIDTH-1:0] dividend;
    reg [WIDTH-1:0] divisor;
    wire [WIDTH-1:0] quotient;
    wire [WIDTH-1:0] remainder;

    // Instantiate the Unit Under Test (UUT)
    pip_divider #(.WIDTH(WIDTH)) uut (
        .clk(clk),
        .dividend(dividend),
        .divisor(divisor),
        .quotient(quotient),
        .remainder(remainder)
    );

    // Generate 100MHz clock (10ns period)
    always #5 clk = ~clk;

    initial begin
        // Initialize signals
        clk = 0;
        dividend = 0;
        divisor = 0;

        // Wait for reset/stabilization
        #20;

        // --- TEST CASE 1: Simple Division ---
        // Let's do 1000 / 10
        // Expected Quotient: 100
        @(posedge clk);
        dividend = 32'd1000;
        divisor  = 32'd10;
        
        $display("Input: %d / %d. Waiting for pipeline...", dividend, divisor);
        
        // Wait exactly 32 cycles for the result to propagate through the pipeline
        repeat (32) @(posedge clk);
        
        #2; // Small offset to read after the clock edge
        $display("Result: Quotient = %d, Remainder = %d", quotient, remainder);
        if (quotient == 100 && remainder == 0) 
            $display("SUCCESS: 1000/10 = 100");
        else 
            $display("FAILURE: Expected 100, remainder 0");

        // --- TEST CASE 2: Large Numbers ---
        // Apply new inputs on the next clock edge
        @(posedge clk);
        dividend = 32'd67107840;
        divisor  = 32'd50000;
        
        $display("Input: %d / %d. Waiting for pipeline...", dividend, divisor);
        
        // Wait exactly 32 cycles for this result
        repeat (32) @(posedge clk);
        
        #2;
        $display("Result: Quotient = %d, Remainder = %d", quotient, remainder);
        if (quotient == 1342 && remainder == 7840) // 67107840 - (1342 * 50000) = 7840
            $display("SUCCESS: High precision math works!");
        else 
            $display("FAILURE: Expected quotient 1342, remainder 7840");

        // --- TEST CASE 3: Division by zero test ---
        @(posedge clk);
        dividend = 32'd100;
        divisor  = 32'd0;
        
        $display("Input: %d / %d. Testing division by zero...", dividend, divisor);
        
        repeat (32) @(posedge clk);
        
        #2;
        $display("Result: Quotient = %d, Remainder = %d", quotient, remainder);

        #100;
        $finish;
    end

    // Create a waveform file so you can SEE the pipeline stages in GTKWave
    initial begin
        $dumpfile("divider_test.vcd");
        $dumpvars(0, test);
    end

endmodule