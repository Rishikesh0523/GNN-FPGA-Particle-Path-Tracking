`timescale 1ns / 1ps
module register
#(
    parameter WIDTH = 8,
    parameter BITS = 32
)
(
    input [WIDTH*BITS-1:0] data_flat,
    input [31:0] counter,
    output reg [BITS-1:0] value
);

always @(*) begin
    if (counter >= 1 && counter <= WIDTH)
        value = data_flat[(counter-1)*BITS +: BITS];  // counter-1 for 0-indexed array
    else
        value = {BITS{1'b0}};
end

endmodule