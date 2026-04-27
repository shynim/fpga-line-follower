`timescale 1ns/1ps

module test();
  reg clk = 0;
  reg uart_rx = 1;
  wire uart_tx;
  wire [5:0] led;
  reg btn = 1;

  // Instantiate the motherboard
  top #(
    .DELAY_FRAMES(8) // Override the default 234 with 8 for fast simulation
  ) uut (
    .clk(clk),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx),
    .led(led),
    .btn1(btn)
  );

  // Generate the clock (Period = 2 time units)
  always #1 clk = ~clk;

  // ---------------------------------------------------------
  // TASK: Automatically send an 8-bit character over UART
  // ---------------------------------------------------------
  task send_char;
    input [7:0] char;
    integer i;
    begin
      uart_rx = 0; // Send Start Bit
      #16;         // Wait 1 bit period (8 frames * 2 time units)
      
      // Loop through all 8 data bits
      for (i = 0; i < 8; i = i + 1) begin
        uart_rx = char[i];
        #16;
      end
      
      uart_rx = 1; // Send Stop Bit
      #16;
    end
  endtask
  // ---------------------------------------------------------

  // Run the Simulation Sequence
  initial begin
    $display("Starting PID Parser Simulation...");
    #100; // Small delay before we start
    
    // 1. Simulate typing "p128" and pressing Enter
    $display("Sending p128...");
    send_char("p");
    send_char("1");
    send_char(10); // ASCII 10 is the Newline/Enter key
    
    #100; // Pause for a moment

    // 2. Simulate typing "i50" and pressing Enter
    $display("Sending i50...");
    send_char("i");
    send_char("5");
    send_char("0");
    send_char(10);

    #100;

    // 3. Simulate typing "d9" and pressing Enter
    $display("Sending d9...");
    send_char("d");
    send_char("9");
    send_char(10);

    #200;
    $display("Simulation Complete.");
    $finish;
  end

  // Dump the waveform data
  initial begin
    $dumpfile("uart.vcd");
    $dumpvars(0, test); // The '0' means dump EVERYTHING, including sub-modules!
  end
endmodule