`timescale 1ns / 1ps

module top_module #(
    parameter NUM_EDGES = 5,    // Maximum edge capacity for this elaboration
    parameter NUM_NODES = 4,    // Maximum node capacity for this elaboration
    parameter OUT_FEATURES = 32,
    parameter DATA_BITS = 8,
    parameter USE_RMS_NORM = 0,
    parameter MAX_BURST_SIZE = 32,
    parameter ADDR_BITS = $clog2(NUM_EDGES)+1,
    parameter NODE_ADDR_BITS = $clog2(NUM_NODES)+1,
    parameter NUM_FEATURES = 32,
    parameter FEATURE_BITS = $clog2(NUM_FEATURES)
) (
    input wire clk,
    input wire rstn,
    input wire [ADDR_BITS-1:0] active_num_edges,
    input wire [NODE_ADDR_BITS-1:0] active_num_nodes,
    output wire processing_done,
    output wire [3:0] current_phase
);
    // ===============================
    // Internal Signals
    // ===============================
    
    // Phase Control FSM
    localparam PHASE_IDLE = 4'd0;
    localparam PHASE_EDGE_ENCODE = 4'd1;
    localparam PHASE_EDGE_ENCODE_WAIT = 4'd2;
    localparam PHASE_NODE_ENCODE = 4'd3;
    localparam PHASE_NODE_ENCODE_WAIT = 4'd4;
    localparam PHASE_MESSAGE_PASSING = 4'd5;
    localparam PHASE_MESSAGE_PASSING_WAIT = 4'd6;
    localparam PHASE_EDGE_DECODE = 4'd7;
    localparam PHASE_EDGE_DECODE_WAIT = 4'd8;
    localparam PHASE_DONE = 4'd9;
    
    reg [3:0] phase_state;
    reg [7:0] wait_counter;
    
    // Control Signals
    reg edge_start;
    reg node_start;
    reg mp_start;
    reg dec_start;
    
    // Status Signals
    wire edge_done;
    wire node_done;
    wire mp_done;
    wire dec_done;

    // Sticky capture for parallel encoder done signals.
    // edge_done and node_done may be single-cycle pulses that don't coincide,
    // so we latch each one and wait until both have been seen.
    reg edge_done_captured;
    reg node_done_captured;
    
    // ===============================
    // Edge Encoder Signals
    // ===============================
    wire [OUT_FEATURES*DATA_BITS-1:0] edge_data_out;
    wire [ADDR_BITS-1:0] edge_addr_out;
    wire edge_valid;
    (* keep = "true" *) wire [OUT_FEATURES*DATA_BITS-1:0] edge_data_out_kept;
    assign edge_data_out_kept = edge_data_out;

    // Edge Decoder Signals 
    wire [DATA_BITS-1:0] dec_data_out;
    wire [ADDR_BITS-1:0] dec_edge_addr_out;
    wire dec_data_valid;
    (* keep = "true" *) wire [DATA_BITS-1:0] dec_data_out_kept;
    assign dec_data_out_kept = dec_data_out;

    // ===============================
    // Node Encoder Signals
    // ===============================
    wire [OUT_FEATURES*DATA_BITS-1:0] node_data_out;
    wire [NODE_ADDR_BITS-1:0] node_addr_out;
    wire node_valid;
    (* keep = "true" *) wire [OUT_FEATURES*DATA_BITS-1:0] node_data_out_kept;
    assign node_data_out_kept = node_data_out;


    // ===============================
    // Storage Module Signals
    // ===============================
    // Edge Encoder BRAM
    wire encoder_edge_write_start;
    wire [ADDR_BITS+FEATURE_BITS-1:0] encoder_edge_write_addr;
    wire encoder_edge_read_start;
    wire [ADDR_BITS+FEATURE_BITS-1:0] encoder_edge_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] encoder_edge_read_data;
    wire encoder_edge_read_valid;
    wire encoder_edge_write_done;
    
    // Buffer0 Edge
    wire buf0_edge_write_start;
    wire [ADDR_BITS+FEATURE_BITS-1:0] buf0_edge_write_addr;
    wire buf0_edge_read_start;
    wire [ADDR_BITS+FEATURE_BITS-1:0] buf0_edge_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] buf0_edge_read_data;
    wire buf0_edge_read_valid;
    wire buf0_edge_write_done;
    
    // Buffer1 Edge
    wire buf1_edge_write_start;
    wire [ADDR_BITS+FEATURE_BITS-1:0] buf1_edge_write_addr;
    wire buf1_edge_read_start;
    wire [ADDR_BITS+FEATURE_BITS-1:0] buf1_edge_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] buf1_edge_read_data;
    wire buf1_edge_read_valid;
    wire buf1_edge_write_done;
    
    // Node Encoder BRAM
    wire encoder_node_write_start;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] encoder_node_write_addr;
    wire encoder_node_read_start;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] encoder_node_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] encoder_node_read_data;
    wire encoder_node_read_valid;
    wire encoder_node_write_done;
    
    // Buffer0 Node
    wire buf0_node_write_start;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] buf0_node_write_addr;
    wire buf0_node_read_start;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] buf0_node_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] buf0_node_read_data;
    wire buf0_node_read_valid;
    wire buf0_node_write_done;
    
    // Buffer1 Node
    wire buf1_node_write_start;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] buf1_node_write_addr;
    wire buf1_node_read_start;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] buf1_node_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] buf1_node_read_data;
    wire buf1_node_read_valid;
    wire buf1_node_write_done;
    
    // Scatter-Sum In
    wire in_ss_node_read_start;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] in_ss_node_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] in_ss_node_read_data;
    wire in_ss_node_read_valid;
    wire in_ss_node_write_start;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] in_ss_node_write_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] in_ss_node_write_data;
    wire in_ss_node_write_done;
    
    // Scatter-Sum Out
    wire out_ss_node_read_start;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] out_ss_node_read_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] out_ss_node_read_data;
    wire out_ss_node_read_valid;
    wire out_ss_node_write_start;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] out_ss_node_write_addr;
    wire [DATA_BITS*MAX_BURST_SIZE-1:0] out_ss_node_write_data;
    wire out_ss_node_write_done;
    
    // Connectivity
    wire connectivity_src_re;
    wire [ADDR_BITS-1:0] connectivity_src_addr;
    wire [NODE_ADDR_BITS-1:0] connectivity_src_data;
    wire connectivity_dst_re;
    wire [ADDR_BITS-1:0] connectivity_dst_addr;
    wire [NODE_ADDR_BITS-1:0] connectivity_dst_data;
    reg connectivity_src_re_d;
    reg connectivity_dst_re_d;
    reg [NODE_ADDR_BITS-1:0] connectivity_src_data_latched;
    reg [NODE_ADDR_BITS-1:0] connectivity_dst_data_latched;
    reg connectivity_src_valid;
    reg connectivity_dst_valid;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] connectivity_src_data_ext;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] connectivity_dst_data_ext;
    
    // ===============================
    // Message Passing Signals
    // ===============================
    wire mp_initial_edge_features_re;
    wire mp_edge_buf0_re;
    wire mp_edge_buf0_we;
    wire mp_edge_buf1_re;
    wire mp_edge_buf1_we;
    wire mp_initial_node_features_edge_re;
    wire mp_node_buf0_re_edge;
    wire mp_node_buf1_re_edge;
    wire mp_source_node_index_re;
    wire mp_destination_node_index_re;
    wire [ADDR_BITS+FEATURE_BITS-1:0] mp_edge_address;
    wire [ADDR_BITS+FEATURE_BITS-1:0] mp_load_edge_address;
    wire [ADDR_BITS-1:0] mp_edge_index;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] mp_in_node_index_ss;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] mp_out_node_index_ss;
    wire mp_scatter_sum_we;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] mp_edge_net_node_index;
    wire [DATA_BITS*OUT_FEATURES-1:0] mp_edge_output;
    wire mp_scatter_sum_features_in_re;
    wire mp_scatter_sum_features_out_re;
    wire mp_initial_node_features_node_re;
    wire mp_node_buf0_re_node;
    wire mp_node_buf0_we;
    wire mp_node_buf1_re_node;
    wire mp_node_buf1_we;
    wire [NODE_ADDR_BITS+FEATURE_BITS-1:0] mp_node_address;
    wire [NODE_ADDR_BITS-1:0] mp_node_index;
    wire [DATA_BITS*OUT_FEATURES-1:0] mp_node_output;
    wire edge_features_re;
    (* keep = "true" *) wire [DATA_BITS*OUT_FEATURES-1:0] mp_edge_output_kept;
    assign mp_edge_output_kept = mp_edge_output;

    (* keep = "true" *) wire [DATA_BITS*OUT_FEATURES-1:0] mp_node_output_kept;
    assign mp_node_output_kept = mp_node_output;
    reg mp_buf0_edge_write_start_r;
    reg [ADDR_BITS+FEATURE_BITS-1:0] mp_buf0_edge_write_addr_r;
    reg [DATA_BITS*OUT_FEATURES-1:0] mp_buf0_edge_write_data_r;
    reg mp_buf1_edge_write_start_r;
    reg [ADDR_BITS+FEATURE_BITS-1:0] mp_buf1_edge_write_addr_r;
    reg [DATA_BITS*OUT_FEATURES-1:0] mp_buf1_edge_write_data_r;

    // Sanitize shared read-select signals so X/Z control values do not
    // propagate into BRAM read-starts or read addresses in simulation.
    wire mp_initial_node_features_edge_re_sel;
    wire mp_initial_node_features_node_re_sel;
    wire mp_node_buf0_re_edge_sel;
    wire mp_node_buf0_re_node_sel;
    wire mp_node_buf1_re_edge_sel;
    wire mp_node_buf1_re_node_sel;
    assign mp_initial_node_features_edge_re_sel = (mp_initial_node_features_edge_re === 1'b1);
    assign mp_initial_node_features_node_re_sel = (mp_initial_node_features_node_re === 1'b1);
    assign mp_node_buf0_re_edge_sel = (mp_node_buf0_re_edge === 1'b1);
    assign mp_node_buf0_re_node_sel = (mp_node_buf0_re_node === 1'b1);
    assign mp_node_buf1_re_edge_sel = (mp_node_buf1_re_edge === 1'b1);
    assign mp_node_buf1_re_node_sel = (mp_node_buf1_re_node === 1'b1);
    assign connectivity_src_data_ext = {{FEATURE_BITS{1'b0}}, connectivity_src_data_latched};
    assign connectivity_dst_data_ext = {{FEATURE_BITS{1'b0}}, connectivity_dst_data_latched};
    
    // ===============================
    // Reset Synchronization
    // ===============================
    reg rst;
    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            rst <= 1'b1;
        else
            rst <= 1'b0;
    end

    // Connectivity BRAM reads are synchronous. Latch the returned node indices
    // one cycle after the read request and only raise valid once the captured
    // data is stable, so downstream logic never consumes raw/X BRAM outputs.
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            connectivity_src_re_d <= 1'b0;
            connectivity_dst_re_d <= 1'b0;
            connectivity_src_data_latched <= {NODE_ADDR_BITS{1'b0}};
            connectivity_dst_data_latched <= {NODE_ADDR_BITS{1'b0}};
            connectivity_src_valid <= 1'b0;
            connectivity_dst_valid <= 1'b0;
        end else begin
            connectivity_src_re_d <= connectivity_src_re;
            connectivity_dst_re_d <= connectivity_dst_re;

            if (connectivity_src_re)
                connectivity_src_valid <= 1'b0;
            if (connectivity_dst_re)
                connectivity_dst_valid <= 1'b0;

            if (connectivity_src_re_d) begin
                connectivity_src_data_latched <= connectivity_src_data;
                connectivity_src_valid <= 1'b1;
            end
            if (connectivity_dst_re_d) begin
                connectivity_dst_data_latched <= connectivity_dst_data;
                connectivity_dst_valid <= 1'b1;
            end
        end
    end
    
    // ===============================
    // Phase Control FSM
    // ===============================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            phase_state <= PHASE_IDLE;
            wait_counter <= 8'd0;
            edge_start <= 1'b0;
            node_start <= 1'b0;
            mp_start <= 1'b0;
            dec_start <= 1'b0;
            edge_done_captured <= 1'b0;
            node_done_captured <= 1'b0;
        end else begin
            // Default: deassert start signals
            edge_start <= 1'b0;
            node_start <= 1'b0;
            mp_start <= 1'b0;
            dec_start <= 1'b0;

            // Latch encoder done pulses — cleared when we leave PHASE_EDGE_ENCODE_WAIT
            if (edge_done) edge_done_captured <= 1'b1;
            if (node_done) node_done_captured <= 1'b1;
            
            case (phase_state)
                PHASE_IDLE: begin
                    wait_counter <= 8'd10;
                    phase_state <= PHASE_EDGE_ENCODE;
                end
                
                PHASE_EDGE_ENCODE: begin
                    if (wait_counter > 0) begin
                        wait_counter <= wait_counter - 1;
                    end else begin
                        // Start both encoders simultaneously — they use independent
                        // BRAMs (encoder_edge vs encoder_node) with no shared resources.
                        edge_start <= 1'b1;
                        node_start <= 1'b1;
                        phase_state <= PHASE_EDGE_ENCODE_WAIT;
                    end
                end
                
                PHASE_EDGE_ENCODE_WAIT: begin
                    // Wait until BOTH encoder done signals have been seen.
                    // Uses sticky latches in case the pulses don't coincide.
                    if ((edge_done || edge_done_captured) &&
                        (node_done || node_done_captured)) begin
                        wait_counter <= 8'd10;
                        edge_done_captured <= 1'b0;
                        node_done_captured <= 1'b0;
                        phase_state <= PHASE_MESSAGE_PASSING;
                    end
                end
                
                // PHASE_NODE_ENCODE and PHASE_NODE_ENCODE_WAIT are now bypassed —
                // node encoding runs in parallel with edge encoding above.
                // States kept to preserve localparam values.
                PHASE_NODE_ENCODE: begin
                    phase_state <= PHASE_MESSAGE_PASSING;
                end
                
                PHASE_NODE_ENCODE_WAIT: begin
                    phase_state <= PHASE_MESSAGE_PASSING;
                end
                
                PHASE_MESSAGE_PASSING: begin
                    if (wait_counter > 0) begin
                        wait_counter <= wait_counter - 1;
                    end else begin
                        mp_start <= 1'b1;
                        phase_state <= PHASE_MESSAGE_PASSING_WAIT;
                    end
                end
                
                PHASE_MESSAGE_PASSING_WAIT: begin
                    if (mp_done) begin
                        wait_counter <= 8'd10;
                        phase_state <= PHASE_EDGE_DECODE;
                    end
                end
                
                PHASE_EDGE_DECODE: begin
                    if (wait_counter > 0) begin
                        wait_counter <= wait_counter - 1;
                    end else begin
                        dec_start <= 1'b1;
                        phase_state <= PHASE_EDGE_DECODE_WAIT;
                    end
                end
                
                PHASE_EDGE_DECODE_WAIT: begin
                    if (dec_done) begin
                        wait_counter <= 8'd10;
                        phase_state <= PHASE_DONE;
                    end
                end
                
                PHASE_DONE: begin
                    // Stay in done state
                    phase_state <= PHASE_DONE;
                end
                
                default: begin
                    phase_state <= PHASE_IDLE;
                end
            endcase
        end
    end
    
    // Register message-passing edge write requests at the top-level storage
    // boundary so the write pulse, address, and data stay aligned in waveform
    // and at the storage input ports.
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            mp_buf0_edge_write_start_r <= 1'b0;
            mp_buf0_edge_write_addr_r <= {(ADDR_BITS+FEATURE_BITS){1'b0}};
            mp_buf0_edge_write_data_r <= {(DATA_BITS*OUT_FEATURES){1'b0}};
            mp_buf1_edge_write_start_r <= 1'b0;
            mp_buf1_edge_write_addr_r <= {(ADDR_BITS+FEATURE_BITS){1'b0}};
            mp_buf1_edge_write_data_r <= {(DATA_BITS*OUT_FEATURES){1'b0}};
        end else begin
            mp_buf0_edge_write_start_r <= mp_edge_buf0_we;
            if (mp_edge_buf0_we) begin
                mp_buf0_edge_write_addr_r <= mp_edge_address;
                mp_buf0_edge_write_data_r <= mp_edge_output_kept;
            end

            mp_buf1_edge_write_start_r <= mp_edge_buf1_we;
            if (mp_edge_buf1_we) begin
                mp_buf1_edge_write_addr_r <= mp_edge_address;
                mp_buf1_edge_write_data_r <= mp_edge_output_kept;
            end
        end
    end

    // Output assignments
    assign processing_done = (phase_state == PHASE_DONE);
    assign current_phase = phase_state;
    
    // ===============================
    // Encoder to Storage Connections
    // ===============================
    assign encoder_edge_write_start = edge_valid;
    assign encoder_edge_write_addr = edge_addr_out * OUT_FEATURES;
    
    assign buf0_edge_write_start = mp_buf0_edge_write_start_r || edge_valid;
    assign buf0_edge_write_addr = mp_buf0_edge_write_start_r ? mp_buf0_edge_write_addr_r : edge_addr_out * OUT_FEATURES;
    
    assign encoder_node_write_start = node_valid;
    assign encoder_node_write_addr = node_addr_out * OUT_FEATURES;
    
    assign buf0_node_write_start = mp_node_buf0_we || node_valid;
    assign buf0_node_write_addr = mp_node_buf0_we ? mp_node_address : node_addr_out * OUT_FEATURES;
    
    // ===============================
    // Message Passing to Storage Connections
    // ===============================
    assign encoder_edge_read_start = mp_initial_edge_features_re;
    assign encoder_edge_read_addr = mp_load_edge_address;
    
    assign buf0_edge_read_start = mp_edge_buf0_re || edge_features_re;
    assign buf0_edge_read_addr = mp_edge_buf0_re ? mp_load_edge_address : dec_edge_addr_out * OUT_FEATURES;
    
    assign buf1_edge_read_start = mp_edge_buf1_re;
    assign buf1_edge_read_addr = mp_load_edge_address;
    
    assign encoder_node_read_start = mp_initial_node_features_edge_re_sel || mp_initial_node_features_node_re_sel;
    assign encoder_node_read_addr = mp_initial_node_features_edge_re_sel ? mp_edge_net_node_index : mp_node_address;
    
    assign buf0_node_read_start = mp_node_buf0_re_edge_sel || mp_node_buf0_re_node_sel;
    assign buf0_node_read_addr = mp_node_buf0_re_edge_sel ? mp_edge_net_node_index : mp_node_address;
    
    assign buf1_node_read_start = mp_node_buf1_re_edge_sel || mp_node_buf1_re_node_sel;
    assign buf1_node_read_addr = mp_node_buf1_re_edge_sel ? mp_edge_net_node_index : mp_node_address;
    
    assign connectivity_src_re = mp_source_node_index_re;
    assign connectivity_src_addr = mp_edge_index;
    
    assign connectivity_dst_re = mp_destination_node_index_re;
    assign connectivity_dst_addr = mp_edge_index;
    
    // Scatter-sum writes
    assign in_ss_node_write_start = mp_scatter_sum_we;
    assign in_ss_node_write_addr = mp_in_node_index_ss;
    assign in_ss_node_write_data = {224'b0, mp_edge_output};
    
    assign out_ss_node_write_start = mp_scatter_sum_we;
    assign out_ss_node_write_addr = mp_out_node_index_ss;
    assign out_ss_node_write_data = {224'b0, mp_edge_output};
    
    // Scatter-sum reads
    assign in_ss_node_read_start = mp_scatter_sum_features_in_re;
    assign in_ss_node_read_addr = mp_node_address;
    
    assign out_ss_node_read_start = mp_scatter_sum_features_out_re;
    assign out_ss_node_read_addr = mp_node_address;
    
    // Buffer writes
    assign buf1_edge_write_start = mp_buf1_edge_write_start_r;
    assign buf1_edge_write_addr = mp_buf1_edge_write_addr_r;
    
    assign buf1_node_write_start = mp_node_buf1_we;
    assign buf1_node_write_addr = mp_node_address;
    
    // ===============================
    // Module Instantiations
    // ===============================
    
    // Edge Encoder
    edge_encoder #(
        .NUM_EDGES(NUM_EDGES),
        .NUM_FEATURES(6),
        .DATA_BITS(DATA_BITS),
        .USE_RMS_NORM(USE_RMS_NORM),
        .OUT_FEATURES(OUT_FEATURES),
        .ADDR_BITS(ADDR_BITS),
        .MEM_FILE("edge_initial_features.mem")
    ) edge_enc (
        .clk(clk),
        .rstn(rstn),
        .start(edge_start),
        .active_num_edges(active_num_edges),
        .encoded_data(edge_data_out),
        .edge_addr_out(edge_addr_out),
        .data_valid(edge_valid),
        .done(edge_done)
    );
    
    // Node Encoder
    node_encoder #(
        .NUM_NODES(NUM_NODES),
        .NUM_FEATURES(12),
        .DATA_BITS(DATA_BITS),
        .USE_RMS_NORM(USE_RMS_NORM),
        .WEIGHT_BITS(8),
        .BIAS_BITS(8),
        .ADDR_BITS(NODE_ADDR_BITS),
        .OUT_FEATURES(32),
        .MEM_FILE("node_initial_features.mem")
    ) node_enc (
        .clk(clk),
        .rstn(rstn),
        .start(node_start),
        .active_num_nodes(active_num_nodes),
        .encoded_data(node_data_out),
        .node_addr_out(node_addr_out),
        .data_valid(node_valid),
        .done(node_done)
    );
    
    // Storage Module
    storage_module #(
        .DATA_BITS(DATA_BITS),
        .RAM_ADDR_BITS_FOR_NODE(NODE_ADDR_BITS+FEATURE_BITS),  // Use more address bits to accommodate feature indexing
        .RAM_ADDR_BITS_FOR_EDGE(ADDR_BITS+FEATURE_BITS),  // Use more address bits to accommodate feature indexing
        .NUM_NODES(NUM_NODES),
        .NUM_EDGES(NUM_EDGES),
        .NUM_FEATURES(OUT_FEATURES),
        .MAX_BURST_SIZE(MAX_BURST_SIZE)
    ) storage (
        .clk(clk),
        .rst(rst),
        
        // Edge Encoder BRAM
        .encoder_edge_write_start(encoder_edge_write_start),
        .encoder_edge_write_addr_base(encoder_edge_write_addr),
        .encoder_edge_write_burst_size(6'd32),
        .encoder_edge_write_data(edge_data_out),
        .encoder_edge_write_done(encoder_edge_write_done),
        .encoder_edge_write_busy(),
        
        .encoder_edge_read_start(encoder_edge_read_start),
        .encoder_edge_read_addr_base(encoder_edge_read_addr),
        .encoder_edge_read_burst_size(6'd32),
        .encoder_edge_read_data(encoder_edge_read_data),
        .encoder_edge_read_valid(encoder_edge_read_valid),
        .encoder_edge_read_busy(),
        
        // Node Encoder BRAM
        .encoder_node_write_start(encoder_node_write_start),
        .encoder_node_write_addr_base(encoder_node_write_addr),
        .encoder_node_write_burst_size(6'd32),
        .encoder_node_write_data(node_data_out),
        .encoder_node_write_done(encoder_node_write_done),
        .encoder_node_write_busy(),
        
        .encoder_node_read_start(encoder_node_read_start),
        .encoder_node_read_addr_base(encoder_node_read_addr),
        .encoder_node_read_burst_size(6'd32),
        .encoder_node_read_data(encoder_node_read_data),
        .encoder_node_read_valid(encoder_node_read_valid),
        .encoder_node_read_busy(),
        
        // Connectivity BRAMs
        .connectivity_src_re(connectivity_src_re),
        .connectivity_src_addr(connectivity_src_addr),
        .connectivity_src_data(connectivity_src_data),
        
        .connectivity_dst_re(connectivity_dst_re),
        .connectivity_dst_addr(connectivity_dst_addr),
        .connectivity_dst_data(connectivity_dst_data),
        
        // Buffer0 Edge
        .buf0_edge_write_start(buf0_edge_write_start),
        .buf0_edge_write_addr_base(buf0_edge_write_addr),
        .buf0_edge_write_burst_size(6'd32),
        .buf0_edge_write_data(encoder_edge_write_start ? edge_data_out_kept : mp_buf0_edge_write_data_r),
        .buf0_edge_write_done(buf0_edge_write_done),
        .buf0_edge_write_busy(),
        
        .buf0_edge_read_start(buf0_edge_read_start),
        .buf0_edge_read_addr_base(buf0_edge_read_addr),
        .buf0_edge_read_burst_size(6'd32),
        .buf0_edge_read_data(buf0_edge_read_data),
        .buf0_edge_read_valid(buf0_edge_read_valid),
        .buf0_edge_read_busy(),
        
        // Buffer1 Edge
        .buf1_edge_write_start(buf1_edge_write_start),
        .buf1_edge_write_addr_base(buf1_edge_write_addr),
        .buf1_edge_write_burst_size(6'd32),
        .buf1_edge_write_data(mp_buf1_edge_write_data_r),
        .buf1_edge_write_done(buf1_edge_write_done),
        .buf1_edge_write_busy(),
        
        .buf1_edge_read_start(buf1_edge_read_start),
        .buf1_edge_read_addr_base(buf1_edge_read_addr),
        .buf1_edge_read_burst_size(6'd32),
        .buf1_edge_read_data(buf1_edge_read_data),
        .buf1_edge_read_valid(buf1_edge_read_valid),
        .buf1_edge_read_busy(),
        
        // Buffer0 Node
        .buf0_node_write_start(buf0_node_write_start),
        .buf0_node_write_addr_base(buf0_node_write_addr),
        .buf0_node_write_burst_size(6'd32),
        .buf0_node_write_data(encoder_node_write_start ? node_data_out_kept : mp_node_output_kept),
        .buf0_node_write_done(buf0_node_write_done),
        .buf0_node_write_busy(),
        
        .buf0_node_read_start(buf0_node_read_start),
        .buf0_node_read_addr_base(buf0_node_read_addr),
        .buf0_node_read_burst_size(6'd32),
        .buf0_node_read_data(buf0_node_read_data),
        .buf0_node_read_valid(buf0_node_read_valid),
        .buf0_node_read_busy(),
        
        // Buffer1 Node
        .buf1_node_write_start(buf1_node_write_start),
        .buf1_node_write_addr_base(buf1_node_write_addr),
        .buf1_node_write_burst_size(6'd32),
        .buf1_node_write_data(mp_node_output_kept),
        .buf1_node_write_done(buf1_node_write_done),
        .buf1_node_write_busy(),
        
        .buf1_node_read_start(buf1_node_read_start),
        .buf1_node_read_addr_base(buf1_node_read_addr),
        .buf1_node_read_burst_size(6'd32),
        .buf1_node_read_data(buf1_node_read_data),
        .buf1_node_read_valid(buf1_node_read_valid),
        .buf1_node_read_busy(),
        
        // Scatter-Sum In
        .in_ss_node_write_start(in_ss_node_write_start),
        .in_ss_node_write_addr_base(in_ss_node_write_addr),
        .in_ss_node_write_burst_size(6'd32),
        .in_ss_node_write_data(in_ss_node_write_data),
        .in_ss_node_write_done(in_ss_node_write_done),
        .in_ss_node_write_busy(),
        
        .in_ss_node_read_start(in_ss_node_read_start),
        .in_ss_node_read_addr_base(in_ss_node_read_addr),
        .in_ss_node_read_burst_size(6'd32),
        .in_ss_node_read_data(in_ss_node_read_data),
        .in_ss_node_read_valid(in_ss_node_read_valid),
        .in_ss_node_read_busy(),
        
        // Scatter-Sum Out
        .out_ss_node_write_start(out_ss_node_write_start),
        .out_ss_node_write_addr_base(out_ss_node_write_addr),
        .out_ss_node_write_burst_size(6'd32),
        .out_ss_node_write_data(out_ss_node_write_data),
        .out_ss_node_write_done(out_ss_node_write_done),
        .out_ss_node_write_busy(),
        
        .out_ss_node_read_start(out_ss_node_read_start),
        .out_ss_node_read_addr_base(out_ss_node_read_addr),
        .out_ss_node_read_burst_size(6'd32),
        .out_ss_node_read_data(out_ss_node_read_data),
        .out_ss_node_read_valid(out_ss_node_read_valid),
        .out_ss_node_read_busy(),
        
        // Edge Score BRAM
        .edge_score_write_start(dec_data_valid),
        .edge_score_write_addr_base(dec_edge_addr_out),
        .edge_score_write_burst_size(1'd1),
        .edge_score_write_data(dec_data_out_kept),
        .edge_score_write_done(),
        .edge_score_write_busy(),
        
        .edge_score_read_start(1'b0),
        .edge_score_read_addr_base({ADDR_BITS{1'b0}}),
        .edge_score_read_burst_size(1'd1),
        .edge_score_read_data(),
        .edge_score_read_valid(),
        .edge_score_read_busy()
    );
    
    // Message Passing Wrapper
    message_passing_wrapper #(
        .DATA_BITS(DATA_BITS),
        .USE_RMS_NORM(USE_RMS_NORM),
        .RAM_ADDR_BITS_FOR_NODE(NODE_ADDR_BITS+FEATURE_BITS),
        .RAM_ADDR_BITS_FOR_EDGE(ADDR_BITS+FEATURE_BITS),
        .NODE_FEATURES(OUT_FEATURES),
        .EDGE_FEATURES(OUT_FEATURES),
        .MAX_EDGES(NUM_EDGES),
        .MAX_NODES(NUM_NODES)
    ) mp_wrapper (
        .clk(clk),
        .rstn(rstn),
        .start(mp_start),
        .active_num_edges(active_num_edges),
        .active_num_nodes(active_num_nodes),
        .done(mp_done),
        
        // Edge Network - Initial Edge Features
        .initial_edge_features(encoder_edge_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .initial_edge_features_re(mp_initial_edge_features_re),
        .initial_edge_features_valid(encoder_edge_read_valid),
        
        // Edge Network - Edge Buffer 0
        .edge_buf0_read_data(buf0_edge_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .edge_buf0_re(mp_edge_buf0_re),
        .edge_buf0_read_valid(buf0_edge_read_valid),
        .edge_buf0_we(mp_edge_buf0_we),
        .edge_buf0_write_done(buf0_edge_write_done),
        
        // Edge Network - Edge Buffer 1
        .edge_buf1_read_data(buf1_edge_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .edge_buf1_re(mp_edge_buf1_re),
        .edge_buf1_read_valid(buf1_edge_read_valid),
        .edge_buf1_we(mp_edge_buf1_we),
        .edge_buf1_write_done(buf1_edge_write_done),
        
        // Edge Network - Initial Node Features
        .initial_node_features_edge(encoder_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .initial_node_features_edge_re(mp_initial_node_features_edge_re),
        .initial_node_features_edge_valid(encoder_node_read_valid),
        
        // Edge Network - Node Buffer 0
        .node_buf0_read_data_edge(buf0_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .node_buf0_re_edge(mp_node_buf0_re_edge),
        .node_buf0_read_valid_edge(buf0_node_read_valid),
        
        // Edge Network - Node Buffer 1
        .node_buf1_read_data_edge(buf1_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .node_buf1_re_edge(mp_node_buf1_re_edge),
        .node_buf1_read_valid_edge(buf1_node_read_valid),
        
        // Edge Network - Connectivity
        .source_node_index(connectivity_src_data_ext),
        .source_node_index_re(mp_source_node_index_re),
        .source_node_index_valid(connectivity_src_valid),
        
        .destination_node_index(connectivity_dst_data_ext),
        .destination_node_index_re(mp_destination_node_index_re),
        .destination_node_index_valid(connectivity_dst_valid),
        
        // Edge Network - Outputs
        .edge_address(mp_edge_address),
        .load_edge_address(mp_load_edge_address),
        .edge_index(mp_edge_index),
        .in_node_index_ss(mp_in_node_index_ss),
        .in_node_ss_write_done(in_ss_node_write_done),
        .out_node_index_ss(mp_out_node_index_ss),
        .scatter_sum_we(mp_scatter_sum_we),
        .out_node_ss_write_done(out_ss_node_write_done),
        .edge_net_node_index(mp_edge_net_node_index),
        .edge_output(mp_edge_output),
        
        // Node Network - Scatter-sum features
        .scatter_sum_features_in(in_ss_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .scatter_sum_features_in_re(mp_scatter_sum_features_in_re),
        .scatter_sum_features_in_valid(in_ss_node_read_valid),
        .scatter_sum_features_in_write_done(in_ss_node_write_done),
        
        .scatter_sum_features_out(out_ss_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .scatter_sum_features_out_re(mp_scatter_sum_features_out_re),
        .scatter_sum_features_out_valid(out_ss_node_read_valid),
        .scatter_sum_features_out_write_done(out_ss_node_write_done),
        
        // Node Network - Node Buffer 0
        .node_buf0_read_data_node(buf0_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .node_buf0_re_node(mp_node_buf0_re_node),
        .node_buf0_read_valid_node(buf0_node_read_valid),
        .node_buf0_we(mp_node_buf0_we),
        .node_buf0_write_done(buf0_node_write_done),
        
        // Node Network - Node Buffer 1
        .node_buf1_read_data_node(buf1_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .node_buf1_re_node(mp_node_buf1_re_node),
        .node_buf1_read_valid_node(buf1_node_read_valid),
        .node_buf1_we(mp_node_buf1_we),
        .node_buf1_write_done(buf1_node_write_done),
        
        // Node Network - Initial Node Features
        .initial_node_features_node(encoder_node_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .initial_node_features_node_re(mp_initial_node_features_node_re),
        .initial_node_features_node_valid(encoder_node_read_valid),
        
        // Node Network - Outputs
        .node_address(mp_node_address),
        .node_index(mp_node_index),
        .node_output(mp_node_output)
    );

    // Edge Decoder
    edge_decoder #(
        .NUM_EDGES(NUM_EDGES),
        .NUM_FEATURES(OUT_FEATURES),
        .DATA_BITS(DATA_BITS),
        .USE_RMS_NORM(USE_RMS_NORM),
        .OUT_FEATURES(OUT_FEATURES),
        .ADDR_BITS(ADDR_BITS),
        .WEIGHT_BITS(8),
        .BIAS_BITS(8)
    ) edge_dec (
        .clk(clk),
        .rstn(rstn),
        .start(dec_start),
        .active_num_edges(active_num_edges),
        .decoded_data(dec_data_out),
        .edge_addr_out(dec_edge_addr_out),
        .data_valid(dec_data_valid),
        .done(dec_done),
        .edge_features(buf0_edge_read_data[OUT_FEATURES*DATA_BITS-1:0]),
        .edge_features_re(edge_features_re),
        .edge_features_valid(buf0_edge_read_valid)
    );

endmodule
