// Auto-generated stub for MP_Edge_Layer_B1_L1
module MP_Edge_Layer_B1_L1
#(
    parameter DATA_BITS   = 8,
    parameter WEIGHT_BITS = 8
)
(
    input clk,
    input rstn,
    input start,
    input [DATA_BITS*32-1:0] feature_in,
    output reg done,
    output reg [DATA_BITS*32-1:0] feature_out
);
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            done <= 1'b0;
            feature_out <= {DATA_BITS*32{1'b0}};
        end
    end
endmodule
