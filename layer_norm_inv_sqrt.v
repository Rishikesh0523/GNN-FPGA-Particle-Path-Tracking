module layer_norm_inv_sqrt #(
    parameter VAR_BITS      = 45,
    parameter VAR_FRAC_BITS = 15,
    parameter LUT_BITS      = 5,        // 2^5=32 entries allocated in memory
    parameter LUT_SIZE      = 20,       // only 20 entries populated by generator
    parameter OUT_BITS      = 16,
    parameter OUT_FRAC_BITS = 11,       // Q5.11
    parameter real VAR_MIN_REAL = 0.01,
    parameter real VAR_MAX_REAL = 1024.0
)(
    input  clk,
    input  rstn,
    input  valid_in,
    input  [VAR_BITS-1:0] variance_in,

    output reg valid_out,
    output reg [OUT_BITS-1:0] inv_sqrt_out
);

    reg [OUT_BITS-1:0] lut [0:(1<<LUT_BITS)-1];

    initial begin
        $readmemb("inv_sqrt_lut.mem", lut);
    end

    localparam IDLE = 2'd0;
    localparam ADDR = 2'd1;
    localparam LUTR = 2'd2;
    localparam OUT  = 2'd3;

    reg [1:0]          state;
    reg [LUT_BITS-1:0] addr;
    localparam [VAR_BITS-1:0] THR_0  = 32'h00004B2C;  // 0.018353
localparam [VAR_BITS-1:0] THR_1  = 32'h000089F6;  // 0.033682
localparam [VAR_BITS-1:0] THR_2  = 32'h0000FD33;  // 0.061816
localparam [VAR_BITS-1:0] THR_3  = 32'h0001D0B0;  // 0.113449
localparam [VAR_BITS-1:0] THR_4  = 32'h000354D3;  // 0.208209
localparam [VAR_BITS-1:0] THR_5  = 32'h00061D2A;  // 0.382120
localparam [VAR_BITS-1:0] THR_6  = 32'h000B3880;  // 0.701294
localparam [VAR_BITS-1:0] THR_7  = 32'h001497D0;  // 1.287064
localparam [VAR_BITS-1:0] THR_8  = 32'h0025CB33;  // 2.362109
localparam [VAR_BITS-1:0] THR_9  = 32'h00455C9B;  // 4.335109
localparam [VAR_BITS-1:0] THR_10 = 32'h007F4C2B;  // 7.956095
localparam [VAR_BITS-1:0] THR_11 = 32'h00E9A017;  // 14.601584
localparam [VAR_BITS-1:0] THR_12 = 32'h01ACC400;  // 26.797851
localparam [VAR_BITS-1:0] THR_13 = 32'h0312E697;  // 49.181296
localparam [VAR_BITS-1:0] THR_14 = 32'h05A42CE8;  // 90.260964
localparam [VAR_BITS-1:0] THR_15 = 32'h0A5A73B7;  // 165.653251
localparam [VAR_BITS-1:0] THR_16 = 32'h13004BA1;  // 304.018465
localparam [VAR_BITS-1:0] THR_17 = 32'h22DF4BD0;  // 557.956009
localparam [VAR_BITS-1:0] THR_18 = 32'h40000000;  // 1024.000000

function [LUT_BITS-1:0] variance_to_lut_addr;
    input [VAR_BITS-1:0] var_in;
    begin
        if      (var_in <= THR_0 ) variance_to_lut_addr = 0;
        else if (var_in <= THR_1 ) variance_to_lut_addr = 1;
        else if (var_in <= THR_2 ) variance_to_lut_addr = 2;
        else if (var_in <= THR_3 ) variance_to_lut_addr = 3;
        else if (var_in <= THR_4 ) variance_to_lut_addr = 4;
        else if (var_in <= THR_5 ) variance_to_lut_addr = 5;
        else if (var_in <= THR_6 ) variance_to_lut_addr = 6;
        else if (var_in <= THR_7 ) variance_to_lut_addr = 7;
        else if (var_in <= THR_8 ) variance_to_lut_addr = 8;
        else if (var_in <= THR_9 ) variance_to_lut_addr = 9;
        else if (var_in <= THR_10) variance_to_lut_addr = 10;
        else if (var_in <= THR_11) variance_to_lut_addr = 11;
        else if (var_in <= THR_12) variance_to_lut_addr = 12;
        else if (var_in <= THR_13) variance_to_lut_addr = 13;
        else if (var_in <= THR_14) variance_to_lut_addr = 14;
        else if (var_in <= THR_15) variance_to_lut_addr = 15;
        else if (var_in <= THR_16) variance_to_lut_addr = 16;
        else if (var_in <= THR_17) variance_to_lut_addr = 17;
        else if (var_in <= THR_18) variance_to_lut_addr = 18;
        else                       variance_to_lut_addr = 19;
    end
endfunction

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state        <= IDLE;
            valid_out    <= 0;
            inv_sqrt_out <= 0;
            addr         <= 0;
        end else begin
            case (state)
                IDLE: begin
                    valid_out <= 0;
                    if (valid_in)
                        state <= ADDR;
                end

                ADDR: begin
                    addr  <= variance_to_lut_addr(variance_in);
                    state <= LUTR;
                end

                LUTR: begin
                    inv_sqrt_out <= lut[addr];
                    state        <= OUT;
                end

                OUT: begin
                    valid_out <= 1;
                    state     <= IDLE;
                end
            endcase
        end
    end

endmodule