`timescale 1ns / 1ps

module counter #(parameter END_COUNTER = 32'd0)
(
    input clk,
    input rstn,
    output reg [31:0] counter_out
);

always @(posedge clk) begin
    if (!rstn)
        counter_out <= 32'd0;
    else if (counter_out < END_COUNTER+1)
        counter_out <= counter_out + 1'b1;
end

endmodule
