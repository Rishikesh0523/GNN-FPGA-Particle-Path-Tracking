`timescale 1ns / 1ps

module bram_burst_wrapper_ss #(
    parameter RAM_WIDTH       = 8,          // External interface width (bytes)
    parameter RAM_ADDR_BITS   = 12,
    parameter MAX_BURST_SIZE  = 32,         // In bytes
    parameter DATA_FILE       = "",
    parameter INIT_START_ADDR = 0,
    parameter INIT_END_ADDR   = 0
)(
    input clock,
    input reset,

    // Burst Write Port (Scatter-Sum)
    input                                        write_start,
    input  [RAM_ADDR_BITS-1:0]                   write_addr_base,
    input  [$clog2(MAX_BURST_SIZE):0]            write_burst_size,  // in bytes
    input  [RAM_WIDTH*MAX_BURST_SIZE-1:0]        write_data,        // 32 x 8-bit flat
    output reg                                   write_done,
    output reg                                   write_busy,

    // Burst Read Port
    input                                        read_start,
    input  [RAM_ADDR_BITS-1:0]                   read_addr_base,
    input  [$clog2(MAX_BURST_SIZE):0]            read_burst_size,   // in bytes
    output reg [RAM_WIDTH*MAX_BURST_SIZE-1:0]    read_data,         // 32 x 8-bit flat
    output reg                                   read_valid,
    output reg                                   read_busy
);

    //--------------------------------------------------------------------------
    // URAM internal width — do not change
    //--------------------------------------------------------------------------
    localparam URAM_WIDTH      = 72;

    // Flat bus width in bits
    localparam FLAT_BITS       = MAX_BURST_SIZE * RAM_WIDTH;            // 256

    // How many 72-bit URAM words cover the flat bus
    localparam WORDS_PER_BURST = (FLAT_BITS + URAM_WIDTH - 1) / URAM_WIDTH; // 4

    // Total packed buffer width (WORDS_PER_BURST * 72 = 288)
    localparam PACKED_BITS     = WORDS_PER_BURST * URAM_WIDTH;

    // Leftover bits in the last URAM word
    localparam LAST_WORD_BITS  = FLAT_BITS % URAM_WIDTH;               // 40
    localparam LAST_PAD_BITS   = (LAST_WORD_BITS == 0) ? 0
                                 : (URAM_WIDTH - LAST_WORD_BITS);       // 32

    //--------------------------------------------------------------------------
    // Internal URAM signals
    //--------------------------------------------------------------------------
    reg                      bram_we_a;
    reg                      bram_en_a;
    reg  [RAM_ADDR_BITS-1:0] bram_addr_a;
    reg  [URAM_WIDTH-1:0]    bram_din_a;

    wire                     bram_en_b;
    wire [RAM_ADDR_BITS-1:0] bram_addr_b;
    wire [URAM_WIDTH-1:0]    bram_dout_b;

    //--------------------------------------------------------------------------
    // URAM instance — uses URAM_WIDTH not RAM_WIDTH
    //--------------------------------------------------------------------------
    bram_dual #(
        .RAM_WIDTH      (URAM_WIDTH),
        .RAM_ADDR_BITS  (RAM_ADDR_BITS),
        .DATA_FILE      (DATA_FILE),
        .INIT_START_ADDR(INIT_START_ADDR),
        .INIT_END_ADDR  (INIT_END_ADDR)
    ) bram_inst (
        .clock  (clock),
        .we_a   (bram_we_a),
        .en_a   (bram_en_a),
        .addr_a (bram_addr_a),
        .din_a  (bram_din_a),
        .en_b   (bram_en_b),
        .addr_b (bram_addr_b),
        .dout_b (bram_dout_b)
    );

    //--------------------------------------------------------------------------
    // Pack/unpack buffers
    //--------------------------------------------------------------------------
    reg [PACKED_BITS-1:0] packed_write;
    reg [PACKED_BITS-1:0] packed_read;

    //--------------------------------------------------------------------------
    // Pack: 32 x 8-bit flat -> WORDS_PER_BURST x 72-bit
    //--------------------------------------------------------------------------
    always @(*) begin : pack_write
        integer w;
        packed_write = {PACKED_BITS{1'b0}};

        // Full words
        for (w = 0; w < WORDS_PER_BURST - 1; w = w + 1)
            packed_write[w*URAM_WIDTH +: URAM_WIDTH] =
                write_data[w*URAM_WIDTH +: URAM_WIDTH];

        // Partial last word — zero-pad upper bits
        if (LAST_WORD_BITS != 0)
            packed_write[(WORDS_PER_BURST-1)*URAM_WIDTH +: URAM_WIDTH] =
                {{LAST_PAD_BITS{1'b0}},
                  write_data[(WORDS_PER_BURST-1)*URAM_WIDTH +: LAST_WORD_BITS]};
        else
            packed_write[(WORDS_PER_BURST-1)*URAM_WIDTH +: URAM_WIDTH] =
                write_data[(WORDS_PER_BURST-1)*URAM_WIDTH +: URAM_WIDTH];
    end

    //--------------------------------------------------------------------------
    // Unpack: WORDS_PER_BURST x 72-bit -> 32 x 8-bit flat
    //--------------------------------------------------------------------------
    always @(*) begin : unpack_read
        integer w;
        read_data = {FLAT_BITS{1'b0}};

        // Full words
        for (w = 0; w < WORDS_PER_BURST - 1; w = w + 1)
            read_data[w*URAM_WIDTH +: URAM_WIDTH] =
                packed_read[w*URAM_WIDTH +: URAM_WIDTH];

        // Partial last word — discard padding, take only LAST_WORD_BITS
        if (LAST_WORD_BITS != 0)
            read_data[(WORDS_PER_BURST-1)*URAM_WIDTH +: LAST_WORD_BITS] =
                packed_read[(WORDS_PER_BURST-1)*URAM_WIDTH +: LAST_WORD_BITS];
        else
            read_data[(WORDS_PER_BURST-1)*URAM_WIDTH +: URAM_WIDTH] =
                packed_read[(WORDS_PER_BURST-1)*URAM_WIDTH +: URAM_WIDTH];
    end

    //--------------------------------------------------------------------------
    // Port B control — shared by read FSM and write read-modify-write
    //--------------------------------------------------------------------------
    assign bram_en_b   = (read_state == R_READING) || (write_state == W_READ_WAIT);
    assign bram_addr_b = (read_state == R_READING) ? read_current_addr
                                                    : write_current_addr;

    //--------------------------------------------------------------------------
    // WRITE FSM — Read-Modify-Write (Scatter-Sum) on 72-bit words
    //--------------------------------------------------------------------------
    localparam W_IDLE      = 3'b000;
    localparam W_READ_WAIT = 3'b001;
    localparam W_READ_DATA = 3'b010;
    localparam W_ADD_WRITE = 3'b011;
    localparam W_DONE      = 3'b100;

    reg [2:0]                         write_state;
    reg [$clog2(WORDS_PER_BURST):0]   write_counter;
    reg [$clog2(WORDS_PER_BURST):0]   write_total_words;
    reg [RAM_ADDR_BITS-1:0]           write_current_addr;
    reg [PACKED_BITS-1:0]             write_packed_reg;   // latched packed data
    reg [URAM_WIDTH-1:0]              old_data;           // read-modify-write buffer

    always @(posedge clock) begin
        if (reset) begin
            write_state        <= W_IDLE;
            write_counter      <= 0;
            write_done         <= 1'b0;
            write_busy         <= 1'b0;
            write_current_addr <= 0;
            write_total_words  <= 0;
            write_packed_reg   <= 0;
            old_data           <= 0;
            bram_we_a          <= 1'b0;
            bram_en_a          <= 1'b0;
            bram_addr_a        <= 0;
            bram_din_a         <= 0;
        end else begin
            case (write_state)

                W_IDLE: begin
                    write_done <= 1'b0;
                    bram_we_a  <= 1'b0;
                    bram_en_a  <= 1'b0;

                    if (write_start && write_burst_size > 0
                                    && write_burst_size <= MAX_BURST_SIZE) begin
                        write_state        <= W_READ_WAIT;
                        write_busy         <= 1'b1;
                        write_current_addr <= write_addr_base;
                        write_counter      <= 0;
                        // Total URAM words needed for this byte burst
                        write_total_words  <= (write_burst_size * RAM_WIDTH
                                               + URAM_WIDTH - 1) / URAM_WIDTH;
                        // Latch packed version of input
                        write_packed_reg   <= packed_write;
                    end else begin
                        write_busy <= 1'b0;
                    end
                end

                // Wait 1 cycle for BRAM read latency (address driven via bram_addr_b)
                W_READ_WAIT: begin
                    write_state <= W_READ_DATA;
                end

                // Capture existing URAM word for add
                W_READ_DATA: begin
                    old_data    <= bram_dout_b;
                    write_state <= W_ADD_WRITE;
                end

                // Add new 72-bit word to old, write back
                W_ADD_WRITE: begin
                    if (write_counter < write_total_words) begin
                        bram_en_a   <= 1'b1;
                        bram_we_a   <= 1'b1;
                        bram_addr_a <= write_current_addr;

                        // Scatter-sum: add existing URAM word to new packed word
                        bram_din_a  <= old_data
                                     + write_packed_reg[write_counter*URAM_WIDTH +: URAM_WIDTH];

                        write_current_addr <= write_current_addr + 1;
                        write_counter      <= write_counter + 1;

                        if (write_counter == write_total_words - 1)
                            write_state <= W_DONE;
                        else
                            write_state <= W_READ_WAIT;   // fetch next word
                    end
                end

                W_DONE: begin
                    bram_we_a   <= 1'b0;
                    bram_en_a   <= 1'b0;
                    write_done  <= 1'b1;
                    write_busy  <= 1'b0;
                    write_state <= W_IDLE;
                end

                default: write_state <= W_IDLE;

            endcase
        end
    end

    //--------------------------------------------------------------------------
    // READ FSM — burst read, assemble into packed_read then unpack
    //--------------------------------------------------------------------------
    localparam R_IDLE      = 2'b00;
    localparam R_READING   = 2'b01;
    localparam R_WAIT_LAST = 2'b10;
    localparam R_DONE      = 2'b11;

    reg [1:0]                        read_state;
    reg [$clog2(WORDS_PER_BURST):0]  read_counter;
    reg [$clog2(WORDS_PER_BURST):0]  read_total_words;
    reg [RAM_ADDR_BITS-1:0]          read_current_addr;

    always @(posedge clock) begin
        if (reset) begin
            read_state        <= R_IDLE;
            read_counter      <= 0;
            read_valid        <= 1'b0;
            read_busy         <= 1'b0;
            read_current_addr <= 0;
            read_total_words  <= 0;
            packed_read       <= 0;
        end else begin
            case (read_state)

                R_IDLE: begin
                    read_valid <= 1'b0;
                    if (read_start && read_burst_size > 0
                                   && read_burst_size <= MAX_BURST_SIZE
                                   && !write_busy) begin
                        read_state        <= R_READING;
                        read_busy         <= 1'b1;
                        read_current_addr <= read_addr_base;
                        read_counter      <= 0;
                        read_total_words  <= (read_burst_size * RAM_WIDTH
                                              + URAM_WIDTH - 1) / URAM_WIDTH;
                        packed_read       <= 0;
                    end else begin
                        read_busy <= 1'b0;
                    end
                end

                R_READING: begin
                    if (read_counter < read_total_words) begin
                        read_current_addr <= read_current_addr + 1;
                        read_counter      <= read_counter + 1;

                        // URAM has 1-cycle latency — store previous cycle's output
                        if (read_counter > 0)
                            packed_read[(read_counter-1)*URAM_WIDTH +: URAM_WIDTH]
                                <= bram_dout_b;

                        if (read_counter == read_total_words - 1)
                            read_state <= R_WAIT_LAST;
                    end
                end

                // Capture last URAM word
                R_WAIT_LAST: begin
                    packed_read[(read_total_words-1)*URAM_WIDTH +: URAM_WIDTH]
                        <= bram_dout_b;
                    read_state <= R_DONE;
                end

                // packed_read is full — unpack combinationally drives read_data
                R_DONE: begin
                    read_valid <= 1'b1;
                    read_busy  <= 1'b0;
                    read_state <= R_IDLE;
                end

            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Elaboration check
    //--------------------------------------------------------------------------
    // initial begin
    //     // $display("bram_burst_wrapper_ss: FLAT_BITS=%0d URAM_WIDTH=%0d WORDS_PER_BURST=%0d LAST_WORD_BITS=%0d LAST_PAD_BITS=%0d",
    //              FLAT_BITS, URAM_WIDTH, WORDS_PER_BURST, LAST_WORD_BITS, LAST_PAD_BITS);
    //     if (LAST_PAD_BITS < 0) begin
    //         $error("LAST_PAD_BITS negative — check FLAT_BITS vs URAM_WIDTH");
    //         $finish;
    //     end
    // end

endmodule