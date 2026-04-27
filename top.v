`default_nettype none

module top
#(
    parameter DELAY_FRAMES = 234 
)
(
    input clk,
    input uart_rx,
    output uart_tx,
    output reg [5:0] led = 6'b111111, // Default all LEDs OFF
    input btn1
);

// 1. Wires from the Receiver
wire [7:0] rx_data;
wire rx_byte_ready;

// 2. Wires from the PID Parser
wire [7:0] p_value;
wire [7:0] i_value;
wire [7:0] d_value;

// 3. Wires and Registers for the Transmitter
wire tx_busy;
reg transmit_pulse = 0;
wire [7:0] data_to_send = "a"; // The character we want to send

// Registers for button debouncing / edge detection
reg btn_sync_1 = 0;
reg btn_sync_2 = 0;
reg btn_prev = 0;

uart_rx #(.DELAY_FRAMES(DELAY_FRAMES)) my_receiver (
    .clk(clk),
    .uart_rx_pin(uart_rx),
    .data_out(rx_data),
    .byte_ready(rx_byte_ready)
);

uart_tx #(.DELAY_FRAMES(DELAY_FRAMES)) my_transmitter (
    .clk(clk),
    .data_in(data_to_send),
    .transmit(transmit_pulse),
    .uart_tx_pin(uart_tx),      // Connects to the top-level output pin
    .tx_busy(tx_busy)
);

// pid_parser my_parser (
//     .clk(clk),
//     .byte_ready(rx_byte_ready), // Feed the RX ready signal in
//     .data_in(rx_data),          // Feed the RX data in
//     .reg_p(p_value),            // Output the parsed P value
//     .reg_i(i_value),            // Output the parsed I value
//     .reg_d(d_value)             // Output the parsed D value
// );


always @(posedge clk) begin
   
end

endmodule