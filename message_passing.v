`timescale 1ns / 1ps

module Message_Passing #(
    parameter BLOCK_NUM = 0,
    parameter DATA_BITS = 8,
    parameter USE_RMS_NORM = 1,
    parameter RAM_ADDR_BITS_FOR_NODE = 18,
    parameter RAM_ADDR_BITS_FOR_EDGE = 14,
    parameter NODE_FEATURES = 32,
    parameter EDGE_FEATURES = 32,
    parameter MAX_EDGES = 4,
    parameter MAX_NODES = 5
) (
    input clk,
    input rstn,
    input start,
    input [RAM_ADDR_BITS_FOR_EDGE-6:0] active_num_edges,
    input [RAM_ADDR_BITS_FOR_NODE-6:0] active_num_nodes,
    output reg done,
    
    // Edge Network - Initial Edge Features from Edge Encoder
    input  [DATA_BITS*EDGE_FEATURES-1:0] initial_edge_features,
    output initial_edge_features_re,
    input  initial_edge_features_valid,
    
    // Edge Network - Edge PingPong Buffer 0
    input  [DATA_BITS*EDGE_FEATURES-1:0] edge_buf0_read_data,
    output edge_buf0_re,
    input  edge_buf0_read_valid,
    output edge_buf0_we,
    input  edge_buf0_write_done,
    
    // Edge Network - Edge PingPong Buffer 1
    input  [DATA_BITS*EDGE_FEATURES-1:0] edge_buf1_read_data,
    output edge_buf1_re,
    input  edge_buf1_read_valid,
    output edge_buf1_we,
    input  edge_buf1_write_done,
    
    // Edge Network - Initial Node features from Node Encoder BRAM
    input  [DATA_BITS*NODE_FEATURES-1:0] initial_node_features_edge,
    output initial_node_features_edge_re,
    input  initial_node_features_edge_valid,
    
    // Edge Network - Node PingPong Buffer 0
    input  [DATA_BITS*NODE_FEATURES-1:0] node_buf0_read_data_edge,
    output node_buf0_re_edge,
    input  node_buf0_read_valid_edge,
    
    // Edge Network - Node PingPong Buffer 1
    input  [DATA_BITS*NODE_FEATURES-1:0] node_buf1_read_data_edge,
    output node_buf1_re_edge,
    input  node_buf1_read_valid_edge,
    
    // Edge Network - Source/Destination Node indices from Connectivity BRAMs
    input  [RAM_ADDR_BITS_FOR_NODE-1:0] source_node_index,
    output source_node_index_re,
    input  source_node_index_valid,
    
    input  [RAM_ADDR_BITS_FOR_NODE-1:0] destination_node_index,
    output destination_node_index_re,
    input  destination_node_index_valid,
    
    // Edge Network - Output Index for Edge Encoder BRAM
    output [RAM_ADDR_BITS_FOR_EDGE-1:0] edge_address,
    output [RAM_ADDR_BITS_FOR_EDGE-1:0] load_edge_address,
    output [RAM_ADDR_BITS_FOR_EDGE-6:0] edge_index,
    
    // Edge Network - Scatter Sum indices
    output [RAM_ADDR_BITS_FOR_NODE-1:0] in_node_index_ss,
    input  in_node_ss_write_done,
    output [RAM_ADDR_BITS_FOR_NODE-1:0] out_node_index_ss,
    output scatter_sum_we,
    input  out_node_ss_write_done,
    
    // Edge Network - Node index output
    output [RAM_ADDR_BITS_FOR_NODE-1:0] edge_net_node_index,
    
    // Edge Network - Edge output
    output [DATA_BITS*EDGE_FEATURES-1:0] edge_output,
    
    // Node Network - Scatter-sum features
    input  [DATA_BITS*NODE_FEATURES-1:0] scatter_sum_features_in,
    output scatter_sum_features_in_re,
    input  scatter_sum_features_in_valid,
    input scatter_sum_features_in_write_done,
    
    input  [DATA_BITS*NODE_FEATURES-1:0] scatter_sum_features_out,
    output scatter_sum_features_out_re,
    input  scatter_sum_features_out_valid,
    input scatter_sum_features_out_write_done,
    
    // Node Network - Node PingPong Buffer 0
    input  [DATA_BITS*NODE_FEATURES-1:0] node_buf0_read_data_node,
    output node_buf0_re_node,
    input  node_buf0_read_valid_node,
    output node_buf0_we,
    input  node_buf0_write_done,
    
    // Node Network - Node PingPong Buffer 1
    input  [DATA_BITS*NODE_FEATURES-1:0] node_buf1_read_data_node,
    output node_buf1_re_node,
    input  node_buf1_read_valid_node,
    output node_buf1_we,
    input  node_buf1_write_done,
    
    // Node Network - Initial Node features from Node Encoder BRAM
    input  [DATA_BITS*NODE_FEATURES-1:0] initial_node_features_node,
    output initial_node_features_node_re,
    input  initial_node_features_node_valid,
    
    // Node Network - Node addressing
    output [RAM_ADDR_BITS_FOR_NODE-1:0] node_address,
    output [RAM_ADDR_BITS_FOR_NODE-6:0] node_index,
    
    // Node Network - Node output
    output [DATA_BITS*NODE_FEATURES-1:0] node_output
);

    // Determine if BLOCK_NUM is even or odd
    localparam IS_EVEN = (BLOCK_NUM % 2 == 0);
    
    // FSM States
    localparam IDLE = 3'd0;
    localparam RUN_EDGE_NETWORK = 3'd1;
    localparam WAIT_EDGE_DONE = 3'd2;
    localparam RUN_NODE_NETWORK = 3'd3;
    localparam WAIT_NODE_DONE = 3'd4;
    localparam DONE = 3'd5;
    
    reg [2:0] state, next_state;
    
    // Pulse capture registers
    reg edge_done_captured;
    reg ss_in_done_captured;
    reg ss_out_done_captured;
    // Start pulses: each run state lasts one cycle, so these assert for one clock.
    wire edge_network_start;
    wire node_network_start;
    wire edge_network_done;
    wire node_network_done;
    wire edge_phase_active;
    wire node_phase_active;

    assign edge_network_start = (state == RUN_EDGE_NETWORK);
    assign node_network_start = (state == RUN_NODE_NETWORK);
    assign edge_phase_active = (state == RUN_EDGE_NETWORK) || (state == WAIT_EDGE_DONE);
    assign node_phase_active = (state == RUN_NODE_NETWORK) || (state == WAIT_NODE_DONE);

    // Capture pulses
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            edge_done_captured <= 0;
            ss_in_done_captured <= 0;
            ss_out_done_captured <= 0;
        end else begin
            // Capture each pulse
            if (edge_network_done)
                edge_done_captured <= 1;
            if (scatter_sum_features_in_write_done)
                ss_in_done_captured <= 1;
            if (scatter_sum_features_out_write_done)
                ss_out_done_captured <= 1;
                
            // Clear all when transitioning to next phase
            if (state == RUN_NODE_NETWORK) begin
                edge_done_captured <= 0;
                ss_in_done_captured <= 0;
                ss_out_done_captured <= 0;
            end
        end
    end
    
    
    
    // Internal signals for Edge Network
    wire [DATA_BITS*EDGE_FEATURES-1:0] current_edge_features;
    wire current_edge_features_re;
    wire current_edge_features_valid;
    wire current_edge_features_we;
    wire current_edge_features_write_done;
    
    wire [DATA_BITS*NODE_FEATURES-1:0] current_node_features_edge;
    wire current_node_features_edge_re;
    wire current_node_features_edge_valid;
    
    // Internal signals for Node Network
    wire [DATA_BITS*NODE_FEATURES-1:0] current_node_features_node;
    wire current_node_features_node_re;
    wire current_node_features_node_valid;
    wire current_node_features_node_we;
    wire current_node_features_node_write_done;
    
    // ========== EDGE NETWORK PING-PONG MUX ==========
    // Even: Read from buf0, Write to buf1
    // Odd:  Read from buf1, Write to buf0
    
    assign current_edge_features = IS_EVEN ? edge_buf0_read_data : edge_buf1_read_data;
    assign current_edge_features_valid = IS_EVEN ? edge_buf0_read_valid : edge_buf1_read_valid;
    assign current_edge_features_write_done = IS_EVEN ? edge_buf1_write_done : edge_buf0_write_done;
    
    assign edge_buf0_re = edge_phase_active && (IS_EVEN ? current_edge_features_re : 1'b0);
    assign edge_buf1_re = edge_phase_active && (IS_EVEN ? 1'b0 : current_edge_features_re);
    
    assign edge_buf0_we = edge_phase_active && (IS_EVEN ? 1'b0 : current_edge_features_we);
    assign edge_buf1_we = edge_phase_active && (IS_EVEN ? current_edge_features_we : 1'b0);
    
    // Edge Network reads current node features
    assign current_node_features_edge = IS_EVEN ? node_buf0_read_data_edge : node_buf1_read_data_edge;
    assign current_node_features_edge_valid = IS_EVEN ? node_buf0_read_valid_edge : node_buf1_read_valid_edge;
    
    assign node_buf0_re_edge = edge_phase_active && (IS_EVEN ? current_node_features_edge_re : 1'b0);
    assign node_buf1_re_edge = edge_phase_active && (IS_EVEN ? 1'b0 : current_node_features_edge_re);
    
    // ========== NODE NETWORK PING-PONG MUX ==========
    // Even: Read from buf0, Write to buf1
    // Odd:  Read from buf1, Write to buf0
    
    assign current_node_features_node = IS_EVEN ? node_buf0_read_data_node : node_buf1_read_data_node;
    assign current_node_features_node_valid = IS_EVEN ? node_buf0_read_valid_node : node_buf1_read_valid_node;
    assign current_node_features_node_write_done = IS_EVEN ? node_buf1_write_done : node_buf0_write_done;
    
    assign node_buf0_re_node = node_phase_active && (IS_EVEN ? current_node_features_node_re : 1'b0);
    assign node_buf1_re_node = node_phase_active && (IS_EVEN ? 1'b0 : current_node_features_node_re);
    
    assign node_buf0_we = node_phase_active && (IS_EVEN ? 1'b0 : current_node_features_node_we);
    assign node_buf1_we = node_phase_active && (IS_EVEN ? current_node_features_node_we : 1'b0);
    
    // State register
    always @(posedge clk or negedge rstn) begin
        if (!rstn)
            state <= IDLE;
        else
            state <= next_state;
    end
    
    // Next state logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start)
                    next_state = RUN_EDGE_NETWORK;
            end
            
            RUN_EDGE_NETWORK: begin
                next_state = WAIT_EDGE_DONE;
            end
            
            WAIT_EDGE_DONE: begin
                if (edge_done_captured && ss_in_done_captured && ss_out_done_captured) begin
                    // Last block (BLOCK_NUM == 7): node embeddings are never read again,
                    // skip Node_Network entirely and go straight to DONE.
                    if (BLOCK_NUM == 7)
                        next_state = DONE;
                    else
                        next_state = RUN_NODE_NETWORK;
                end
            end
            
            RUN_NODE_NETWORK: begin
                next_state = WAIT_NODE_DONE;
            end
            
            WAIT_NODE_DONE: begin
                if (node_network_done)
                    next_state = DONE;
            end
            
            DONE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Output logic
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                end
                
                RUN_EDGE_NETWORK: begin
                    done <= 0;
                    // $display("[%0t] Message_Passing Block %0d: Starting Edge Network (Read: buf%0d, Write: buf%0d)", 
//                             $time, BLOCK_NUM, IS_EVEN ? 0 : 1, IS_EVEN ? 1 : 0);
                end
                
                WAIT_EDGE_DONE: begin
                    if (edge_done_captured && ss_in_done_captured && ss_out_done_captured) begin
                        // $display("[%0t] Message_Passing Block %0d: Edge Network completed", $time, BLOCK_NUM);
                    end
                end
                
                RUN_NODE_NETWORK: begin
                    done <= 0;
                end
                
                WAIT_NODE_DONE: begin
                    if (node_network_done) begin
                        // $display("[%0t] Message_Passing Block %0d: Node Network completed", $time, BLOCK_NUM);
                    end
                end
                
                DONE: begin
                    done <= 1;
                    // $display("[%0t] Message_Passing Block %0d: Complete", $time, BLOCK_NUM);
                end
                
                default: begin
                    done <= 0;
                end
            endcase
        end
    end
    
    // Instantiate Edge Network
    Edge_Network #(
        .BLOCK_NUM(BLOCK_NUM),
        .DATA_BITS(DATA_BITS),
        .USE_RMS_NORM(USE_RMS_NORM),
        .RAM_ADDR_BITS_FOR_NODE(RAM_ADDR_BITS_FOR_NODE),
        .RAM_ADDR_BITS_FOR_EDGE(RAM_ADDR_BITS_FOR_EDGE),
        .NODE_FEATURES(NODE_FEATURES),
        .EDGE_FEATURES(EDGE_FEATURES),
        .MAX_EDGES(MAX_EDGES)
    ) edge_network (
        .clk(clk),
        .rstn(rstn),
        .start(edge_network_start),
        .active_num_edges(active_num_edges),
        
        .initial_edge_features(initial_edge_features),
        .initial_edge_features_re(initial_edge_features_re),
        .initial_edge_features_valid(initial_edge_features_valid),
        
        .current_edge_features(current_edge_features),
        .current_edge_features_re(current_edge_features_re),
        .current_edge_features_valid(current_edge_features_valid),
        .current_edge_features_we(current_edge_features_we),
        .current_edge_features_write_done(current_edge_features_write_done),
        
        .initial_node_features(initial_node_features_edge),
        .initial_node_features_re(initial_node_features_edge_re),
        .initial_node_features_valid(initial_node_features_edge_valid),
        
        .current_node_features(current_node_features_edge),
        .current_node_features_re(current_node_features_edge_re),
        .current_node_features_valid(current_node_features_edge_valid),
        
        .source_node_index(source_node_index),
        .source_node_index_re(source_node_index_re),
        .source_node_index_valid(source_node_index_valid),
        
        .destination_node_index(destination_node_index),
        .destination_node_index_re(destination_node_index_re),
        .destination_node_index_valid(destination_node_index_valid),
        
        .edge_address(edge_address),
        .load_edge_address(load_edge_address), 
        .edge_index(edge_index),
        .in_node_index_ss(in_node_index_ss),
        .in_node_ss_write_done(in_node_ss_write_done),
        .out_node_index_ss(out_node_index_ss),
        .scatter_sum_we(scatter_sum_we),
        .out_node_ss_write_done(out_node_ss_write_done),
        .node_index(edge_net_node_index),
        .edge_output(edge_output),
        .done(edge_network_done)
    );
    
    // Instantiate Node Network
    Node_Network #(
        .BLOCK_NUM(BLOCK_NUM),
        .DATA_BITS(DATA_BITS),
        .USE_RMS_NORM(USE_RMS_NORM),
        .RAM_ADDR_BITS_FOR_NODE(RAM_ADDR_BITS_FOR_NODE),
        .NODE_FEATURES(NODE_FEATURES),
        .MAX_NODES(MAX_NODES)
    ) node_network (
        .clk(clk),
        .rstn(rstn),
        .start(node_network_start),
        .active_num_nodes(active_num_nodes),
        
        .scatter_sum_features_in(scatter_sum_features_in),
        .scatter_sum_features_in_re(scatter_sum_features_in_re),
        .scatter_sum_features_in_valid(scatter_sum_features_in_valid),
        
        .scatter_sum_features_out(scatter_sum_features_out),
        .scatter_sum_features_out_re(scatter_sum_features_out_re),
        .scatter_sum_features_out_valid(scatter_sum_features_out_valid),
        
        .current_node_features(current_node_features_node),
        .current_node_features_re(current_node_features_node_re),
        .current_node_features_valid(current_node_features_node_valid),
        .current_node_features_we(current_node_features_node_we),
        .current_node_features_write_done(current_node_features_node_write_done),
        
        .initial_node_features(initial_node_features_node),
        .initial_node_features_re(initial_node_features_node_re),
        .initial_node_features_valid(initial_node_features_node_valid),
        
        .node_address(node_address),
        .node_index(node_index),
        .node_output(node_output),
        .done(node_network_done)
    );

endmodule
