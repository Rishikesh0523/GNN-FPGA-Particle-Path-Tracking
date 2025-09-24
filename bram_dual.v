`timescale 1ns / 1ps
// Dual-port BRAM wrapper. Port A: write, Port B: read.
// DATA_FILE if non-empty triggers $readmemb on a range
// [INIT_START_ADDR, INIT_END_ADDR] at elaboration time.
module bram_dual #(
    parameter RAM_WIDTH       = 8,
    parameter RAM_ADDR_BITS   = 12,
    parameter DATA_FILE       = "",
    parameter INIT_START_ADDR = 0,
    parameter INIT_END_ADDR   = 0
)(
    input clock,
    input                     we_a,
    input                     en_a,
    input [RAM_ADDR_BITS-1:0] addr_a,
    input [RAM_WIDTH-1:0]     din_a,
    input                     en_b,
    input [RAM_ADDR_BITS-1:0] addr_b,
    output reg [RAM_WIDTH-1:0] dout_b
);
    (* RAM_STYLE = "BLOCK" *)
    reg [RAM_WIDTH-1:0] ram_name [(2**RAM_ADDR_BITS)-1:0];

    initial begin
        if (DATA_FILE != "") begin
            $readmemb(DATA_FILE, ram_name, INIT_START_ADDR, INIT_END_ADDR);
        end
    end

    always @(posedge clock) begin
        if (en_a && we_a) ram_name[addr_a] <= din_a;
    end

    always @(posedge clock) begin
        if (en_b) dout_b <= ram_name[addr_b];
    end
endmodule
