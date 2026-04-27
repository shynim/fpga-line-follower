`default_nettype none

module uart_tx
#(
    parameter DELAY_FRAMES = 234 
)
(
    input wire clk,
    input wire [7:0] data_in,
    input wire transmit,         // Pulse high to start sending
    output reg uart_tx_pin = 1,  // UART line idles HIGH
    output reg tx_busy = 0       // High while actively transmitting
);

reg [3:0] txState = 0;
reg [12:0] txCounter = 0;
reg [2:0] txBitNumber = 0;
reg [7:0] data_reg = 0;

localparam TX_STATE_IDLE = 0;
localparam TX_STATE_START_BIT = 1;
localparam TX_STATE_WRITE = 2;
localparam TX_STATE_STOP_BIT = 3;

always @(posedge clk) begin
    case (txState)
        TX_STATE_IDLE: begin
            uart_tx_pin <= 1'b1; // Default idle state is HIGH
            txCounter <= 0;
            txBitNumber <= 0;
            
            if (transmit == 1'b1) begin
                tx_busy <= 1'b1;
                data_reg <= data_in; // Latch the data to prevent changes during transmission
                txState <= TX_STATE_START_BIT;
            end else begin
                tx_busy <= 1'b0;
            end
        end 

        TX_STATE_START_BIT: begin
            uart_tx_pin <= 1'b0; // Start bit is a LOW signal
            if ((txCounter + 1) == DELAY_FRAMES) begin
                txState <= TX_STATE_WRITE;
                txCounter <= 0;
            end else begin
                txCounter <= txCounter + 1;
            end
        end

        TX_STATE_WRITE: begin
            uart_tx_pin <= data_reg[txBitNumber]; // Send LSB first
            if ((txCounter + 1) == DELAY_FRAMES) begin
                txCounter <= 0;
                if (txBitNumber == 3'b111) begin // All 8 bits sent
                    txState <= TX_STATE_STOP_BIT;
                end else begin
                    txBitNumber <= txBitNumber + 1;
                end
            end else begin
                txCounter <= txCounter + 1;
            end
        end

        TX_STATE_STOP_BIT: begin
            uart_tx_pin <= 1'b1; // Stop bit is a HIGH signal
            if ((txCounter + 1) == DELAY_FRAMES) begin
                txState <= TX_STATE_IDLE;
                txCounter <= 0;
                tx_busy <= 1'b0;
            end else begin
                txCounter <= txCounter + 1;
            end
        end
        
        default: txState <= TX_STATE_IDLE;
    endcase
end

endmodule