`default_nettype none

module driver #(
    // We add the parameter here so the testbench can pass it down!
    parameter PRESCALER = 8'd10 
)(
    input wire clk,
    input wire rst,
    
    input wire [7:0] speed_a, 
    input wire [7:0] speed_b, 
    input wire [1:0] dir_a,   // 00:Stop, 01:Fwd, 10:Rev
    input wire [1:0] dir_b,   // 00:Stop, 01:Fwd, 10:Rev
    
    output wire pwma,
    output wire ain1,
    output wire ain2,
    output wire pwmb,
    output wire bin1,
    output wire bin2
);

    assign ain1 = dir_a[0];
    assign ain2 = dir_a[1];
    
    assign bin1 = dir_b[0];
    assign bin2 = dir_b[1];

    // Left Motor PWM (Updated name to "pwm")
    pwm #(
        .PRESCALER(PRESCALER) 
    ) pwm_left (
        .clk(clk),
        .rst(rst),
        .duty(speed_a),
        .pwm_out(pwma)
    );

    // Right Motor PWM (Updated name to "pwm")
    pwm #(
        .PRESCALER(PRESCALER) 
    ) pwm_right (
        .clk(clk),
        .rst(rst),
        .duty(speed_b),
        .pwm_out(pwmb)
    );

endmodule