`timescale 1ns / 1ps
// Burst wrapper around bram_dual.
// Issues a sequence of single-cycle reads or writes for the requested
// burst length, starting at addr_base. Handshakes via start/done.
module bram_burst_wrapper #(
    parameter DATA_BITS       = 8,
    parameter RAM_ADDR_BITS   = 12,
    parameter MAX_BURST_SIZE  = 32
)(
    input clk,
    input rst,
    input start,
    input write_en,
    input [RAM_ADDR_BITS-1:0]               addr_base,
    input [$clog2(MAX_BURST_SIZE):0]        burst_size,
    input [DATA_BITS*MAX_BURST_SIZE-1:0]    din_packed,
    output reg                              busy,
    output reg                              done,
    output reg [DATA_BITS*MAX_BURST_SIZE-1:0] dout_packed
);
    localparam IDLE = 2'd0, RUN = 2'd1, DONE_S = 2'd2;
    reg [1:0] state;
    reg [$clog2(MAX_BURST_SIZE):0] beat;
    reg [RAM_ADDR_BITS-1:0] cur_addr;

    wire bram_we = (state == RUN) && write_en;
    wire bram_en = (state == RUN);
    wire [DATA_BITS-1:0] din_beat =
        din_packed[beat*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] dout_beat;

    bram_dual #(
        .RAM_WIDTH(DATA_BITS),
        .RAM_ADDR_BITS(RAM_ADDR_BITS)
    ) u_bram (
        .clock(clk),
        .we_a(bram_we), .en_a(bram_en), .addr_a(cur_addr), .din_a(din_beat),
        .en_b(bram_en && !write_en), .addr_b(cur_addr), .dout_b(dout_beat)
    );

    always @(posedge clk) begin
        if (rst) begin
            state    <= IDLE;
            beat     <= 0;
            cur_addr <= 0;
            busy     <= 1'b0;
            done     <= 1'b0;
            dout_packed <= {DATA_BITS*MAX_BURST_SIZE{1'b0}};
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: if (start) begin
                    state    <= RUN;
                    beat     <= 0;
                    cur_addr <= addr_base;
                    busy     <= 1'b1;
                end
                RUN: begin
                    if (!write_en)
                        dout_packed[beat*DATA_BITS +: DATA_BITS] <= dout_beat;
                    if (beat == burst_size - 1) begin
                        state <= DONE_S;
                    end else begin
                        beat     <= beat + 1;
                        cur_addr <= cur_addr + 1;
                    end
                end
                DONE_S: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
