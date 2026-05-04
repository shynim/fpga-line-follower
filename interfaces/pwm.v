`default_nettype none

module pwm #(
    // Prescaler of 10: 27 MHz / (10 * 256) = ~10.5 kHz PWM frequency
    parameter PRESCALER = 8'd10 
)(
    input wire clk,
    input wire rst,
    input wire [7:0] duty, // 0 = 0% speed, 255 = 100% speed
    output reg pwm_out
);

    reg [7:0] prescaler_counter = 0;
    reg [7:0] pwm_counter = 0;

    always @(posedge clk) begin
        if (rst) begin
            prescaler_counter <= 0;
            pwm_counter <= 0;
            pwm_out <= 0;
        end else begin
            
            // 1. Prescaler logic
            if (prescaler_counter < PRESCALER - 1) begin
                prescaler_counter <= prescaler_counter + 1;
            end else begin
                prescaler_counter <= 0;
                // 2. Main counter logic
                pwm_counter <= pwm_counter + 1; 
            end
            
            // 3. Duty cycle logic
            if (duty == 0) begin
                pwm_out <= 1'b0; 
            end else if (pwm_counter < duty) begin
                pwm_out <= 1'b1; 
            end else begin
                pwm_out <= 1'b0; 
            end
            
        end
    end
endmodule