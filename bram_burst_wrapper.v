`timescale 1ns / 1ps
//==============================================================================
// bram_burst_wrapper.v
//
// Packs/unpacks 32x8-bit flat bus into 72-bit URAM words.
//
// 32 x 8 = 256 bits total
// 256 / 72 = 3 full words (216 bits) + 1 partial word (40 bits)
// So 4 URAM words per burst of 32 bytes — 8x fewer cycles than byte-wide
//
// Packing (write):
//   word 0 : flat[71:0]    = bytes  0..8
//   word 1 : flat[143:72]  = bytes  9..17
//   word 2 : flat[215:144] = bytes 18..26
//   word 3 : flat[255:216] zero-padded to 72 bits = bytes 27..31
//
// Unpacking (read):
//   reverse of above, upper bits of word 3 discarded
//==============================================================================
module bram_burst_wrapper #(
    parameter RAM_WIDTH        = 8,                      // URAM native width
    parameter RAM_ADDR_BITS    = 12,
    parameter MAX_BURST_SIZE   = 32,                      // in bytes (8-bit words)
    parameter DATA_FILE        = "",
    parameter INIT_START_ADDR  = 0,
    parameter INIT_END_ADDR    = 0,
    // Derived — do not override
    parameter FLAT_BITS        = MAX_BURST_SIZE * RAM_WIDTH,      // 256
    parameter WORDS_PER_BURST  = (FLAT_BITS + 72 - 1) / 72  // 4
)(
    input  clock,
    input  reset,

    // Burst Write Port
    input                          write_start,
    input  [RAM_ADDR_BITS-1:0]     write_addr_base,
    input  [$clog2(MAX_BURST_SIZE):0] write_burst_size,   // in bytes
    input  [FLAT_BITS-1:0]         write_data,            // 32 x 8-bit flat
    output reg                     write_done,
    output reg                     write_busy,

    // Burst Read Port
    input                          read_start,
    input  [RAM_ADDR_BITS-1:0]     read_addr_base,
    input  [$clog2(MAX_BURST_SIZE):0] read_burst_size,    // in bytes
    output reg [FLAT_BITS-1:0]     read_data,             // 32 x 8-bit flat
    output reg                     read_valid,
    output reg                     read_busy
);

    //--------------------------------------------------------------------------
    // URAM word count for a given byte count
    // ceil(burst_bytes * 8 / 72)
    //--------------------------------------------------------------------------
    function automatic integer bytes_to_words;
        input integer nbytes;
        begin
            bytes_to_words = (nbytes * 8 + 72 - 1) / 72;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Internal URAM signals
    //--------------------------------------------------------------------------
    reg                      bram_we_a;
    reg                      bram_en_a;
    reg  [RAM_ADDR_BITS-1:0] bram_addr_a;
    reg  [72-1:0]     bram_din_a;

    wire                     bram_en_b;
    wire [RAM_ADDR_BITS-1:0] bram_addr_b;
    wire [72-1:0]     bram_dout_b;

    //--------------------------------------------------------------------------
    // URAM instance
    //--------------------------------------------------------------------------
    bram_dual #(
        .RAM_WIDTH      (72),
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
    // READ state machine
    //--------------------------------------------------------------------------
    localparam R_IDLE      = 2'b00;
    localparam R_READING   = 2'b01;
    localparam R_WAIT_LAST = 2'b10;
    localparam R_DONE      = 2'b11;

    reg [1:0]              read_state;
    reg [$clog2(WORDS_PER_BURST):0] read_counter;
    reg [$clog2(WORDS_PER_BURST):0] read_total_words;
    reg [RAM_ADDR_BITS-1:0] read_current_addr;

    assign bram_en_b   = (read_state == R_READING);
    assign bram_addr_b = read_current_addr;

    //--------------------------------------------------------------------------
    // Packed write buffer: flat 256-bit bus padded to WORDS_PER_BURST*72
    //--------------------------------------------------------------------------
    localparam PACKED_BITS = WORDS_PER_BURST * 72;   // 4 * 72 = 288

    reg [PACKED_BITS-1:0] packed_write;     // padded write buffer
    reg [PACKED_BITS-1:0] packed_read;      // assembled read buffer

    localparam LAST_WORD_BITS = FLAT_BITS - (WORDS_PER_BURST-1)*72;  // 256 - 216 = 40


    //--------------------------------------------------------------------------
    // Pack flat write_data into 72-bit words
    // Upper bits of last word are zero-padded
    //--------------------------------------------------------------------------
    always @(*) begin : pack_write
    integer w;
    packed_write = {PACKED_BITS{1'b0}};

    // Full words (w = 0, 1, 2) — constant width RAM_WIDTH
    for (w = 0; w < WORDS_PER_BURST - 1; w = w + 1)
        packed_write[w*72 +: 72] = write_data[w*72 +: 72];

    // Partial last word (w = 3) — constant width LAST_WORD_BITS
    packed_write[(WORDS_PER_BURST-1)*72 +: 72] =
        {{(72 - LAST_WORD_BITS){1'b0}},
          write_data[(WORDS_PER_BURST-1)*72 +: LAST_WORD_BITS]};
end

    //--------------------------------------------------------------------------
    // Unpack 72-bit read words back to flat 256-bit bus
    //--------------------------------------------------------------------------
    always @(*) begin : unpack_read
    integer w;
    read_data = {FLAT_BITS{1'b0}};

    // Full words
    for (w = 0; w < WORDS_PER_BURST - 1; w = w + 1)
        read_data[w*72 +: 72] = packed_read[w*72 +: 72];

    // Partial last word — only take LAST_WORD_BITS, discard upper padding
    read_data[(WORDS_PER_BURST-1)*72 +: LAST_WORD_BITS] =
        packed_read[(WORDS_PER_BURST-1)*72 +: LAST_WORD_BITS];
end

    //--------------------------------------------------------------------------
    // WRITE state machine
    //--------------------------------------------------------------------------
    localparam W_IDLE    = 2'b00;
    localparam W_WRITING = 2'b01;
    localparam W_DONE    = 2'b10;

    reg [1:0]              write_state;
    reg [$clog2(WORDS_PER_BURST):0] write_counter;      // counts URAM words
    reg [$clog2(WORDS_PER_BURST):0] write_total_words;  // total URAM words for burst
    reg [RAM_ADDR_BITS-1:0] write_current_addr;
    reg [PACKED_BITS-1:0]   write_packed_reg;            // latched packed data

    always @(posedge clock) begin
        if (reset) begin
            write_state        <= W_IDLE;
            write_counter      <= 0;
            write_done         <= 1'b0;
            write_busy         <= 1'b0;
            write_current_addr <= 0;
            write_total_words  <= 0;
            write_packed_reg   <= 0;
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
                        write_state        <= W_WRITING;
                        write_busy         <= 1'b1;
                        write_current_addr <= write_addr_base;
                        write_counter      <= 0;
                        // How many 72-bit words needed for this burst
                        write_total_words  <= bytes_to_words(write_burst_size);
                        // Latch packed data
                        write_packed_reg   <= packed_write;
                    end else begin
                        write_busy <= 1'b0;
                    end
                end

                W_WRITING: begin
                    if (write_counter < write_total_words) begin
                        bram_en_a          <= 1'b1;
                        bram_we_a          <= 1'b1;
                        bram_addr_a        <= write_current_addr;
                        // Write one 72-bit word
                        bram_din_a         <= write_packed_reg[write_counter*72 +: 72];
                        write_current_addr <= write_current_addr + 1;
                        write_counter      <= write_counter + 1;

                        if (write_counter == write_total_words - 1)
                            write_state <= W_DONE;
                    end
                end

                W_DONE: begin
                    bram_we_a  <= 1'b0;
                    bram_en_a  <= 1'b0;
                    write_done <= 1'b1;
                    write_busy <= 1'b0;
                    write_state <= W_IDLE;
                end

            endcase
        end
    end


    

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
                                   && read_burst_size <= MAX_BURST_SIZE) begin
                        read_state        <= R_READING;
                        read_busy         <= 1'b1;
                        read_current_addr <= read_addr_base;
                        read_counter      <= 0;
                        read_total_words  <= bytes_to_words(read_burst_size);
                        packed_read       <= 0;
                    end else begin
                        read_busy <= 1'b0;
                    end
                end

                R_READING: begin
                    if (read_counter < read_total_words) begin
                        // Advance address for next word
                        read_current_addr <= read_current_addr + 1;
                        read_counter      <= read_counter + 1;

                        // Capture previous cycle's URAM output (1-cycle latency)
                        if (read_counter > 0)
                            packed_read[(read_counter-1)*72 +: 72] <= bram_dout_b;

                        if (read_counter == read_total_words - 1)
                            read_state <= R_WAIT_LAST;
                    end
                end

                R_WAIT_LAST: begin
                    // Capture last URAM word
                    packed_read[(read_total_words-1)*72 +: 72] <= bram_dout_b;
                    read_state <= R_DONE;
                end

                R_DONE: begin
                    // packed_read is now full — unpack combinationally drives read_data
                    read_valid <= 1'b1;
                    read_busy  <= 1'b0;
                    read_state <= R_IDLE;
                end

            endcase
        end
    end

    // packed_read is a reg — needs to be declared at module level
    // moved declaration here for clarity (Verilog-2001 allows this at top)

endmodule