`timescale 1ns / 1ps

module counter_with_enable #(
    parameter END_COUNTER = 192
)(
    input clk,
    input rstn,
    input enable,
    output reg [31:0] counter_out,  // reg type output
    output reg counter_donestatus   // reg type output
);
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            counter_out <= 0;
            counter_donestatus <= 0;
        end else if (enable) begin
            if (counter_out < END_COUNTER-1) begin
                counter_out <= counter_out + 1;
                counter_donestatus <= 0;
            end else begin
                counter_out <= 0;
                counter_donestatus <= 1;
            end
        end else begin
            counter_out <= 0;
            counter_donestatus <= 0;
        end
    end
    
endmodule