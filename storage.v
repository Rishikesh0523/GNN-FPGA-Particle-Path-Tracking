`timescale 1ns / 1ps

module storage_module
#(
    parameter DATA_BITS = 8,
    parameter RAM_ADDR_BITS_FOR_NODE = 0,
    parameter RAM_ADDR_BITS_FOR_EDGE = 0,
    parameter NUM_NODES = 0,
    parameter NUM_EDGES = 0,
    parameter NUM_FEATURES = 0,
    parameter MAX_BURST_SIZE = 32,
    parameter FEATURE_DIM = 32
)
(
    input clk,                          // ADDED: Clock input
    input rst,                          // ADDED: Reset input
    input encoder_edge_write_start,
    input [RAM_ADDR_BITS_FOR_EDGE-1:0] encoder_edge_write_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] encoder_edge_write_burst_size,
    input [DATA_BITS*MAX_BURST_SIZE-1:0] encoder_edge_write_data,
    output encoder_edge_write_done,
    output encoder_edge_write_busy,
    
    input encoder_edge_read_start,
    input [RAM_ADDR_BITS_FOR_EDGE-1:0] encoder_edge_read_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] encoder_edge_read_burst_size,
    output [DATA_BITS*MAX_BURST_SIZE-1:0] encoder_edge_read_data,
    output encoder_edge_read_valid,
    output encoder_edge_read_busy,

    input encoder_node_write_start,
    input [RAM_ADDR_BITS_FOR_NODE-1:0] encoder_node_write_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] encoder_node_write_burst_size,
    input [DATA_BITS*MAX_BURST_SIZE-1:0] encoder_node_write_data,
    output encoder_node_write_done,
    output encoder_node_write_busy,
    
    input encoder_node_read_start,
    input [RAM_ADDR_BITS_FOR_NODE-1:0] encoder_node_read_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] encoder_node_read_burst_size,
    output [DATA_BITS*MAX_BURST_SIZE-1:0] encoder_node_read_data,
    output encoder_node_read_valid,
    output encoder_node_read_busy,


    // Source connectivity
    input connectivity_src_re,
    input [RAM_ADDR_BITS_FOR_EDGE-5-1:0] connectivity_src_addr,
    output [RAM_ADDR_BITS_FOR_NODE-5-1:0] connectivity_src_data,
    
    // Destination connectivity
    input connectivity_dst_re,
    input [RAM_ADDR_BITS_FOR_EDGE-5-1:0] connectivity_dst_addr,
    output [RAM_ADDR_BITS_FOR_NODE-5-1:0] connectivity_dst_data,

    //============================================
    // Ping-Pong Buffer 0 - edge - Burst Interface
    //============================================

    input buf0_edge_write_start,
    input [RAM_ADDR_BITS_FOR_EDGE-1:0] buf0_edge_write_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] buf0_edge_write_burst_size,
    input [DATA_BITS*MAX_BURST_SIZE-1:0] buf0_edge_write_data,
    output buf0_edge_write_done,
    output buf0_edge_write_busy,
    
    input buf0_edge_read_start,
    input [RAM_ADDR_BITS_FOR_EDGE-1:0] buf0_edge_read_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] buf0_edge_read_burst_size,
    output [DATA_BITS*MAX_BURST_SIZE-1:0] buf0_edge_read_data,
    output buf0_edge_read_valid,
    output buf0_edge_read_busy,

    //============================================
    // Ping-Pong Buffer 1 - edge - Burst Interface
    //============================================
    input buf1_edge_write_start,
    input [RAM_ADDR_BITS_FOR_EDGE-1:0] buf1_edge_write_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] buf1_edge_write_burst_size,
    input [DATA_BITS*MAX_BURST_SIZE-1:0] buf1_edge_write_data,
    output buf1_edge_write_done,
    output buf1_edge_write_busy,

    input buf1_edge_read_start,
    input [RAM_ADDR_BITS_FOR_EDGE-1:0] buf1_edge_read_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] buf1_edge_read_burst_size,
    output [DATA_BITS*MAX_BURST_SIZE-1:0] buf1_edge_read_data,
    output buf1_edge_read_valid,
    output buf1_edge_read_busy,

    
    //============================================
    // In Scatter-Sum BRAM - Node - Burst Interface
    //============================================
    input in_ss_node_write_start,
    input [RAM_ADDR_BITS_FOR_NODE-1:0] in_ss_node_write_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] in_ss_node_write_burst_size,
    input [DATA_BITS*MAX_BURST_SIZE-1:0] in_ss_node_write_data,
    output in_ss_node_write_done,
    output in_ss_node_write_busy,
    
    input in_ss_node_read_start,
    input [RAM_ADDR_BITS_FOR_NODE-1:0] in_ss_node_read_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] in_ss_node_read_burst_size,
    output [DATA_BITS*MAX_BURST_SIZE-1:0] in_ss_node_read_data,
    output in_ss_node_read_valid,
    output in_ss_node_read_busy,

    //============================================
    // Out Scatter-Sum BRAM - Node - Burst Interface
    //============================================
    input out_ss_node_write_start,
    input [RAM_ADDR_BITS_FOR_NODE-1:0] out_ss_node_write_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] out_ss_node_write_burst_size,
    input [DATA_BITS*MAX_BURST_SIZE-1:0] out_ss_node_write_data,
    output out_ss_node_write_done,
    output out_ss_node_write_busy,
    
    input out_ss_node_read_start,
    input [RAM_ADDR_BITS_FOR_NODE-1:0] out_ss_node_read_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] out_ss_node_read_burst_size,
    output [DATA_BITS*MAX_BURST_SIZE-1:0] out_ss_node_read_data,
    output out_ss_node_read_valid,
    output out_ss_node_read_busy,

     //============================================
    // Ping-Pong Buffer 0 - Node - Burst Interface
    //============================================
    input buf0_node_write_start,
    input [RAM_ADDR_BITS_FOR_NODE-1:0] buf0_node_write_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] buf0_node_write_burst_size,
    input [DATA_BITS*MAX_BURST_SIZE-1:0] buf0_node_write_data,
    output buf0_node_write_done,
    output buf0_node_write_busy,
    
    input buf0_node_read_start,
    input [RAM_ADDR_BITS_FOR_NODE-1:0] buf0_node_read_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] buf0_node_read_burst_size,
    output [DATA_BITS*MAX_BURST_SIZE-1:0] buf0_node_read_data,
    output buf0_node_read_valid,
    output buf0_node_read_busy,

    //============================================
    // Ping-Pong Buffer 1 - Node - Burst Interface
    //============================================
    input buf1_node_write_start,
    input [RAM_ADDR_BITS_FOR_NODE-1:0] buf1_node_write_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] buf1_node_write_burst_size,
    input [DATA_BITS*MAX_BURST_SIZE-1:0] buf1_node_write_data,
    output buf1_node_write_done,
    output buf1_node_write_busy,
    
    input buf1_node_read_start,
    input [RAM_ADDR_BITS_FOR_NODE-1:0] buf1_node_read_addr_base,
    input [$clog2(MAX_BURST_SIZE):0] buf1_node_read_burst_size,
    output [DATA_BITS*MAX_BURST_SIZE-1:0] buf1_node_read_data,
    output buf1_node_read_valid,
    output buf1_node_read_busy,

    //============================================
    // Final Output BRAM - Edge Scores - Burst Interface
    //============================================
    input edge_score_write_start,
    input [RAM_ADDR_BITS_FOR_EDGE-6:0] edge_score_write_addr_base,
    input [$clog2(1):0] edge_score_write_burst_size,
    input [DATA_BITS-1:0] edge_score_write_data,
    output edge_score_write_done,
    output edge_score_write_busy,
    
    input edge_score_read_start,
    input [RAM_ADDR_BITS_FOR_EDGE-6:0] edge_score_read_addr_base,
    input [$clog2(1):0] edge_score_read_burst_size,
    output [DATA_BITS*MAX_BURST_SIZE-1:0] edge_score_read_data,
    output edge_score_read_valid,
    output edge_score_read_busy
);

bram_burst_wrapper # (
    .RAM_WIDTH(DATA_BITS),
    .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_EDGE),
    .MAX_BURST_SIZE(MAX_BURST_SIZE),
    .DATA_FILE(""),
    .INIT_START_ADDR(0),
    .INIT_END_ADDR(NUM_EDGES * NUM_FEATURES - 1)
) edge_encoder_output_bram (
    .clock(clk),
    .reset(rst),
    
    // Write port - Use registered signals
    .write_start(encoder_edge_write_start),
    .write_addr_base(encoder_edge_write_addr_base),
    .write_burst_size(encoder_edge_write_burst_size),
    .write_data(encoder_edge_write_data),
    .write_done(encoder_edge_write_done),
    .write_busy(encoder_edge_write_busy),
    
    // Read port
    .read_start(encoder_edge_read_start),
    .read_addr_base(encoder_edge_read_addr_base),
    .read_burst_size(encoder_edge_read_burst_size),
    .read_data(encoder_edge_read_data),
    .read_valid(encoder_edge_read_valid),
    .read_busy(encoder_edge_read_busy)
);

bram_burst_wrapper #(
    .RAM_WIDTH(DATA_BITS),
    .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_NODE),
    .MAX_BURST_SIZE(MAX_BURST_SIZE),
    .DATA_FILE(""),
    .INIT_START_ADDR(0),
    .INIT_END_ADDR(NUM_NODES * NUM_FEATURES - 1)
)
node_encoder_output_bram (
    .clock(clk),
    .reset(rst),
    
    // Write port - Use registered signals
    .write_start(encoder_node_write_start),
    .write_addr_base(encoder_node_write_addr_base),
    .write_burst_size(encoder_node_write_burst_size),
    .write_data(encoder_node_write_data),
    .write_done(encoder_node_write_done),
    .write_busy(encoder_node_write_busy),
    
    // Read port
    .read_start(encoder_node_read_start),
    .read_addr_base(encoder_node_read_addr_base),
    .read_burst_size(encoder_node_read_burst_size),
    .read_data(encoder_node_read_data),
    .read_valid(encoder_node_read_valid),
    .read_busy(encoder_node_read_busy)
);



bram_dual #(
    .RAM_WIDTH(RAM_ADDR_BITS_FOR_NODE-5),  // Only need node index, not feature index
    .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_EDGE-5),
    .DATA_FILE("connectivity_source_data.mem"),
    .INIT_START_ADDR(0),
    .INIT_END_ADDR(NUM_EDGES-1)
) source_connectivity_bram (
    .clock(clk),
    
    // Port A (Write - unused for read-only)
    .we_a(1'b0),
    .en_a(1'b0),
    .addr_a({RAM_ADDR_BITS_FOR_EDGE-5{1'b0}}),
    .din_a({RAM_ADDR_BITS_FOR_NODE-5{1'b0}}),
    
    // Port B (Read)
    .en_b(connectivity_src_re),
    .addr_b(connectivity_src_addr),
    .dout_b(connectivity_src_data)
);

//============================================
// DESTINATION CONNECTIVITY BRAM (Read-Only using bram_dual)
//============================================
bram_dual #(
    .RAM_WIDTH(RAM_ADDR_BITS_FOR_NODE-5),  // Only need node index, not feature index
    .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_EDGE-5),
    .DATA_FILE("connectivity_destination_data.mem"),
    .INIT_START_ADDR(0),
    .INIT_END_ADDR(NUM_EDGES-1)
) destination_connectivity_bram (
    .clock(clk),
    
    // Port A (Write - unused for read-only)
    .we_a(1'b0),
    .en_a(1'b0),
    .addr_a({RAM_ADDR_BITS_FOR_EDGE-5{1'b0}}),
    .din_a({RAM_ADDR_BITS_FOR_NODE-5{1'b0}}),
    
    // Port B (Read)
    .en_b(connectivity_dst_re),
    .addr_b(connectivity_dst_addr),
    .dout_b(connectivity_dst_data)
);

//============================================
// PING-PONG BUFFER 0 - EDGE FEATURES
//============================================
bram_burst_wrapper # (
    .RAM_WIDTH(DATA_BITS),
    .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_EDGE),
    .MAX_BURST_SIZE(MAX_BURST_SIZE),
    .DATA_FILE(""),
    .INIT_START_ADDR(0),
    .INIT_END_ADDR(NUM_EDGES * FEATURE_DIM - 1)
) buffer0_edge (
    .clock(clk),
    .reset(rst),
    
    // Write port
    .write_start(buf0_edge_write_start),
    .write_addr_base(buf0_edge_write_addr_base),
    .write_burst_size(buf0_edge_write_burst_size),
    .write_data(buf0_edge_write_data),
    .write_done(buf0_edge_write_done),
    .write_busy(buf0_edge_write_busy),
    
    // Read port
    .read_start(buf0_edge_read_start),
    .read_addr_base(buf0_edge_read_addr_base),
    .read_burst_size(buf0_edge_read_burst_size),
    .read_data(buf0_edge_read_data),
    .read_valid(buf0_edge_read_valid),
    .read_busy(buf0_edge_read_busy)
);

//============================================
// PING-PONG BUFFER 1 - EDGE FEATURES
//============================================
bram_burst_wrapper # (
    .RAM_WIDTH(DATA_BITS),
    .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_EDGE),
    .MAX_BURST_SIZE(MAX_BURST_SIZE),
    .DATA_FILE(""),
    .INIT_START_ADDR(0),
    .INIT_END_ADDR(NUM_EDGES * FEATURE_DIM - 1)
) buffer1_edge (
    .clock(clk),
    .reset(rst),
    
    // Write port
    .write_start(buf1_edge_write_start),
    .write_addr_base(buf1_edge_write_addr_base),
    .write_burst_size(buf1_edge_write_burst_size),
    .write_data(buf1_edge_write_data),
    .write_done(buf1_edge_write_done),
    .write_busy(buf1_edge_write_busy),
    
    // Read port
    .read_start(buf1_edge_read_start),
    .read_addr_base(buf1_edge_read_addr_base),
    .read_burst_size(buf1_edge_read_burst_size),
    .read_data(buf1_edge_read_data),
    .read_valid(buf1_edge_read_valid),
    .read_busy(buf1_edge_read_busy)
);


//============================================
// IN SCATTER-SUM BRAM - NODE FEATURES
//============================================
// TODO: Thresholding
bram_burst_wrapper_ss # (
    .RAM_WIDTH(DATA_BITS),
    .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_NODE),
    .MAX_BURST_SIZE(MAX_BURST_SIZE),
    .DATA_FILE("scatter_sum_in.mem"),
    .INIT_START_ADDR(0),
    .INIT_END_ADDR(NUM_NODES * FEATURE_DIM - 1)
) in_scatter_sum_bram_node (
    .clock(clk),
    .reset(rst),
    
    // Write port (Scatter-Sum)
    .write_start(in_ss_node_write_start),
    .write_addr_base(in_ss_node_write_addr_base),
    .write_burst_size(in_ss_node_write_burst_size),
    .write_data(in_ss_node_write_data),
    .write_done(in_ss_node_write_done),
    .write_busy(in_ss_node_write_busy),
    
    // Read port
    .read_start(in_ss_node_read_start),
    .read_addr_base(in_ss_node_read_addr_base),
    .read_burst_size(in_ss_node_read_burst_size),
    .read_data(in_ss_node_read_data),
    .read_valid(in_ss_node_read_valid),
    .read_busy(in_ss_node_read_busy)
);

//============================================
// OUT SCATTER-SUM BRAM - NODE FEATURES
//============================================
// TODO: Thresholding
bram_burst_wrapper_ss # (
    .RAM_WIDTH(DATA_BITS),
    .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_NODE),
    .MAX_BURST_SIZE(MAX_BURST_SIZE),
    .DATA_FILE("scatter_sum_in.mem"),
    .INIT_START_ADDR(0),
    .INIT_END_ADDR(NUM_NODES * FEATURE_DIM - 1)
) out_scatter_sum_bram_node (
    .clock(clk),
    .reset(rst),
    
    // Write port (Scatter-Sum)
    .write_start(out_ss_node_write_start),
    .write_addr_base(out_ss_node_write_addr_base),
    .write_burst_size(out_ss_node_write_burst_size),
    .write_data(out_ss_node_write_data),
    .write_done(out_ss_node_write_done),
    .write_busy(out_ss_node_write_busy),
    
    // Read port
    .read_start(out_ss_node_read_start),
    .read_addr_base(out_ss_node_read_addr_base),
    .read_burst_size(out_ss_node_read_burst_size),
    .read_data(out_ss_node_read_data),
    .read_valid(out_ss_node_read_valid),
    .read_busy(out_ss_node_read_busy)
);


//============================================
// PING-PONG BUFFER 0 - NODE FEATURES
//============================================
bram_burst_wrapper # (
    .RAM_WIDTH(DATA_BITS),
    .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_NODE),
    .MAX_BURST_SIZE(MAX_BURST_SIZE),
    .DATA_FILE(""),
    .INIT_START_ADDR(0),
    .INIT_END_ADDR(NUM_NODES * FEATURE_DIM - 1)
) buffer0_node (
    .clock(clk),
    .reset(rst),
    
    // Write port
    .write_start(buf0_node_write_start),
    .write_addr_base(buf0_node_write_addr_base),
    .write_burst_size(buf0_node_write_burst_size),
    .write_data(buf0_node_write_data),
    .write_done(buf0_node_write_done),
    .write_busy(buf0_node_write_busy),
    
    // Read port
    .read_start(buf0_node_read_start),
    .read_addr_base(buf0_node_read_addr_base),
    .read_burst_size(buf0_node_read_burst_size),
    .read_data(buf0_node_read_data),
    .read_valid(buf0_node_read_valid),
    .read_busy(buf0_node_read_busy)
);

//============================================
// PING-PONG BUFFER 1 - NODE FEATURES
//============================================
bram_burst_wrapper # (
    .RAM_WIDTH(DATA_BITS),
    .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_NODE),
    .MAX_BURST_SIZE(MAX_BURST_SIZE),
    .DATA_FILE(""),
    .INIT_START_ADDR(0),
    .INIT_END_ADDR(NUM_NODES * FEATURE_DIM - 1)
) buffer1_node (
    .clock(clk),
    .reset(rst),
    
    // Write port
    .write_start(buf1_node_write_start),
    .write_addr_base(buf1_node_write_addr_base),
    .write_burst_size(buf1_node_write_burst_size),
    .write_data(buf1_node_write_data),
    .write_done(buf1_node_write_done),
    .write_busy(buf1_node_write_busy),
    
    // Read port
    .read_start(buf1_node_read_start),
    .read_addr_base(buf1_node_read_addr_base),
    .read_burst_size(buf1_node_read_burst_size),
    .read_data(buf1_node_read_data),
    .read_valid(buf1_node_read_valid),
    .read_busy(buf1_node_read_busy)
);

//============================================
// FINAL OUTPUT BRAM - EDGE SCORES
//============================================
// Internal wires for 8-bit BRAM (MAX_BURST_SIZE=1)
wire [DATA_BITS-1:0] edge_score_write_data_internal;
wire [DATA_BITS-1:0] edge_score_read_data_internal;

// Extract lowest 8 bits for write, pad zeros for read
assign edge_score_write_data_internal = edge_score_write_data[DATA_BITS-1:0];
assign edge_score_read_data = {{(DATA_BITS*(MAX_BURST_SIZE-1)){1'b0}}, edge_score_read_data_internal};

// Debug: Monitor write data conversion
always @(posedge clk) begin
    if (edge_score_write_start) begin
        // $display("[STORAGE][%0t] EDGE_SCORE: write_data[255:0]=%h, extracted_internal=%h", 
//                $time, edge_score_write_data, edge_score_write_data_internal);
    end
end

bram_burst_wrapper # (
    .RAM_WIDTH(DATA_BITS),
    .RAM_ADDR_BITS(RAM_ADDR_BITS_FOR_EDGE-5),  // One score per edge (not per feature)
    .MAX_BURST_SIZE(1),
    .DATA_FILE(""),
    .INIT_START_ADDR(0),
    .INIT_END_ADDR(NUM_EDGES - 1)  // NUM_EDGES scores total
) final_edge_score_bram (
    .clock(clk),
    .reset(rst),
    
    // Write port
    .write_start(edge_score_write_start),
    .write_addr_base(edge_score_write_addr_base),
    .write_burst_size(edge_score_write_burst_size),
    .write_data(edge_score_write_data_internal),
    .write_done(edge_score_write_done),
    .write_busy(edge_score_write_busy),
    
    // Read port
    .read_start(edge_score_read_start),
    .read_addr_base(edge_score_read_addr_base),
    .read_burst_size(edge_score_read_burst_size),
    .read_data(edge_score_read_data_internal),
    .read_valid(edge_score_read_valid),
    .read_busy(edge_score_read_busy)
);

endmodule