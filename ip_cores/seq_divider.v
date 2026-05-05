module seq_divider (
    input wire clk,
    input wire rst,
    input wire start,           // Pulse high to start the calculation
    input wire [31:0] num,      // Numerator (The top number)
    input wire [31:0] den,      // Denominator (The bottom number)
    
    output reg [31:0] quotient, // The result of the division
    output reg [31:0] remainder,// The leftover part
    output reg ready            // Pulses high when math is finished
);

    // State Machine
    localparam IDLE   = 2'd0;
    localparam DIVIDE = 2'd1;
    localparam DONE   = 2'd2;

    reg [1:0] state = IDLE;
    
    reg [5:0] count;
    reg [63:0] divisor;
    reg [63:0] dividend;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            ready <= 0;
            quotient <= 0;
            remainder <= 0;
            count <= 0;
        end else begin
            case (state)
                IDLE: begin
                    ready <= 0;
                    if (start) begin
                        // Prevent dividing by zero (which would crash the math)
                        if (den == 0) begin
                            quotient <= 32'hFFFFFFFF; // Output max value on error
                            remainder <= 0;
                            ready <= 1; // Finish instantly
                        end else begin
                            // Setup the binary long division
                            // We use 64-bit registers to have room to shift the 32-bit numbers
                            dividend <= {32'd0, num};       // Numerator in lower half
                            divisor  <= {den, 32'd0};       // Denominator in upper half
                            count    <= 6'd32;              // We must shift 32 times
                            state    <= DIVIDE;
                        end
                    end
                end

                DIVIDE: begin
                    // Hardware Long Division Algorithm
                    if (count > 0) begin
                        // Shift the dividend left by 1. 
                        // If the upper half is now bigger than our divisor, we can subtract!
                        if ((dividend << 1) >= divisor) begin
                            // Subtract the divisor, and add 1 to the bottom bit (our quotient)
                            dividend <= (dividend << 1) - divisor + 1; 
                        end else begin
                            // Too small to subtract, just shift it
                            dividend <= (dividend << 1);               
                        end
                        count <= count - 1;
                    end else begin
                        state <= DONE;
                    end
                end

                DONE: begin
                    // The division is over! 
                    // The lower 32 bits mathematically become our answer.
                    // The upper 32 bits mathematically become the remainder.
                    quotient <= dividend[31:0];
                    remainder <= dividend[63:32];
                    ready <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule