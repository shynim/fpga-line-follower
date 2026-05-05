module test_top (
    
    output wire stby        // Connect this to the STBY pin on the TB6612FNG
);

    assign stby = 1'b0; 

endmodule