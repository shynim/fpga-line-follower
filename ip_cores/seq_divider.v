module seq_divider #(
    parameter WIDTH = 32 // Default to 32 bits, but easily overridable!
)(
    input wire clk,
    input wire rst,
    input wire start,           // Pulse high to start the calculation
    input wire [WIDTH-1:0] num, // Numerator
    input wire [WIDTH-1:0] den, // Denominator
    
    output reg [WIDTH-1:0] quotient, 
    output reg [WIDTH-1:0] remainder,
    output reg ready            // Pulses high when math is finished
);
    // State Machine
    localparam IDLE   = 2'd0;
    localparam DIVIDE = 2'd1;
    localparam DONE   = 2'd2;

    reg [1:0] state = IDLE;
    
    // A 6-bit counter safely supports division up to 63-bits wide
    reg [5:0] count; 
    
    // Internal shift registers must be exactly double the width
    reg [(WIDTH*2)-1:0] divisor;
    reg [(WIDTH*2)-1:0] dividend;

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
                        if (den == 0) begin
                            // Output max value (all 1s) on divide-by-zero error
                            quotient <= {WIDTH{1'b1}}; 
                            remainder <= 0;
                            ready <= 1; 
                        end else begin
                            // Setup the binary long division
                            // Pad the upper half with zeros, and load the numerator in the lower half
                            dividend <= { {WIDTH{1'b0}}, num }; 
                            
                            // Load the denominator in the upper half, pad lower with zeros
                            divisor  <= { den, {WIDTH{1'b0}} }; 
                            
                            count    <= WIDTH[5:0]; // Shift exactly 'WIDTH' times
                            state    <= DIVIDE;
                        end
                    end
                end

                DIVIDE: begin
                    // Hardware Long Division Algorithm
                    if (count > 0) begin
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
                    // The lower half mathematically becomes our answer
                    quotient <= dividend[WIDTH-1:0];
                    
                    // The upper half mathematically becomes the remainder
                    remainder <= dividend[(WIDTH*2)-1:WIDTH];
                    
                    ready <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule