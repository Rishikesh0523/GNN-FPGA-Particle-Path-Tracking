// ============================================================
// File: uram.v
// Description: Simple dual-port UltraRAM wrapper (URAM288)
// Target: UltraScale+ / Artix UltraScale+
// Data width: 72-bit
// Depth: 4096 (example)
// ============================================================

module uram #(
    parameter ADDR_WIDTH = 12,   // 2^12 = 4096 locations
    parameter DATA_WIDTH = 72
)(
    input  wire                    clk,

    // -------- Port A --------
    input  wire                    en_a,
    input  wire                    we_a,
    input  wire [ADDR_WIDTH-1:0]   addr_a,
    input  wire [DATA_WIDTH-1:0]   din_a,
    output wire [DATA_WIDTH-1:0]   dout_a,

    // -------- Port B --------
    input  wire                    en_b,
    input  wire                    we_b,
    input  wire [ADDR_WIDTH-1:0]   addr_b,
    input  wire [DATA_WIDTH-1:0]   din_b,
    output wire [DATA_WIDTH-1:0]   dout_b
);

    // Byte write enable (all bytes enabled)
    wire [8:0] bwe_a = we_a ? 9'h1FF : 9'h000;
    wire [8:0] bwe_b = we_b ? 9'h1FF : 9'h000;

    URAM288 #(
        .AUTO_SLEEP_LATENCY(8),
        .BWE_MODE_A("PARITY_INTERLEAVED"),
        .BWE_MODE_B("PARITY_INTERLEAVED"),
        .CASCADE_ORDER_A("NONE"),
        .CASCADE_ORDER_B("NONE"),
        .EN_ECC_RD_A("FALSE"),
        .EN_ECC_RD_B("FALSE"),
        .EN_ECC_WR_A("FALSE"),
        .EN_ECC_WR_B("FALSE"),
        .OREG_A("FALSE"),
        .OREG_B("FALSE"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC")
    ) uram_inst (

        // -------- Outputs --------
        .DOUT_A(dout_a),
        .DOUT_B(dout_b),
        .DBITERR_A(),
        .DBITERR_B(),
        .SBITERR_A(),
        .SBITERR_B(),
        .RDACCESS_A(),
        .RDACCESS_B(),

        // -------- Inputs --------
        .CLK(clk),

        .ADDR_A({11'd0, addr_a}),   // URAM expects 23-bit address
        .ADDR_B({11'd0, addr_b}),

        .DIN_A(din_a),
        .DIN_B(din_b),

        .BWE_A(bwe_a),
        .BWE_B(bwe_b),

        .EN_A(en_a),
        .EN_B(en_b),

        .RDB_WR_A(~we_a),   // 0 = write, 1 = read
        .RDB_WR_B(~we_b),

        .RST_A(1'b0),
        .RST_B(1'b0),

        .SLEEP(1'b0),

        // -------- Unused cascade / ECC ports --------
        .CAS_IN_ADDR_A(23'd0),
        .CAS_IN_ADDR_B(23'd0),
        .CAS_IN_BWE_A(9'd0),
        .CAS_IN_BWE_B(9'd0),
        .CAS_IN_DIN_A(72'd0),
        .CAS_IN_DIN_B(72'd0),
        .CAS_IN_DOUT_A(72'd0),
        .CAS_IN_DOUT_B(72'd0),
        .CAS_IN_EN_A(1'b0),
        .CAS_IN_EN_B(1'b0),
        .CAS_IN_RDB_WR_A(1'b0),
        .CAS_IN_RDB_WR_B(1'b0),
        .CAS_IN_RDACCESS_A(1'b0),
        .CAS_IN_RDACCESS_B(1'b0),
        .CAS_IN_SBITERR_A(1'b0),
        .CAS_IN_SBITERR_B(1'b0),
        .CAS_IN_DBITERR_A(1'b0),
        .CAS_IN_DBITERR_B(1'b0),

        .OREG_CE_A(1'b1),
        .OREG_CE_B(1'b1),
        .OREG_ECC_CE_A(1'b1),
        .OREG_ECC_CE_B(1'b1),

        .INJECT_SBITERR_A(1'b0),
        .INJECT_SBITERR_B(1'b0),
        .INJECT_DBITERR_A(1'b0),
        .INJECT_DBITERR_B(1'b0)
    );

endmodule
