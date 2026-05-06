module pip_divider #(
    parameter WIDTH = 32
)(
    input  wire clk,
    input  wire [WIDTH-1:0] dividend,
    input  wire [WIDTH-1:0] divisor,
    output wire [WIDTH-1:0] quotient,
    output wire [WIDTH-1:0] remainder
);

    // Pipelines to carry data through the stages
    reg [WIDTH-1:0] q_stage [0:WIDTH];
    reg [WIDTH-1:0] r_stage [0:WIDTH];
    reg [WIDTH-1:0] d_stage [0:WIDTH];
    reg [WIDTH-1:0] div_bits [0:WIDTH];

    // Stage 0: Initial Setup
    always @(posedge clk) begin
        q_stage[0]  <= 0;
        r_stage[0]  <= 0;
        d_stage[0]  <= divisor;
        div_bits[0] <= dividend;
    end

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : div_step
            // Pull the next bit from the dividend and append to current remainder
            wire [WIDTH-1:0] current_remainder = {r_stage[i][WIDTH-2:0], div_bits[i][WIDTH-1-i]};
            
            always @(posedge clk) begin
                d_stage[i+1]  <= d_stage[i];
                div_bits[i+1] <= div_bits[i];

                if (current_remainder >= d_stage[i]) begin
                    // It fits!
                    r_stage[i+1] <= current_remainder - d_stage[i];
                    q_stage[i+1] <= {q_stage[i][WIDTH-2:0], 1'b1};
                end else begin
                    // Too small
                    r_stage[i+1] <= current_remainder;
                    q_stage[i+1] <= {q_stage[i][WIDTH-2:0], 1'b0};
                end
            end
        end
    endgenerate

    assign quotient  = q_stage[WIDTH];
    assign remainder = r_stage[WIDTH];

endmodule