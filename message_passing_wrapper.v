`timescale 1ns / 1ps

module message_passing_wrapper #(
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

    //============================================
    // State Machine for Sequential Block Execution
    //============================================
    // localparam IDLE = 4'b0000;
    // localparam BLOCK0 = 4'b0001;
    // localparam BLOCK1 = 4'b0010;
    // localparam BLOCK2 = 4'b0011;
    // localparam BLOCK3 = 4'b0100;
    // localparam BLOCK4 = 4'b0101;
    // localparam BLOCK5 = 4'b0110;
    // localparam BLOCK6 = 4'b0111;
    // localparam BLOCK7 = 4'b1000;
    // localparam DONE_STATE = 4'b1001;
    
    // reg [3:0] state, next_state;
    
    //============================================
    // Internal Signals for Each Block
    //============================================
    reg [7:0] block_start;
    wire [7:0] block_done;
    
    //============================================
    // State Register
    //============================================
    // always @(posedge clk or negedge rstn) begin
    //     if (!rstn)
    //         state <= IDLE;
    //     else
    //         state <= next_state;
    // end
    
    // //============================================
    // // Next State Logic
    // //============================================
    // always @(*) begin
    //     next_state = state;
    //     case (state)
    //         IDLE: begin
    //             if (start)
    //                 next_state = BLOCK0;
    //         end
            
    //         BLOCK0: begin
    //             if (block_done[0])
    //                 next_state = BLOCK1;
    //         end
            
    //         BLOCK1: begin
    //             if (block_done[1])
    //                 next_state = BLOCK2;
    //         end
            
    //         BLOCK2: begin
    //             if (block_done[2])
    //                 next_state = BLOCK3;
    //         end
            
    //         BLOCK3: begin
    //             if (block_done[3])
    //                 next_state = BLOCK4;
    //         end
            
    //         BLOCK4: begin
    //             if (block_done[4])
    //                 next_state = BLOCK5;
    //         end
            
    //         BLOCK5: begin
    //             if (block_done[5])
    //                 next_state = BLOCK6;
    //         end
            
    //         BLOCK6: begin
    //             if (block_done[6])
    //                 next_state = BLOCK7;
    //         end
            
    //         BLOCK7: begin
    //             if (block_done[7])
    //                 next_state = DONE_STATE;
    //         end
            
    //         DONE_STATE: begin
    //             next_state = IDLE;
    //         end
            
    //         default: next_state = IDLE;
    //     endcase
    // end
    
    //============================================
    // Block Start Signals
    //============================================
    // assign block_start[0] = (state == BLOCK0);
    // assign block_start[1] = (state == BLOCK1);
    // assign block_start[2] = (state == BLOCK2);
    // assign block_start[3] = (state == BLOCK3);
    // assign block_start[4] = (state == BLOCK4);
    // assign block_start[5] = (state == BLOCK5);
    // assign block_start[6] = (state == BLOCK6);
    // assign block_start[7] = (state == BLOCK7);
    
    //============================================
    // Done Signal
    //============================================
    // always @(posedge clk or negedge rstn) begin
    //     if (!rstn)
    //         done <= 1'b0;
    //     else
    //         done <= (state == DONE_STATE);
    // end
    
    //============================================
    // Instantiate 8 Message Passing Blocks
    // 
    // IMPORTANT NOTE ON WRITE_DONE SIGNALS:
    // The in_node_ss_write_done, out_node_ss_write_done, 
    // scatter_sum_features_in_write_done, and scatter_sum_features_out_write_done
    // signals are connected to all blocks simultaneously. Each Message_Passing
    // block contains internal capture registers that hold these pulse signals
    // until all required conditions (edge_network_done, ss_in_done, ss_out_done)
    // are met before transitioning to the next state.
    //
    // The pulse capture logic in Message_Passing module:
    // - Captures write_done pulses when they arrive
    // - Holds them as sticky bits until cleared
    // - Clears them when transitioning to RUN_NODE_NETWORK state
    // This ensures proper synchronization even when pulses arrive at different times.
    //============================================
    
    // Internal wires for each block
    wire [7:0] block_initial_edge_features_re;
    wire [7:0] block_edge_buf0_re;
    wire [7:0] block_edge_buf0_we;
    wire [7:0] block_edge_buf1_re;
    wire [7:0] block_edge_buf1_we;
    wire [7:0] block_initial_node_features_edge_re;
    wire [7:0] block_node_buf0_re_edge;
    wire [7:0] block_node_buf1_re_edge;
    wire [7:0] block_source_node_index_re;
    wire [7:0] block_destination_node_index_re;
    wire [RAM_ADDR_BITS_FOR_EDGE-1:0] block_edge_address [0:7];
    wire [RAM_ADDR_BITS_FOR_EDGE-1:0] block_load_edge_address [0:7];
    wire [RAM_ADDR_BITS_FOR_EDGE-6:0] block_edge_index [0:7];
    wire [RAM_ADDR_BITS_FOR_NODE-1:0] block_in_node_index_ss [0:7];
    wire [RAM_ADDR_BITS_FOR_NODE-1:0] block_out_node_index_ss [0:7];
    wire [7:0] block_scatter_sum_we;
    wire [RAM_ADDR_BITS_FOR_NODE-1:0] block_edge_net_node_index [0:7];
    wire [DATA_BITS*EDGE_FEATURES-1:0] block_edge_output [0:7];
    wire [7:0] block_scatter_sum_features_in_re;
    wire [7:0] block_scatter_sum_features_out_re;
    wire [7:0] block_node_buf0_re_node;
    wire [7:0] block_node_buf0_we;
    wire [7:0] block_node_buf1_re_node;
    wire [7:0] block_node_buf1_we;
    wire [7:0] block_initial_node_features_node_re;
    wire [RAM_ADDR_BITS_FOR_NODE-1:0] block_node_address [0:7];
    wire [RAM_ADDR_BITS_FOR_NODE-6:0] block_node_index [0:7];
    wire [DATA_BITS*NODE_FEATURES-1:0] block_node_output [0:7];
    reg [3:0] current_block;
    
    // Sequential block execution control
    integer j;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (j = 0; j < 8; j = j + 1) begin
                block_start[j] <= 0;
            end
            current_block <= 0;
            done <= 0;
        end else begin
            if (start && current_block == 0 && !block_start[0]) begin
                block_start[0] <= 1;
                // $display("[%0t] Message_Passing_Wrapper: Starting Block 0", $time);
            end
            else if (block_start[current_block]) begin
                block_start[current_block] <= 0;
            end
            
            if (current_block < 8 && block_done[current_block]) begin
                // $display("[%0t] Message_Passing_Wrapper: Block %0d completed", $time, current_block);
                
                if (current_block < 8 - 1) begin
                    current_block <= current_block + 1;
                    block_start[current_block + 1] <= 1;
                    // $display("[%0t] Message_Passing_Wrapper: Starting Block %0d", $time, current_block + 1);
                end else begin
                    done <= 1;
                    // $display("[%0t] Message_Passing_Wrapper: All blocks completed", $time);
                end
            end
            
            if (!start && done) begin
                current_block <= 0;
                done <= 0;
            end
        end
    end
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : mp_blocks
            Message_Passing #(
                .BLOCK_NUM(i),
                .DATA_BITS(DATA_BITS),
                .USE_RMS_NORM(USE_RMS_NORM),
                .RAM_ADDR_BITS_FOR_NODE(RAM_ADDR_BITS_FOR_NODE),
                .RAM_ADDR_BITS_FOR_EDGE(RAM_ADDR_BITS_FOR_EDGE),
                .NODE_FEATURES(NODE_FEATURES),
                .EDGE_FEATURES(EDGE_FEATURES),
                .MAX_EDGES(MAX_EDGES),
                .MAX_NODES(MAX_NODES)
            ) mp_block (
                .clk(clk),
                .rstn(rstn),
                .start(block_start[i]),
                .active_num_edges(active_num_edges),
                .active_num_nodes(active_num_nodes),
                .done(block_done[i]),
                
                // Edge Network - Initial Edge Features
                .initial_edge_features(initial_edge_features),
                .initial_edge_features_re(block_initial_edge_features_re[i]),
                .initial_edge_features_valid(initial_edge_features_valid),
                
                // Edge Network - Edge PingPong Buffer 0
                .edge_buf0_read_data(edge_buf0_read_data),
                .edge_buf0_re(block_edge_buf0_re[i]),
                .edge_buf0_read_valid(edge_buf0_read_valid),
                .edge_buf0_we(block_edge_buf0_we[i]),
                .edge_buf0_write_done(edge_buf0_write_done),
                
                // Edge Network - Edge PingPong Buffer 1
                .edge_buf1_read_data(edge_buf1_read_data),
                .edge_buf1_re(block_edge_buf1_re[i]),
                .edge_buf1_read_valid(edge_buf1_read_valid),
                .edge_buf1_we(block_edge_buf1_we[i]),
                .edge_buf1_write_done(edge_buf1_write_done),
                
                // Edge Network - Initial Node Features
                .initial_node_features_edge(initial_node_features_edge),
                .initial_node_features_edge_re(block_initial_node_features_edge_re[i]),
                .initial_node_features_edge_valid(initial_node_features_edge_valid),
                
                // Edge Network - Node PingPong Buffer 0
                .node_buf0_read_data_edge(node_buf0_read_data_edge),
                .node_buf0_re_edge(block_node_buf0_re_edge[i]),
                .node_buf0_read_valid_edge(node_buf0_read_valid_edge),
                
                // Edge Network - Node PingPong Buffer 1
                .node_buf1_read_data_edge(node_buf1_read_data_edge),
                .node_buf1_re_edge(block_node_buf1_re_edge[i]),
                .node_buf1_read_valid_edge(node_buf1_read_valid_edge),
                
                // Edge Network - Connectivity
                .source_node_index(source_node_index),
                .source_node_index_re(block_source_node_index_re[i]),
                .source_node_index_valid(source_node_index_valid),
                
                .destination_node_index(destination_node_index),
                .destination_node_index_re(block_destination_node_index_re[i]),
                .destination_node_index_valid(destination_node_index_valid),
                
                // Edge Network - Outputs
                .edge_address(block_edge_address[i]),
                .load_edge_address(block_load_edge_address[i]),
                .edge_index(block_edge_index[i]),
                
                // Edge Network - Scatter-Sum indices
                .in_node_index_ss(block_in_node_index_ss[i]),
                .in_node_ss_write_done(in_node_ss_write_done),  // Shared pulse - captured internally
                .out_node_index_ss(block_out_node_index_ss[i]),
                .scatter_sum_we(block_scatter_sum_we[i]),
                .out_node_ss_write_done(out_node_ss_write_done),  // Shared pulse - captured internally
                
                // Edge Network - Node index output
                .edge_net_node_index(block_edge_net_node_index[i]),
                
                // Edge Network - Edge output
                .edge_output(block_edge_output[i]),
                
                // Node Network - Scatter-sum features
                .scatter_sum_features_in(scatter_sum_features_in),
                .scatter_sum_features_in_re(block_scatter_sum_features_in_re[i]),
                .scatter_sum_features_in_valid(scatter_sum_features_in_valid),
                .scatter_sum_features_in_write_done(scatter_sum_features_in_write_done),  // Shared pulse - captured internally
                
                .scatter_sum_features_out(scatter_sum_features_out),
                .scatter_sum_features_out_re(block_scatter_sum_features_out_re[i]),
                .scatter_sum_features_out_valid(scatter_sum_features_out_valid),
                .scatter_sum_features_out_write_done(scatter_sum_features_out_write_done),  // Shared pulse - captured internally
                
                // Node Network - Node PingPong Buffer 0
                .node_buf0_read_data_node(node_buf0_read_data_node),
                .node_buf0_re_node(block_node_buf0_re_node[i]),
                .node_buf0_read_valid_node(node_buf0_read_valid_node),
                .node_buf0_we(block_node_buf0_we[i]),
                .node_buf0_write_done(node_buf0_write_done),
                
                // Node Network - Node PingPong Buffer 1
                .node_buf1_read_data_node(node_buf1_read_data_node),
                .node_buf1_re_node(block_node_buf1_re_node[i]),
                .node_buf1_read_valid_node(node_buf1_read_valid_node),
                .node_buf1_we(block_node_buf1_we[i]),
                .node_buf1_write_done(node_buf1_write_done),
                
                // Node Network - Initial Node Features
                .initial_node_features_node(initial_node_features_node),
                .initial_node_features_node_re(block_initial_node_features_node_re[i]),
                .initial_node_features_node_valid(initial_node_features_node_valid),
                
                // Node Network - Outputs
                .node_address(block_node_address[i]),
                .node_index(block_node_index[i]),
                .node_output(block_node_output[i])
            );
        end
    endgenerate
    
    //============================================
    // MUX Logic for Shared Resources
    // Only the active block (determined by state) can access shared resources
    //============================================
    // Multiplex shared resources and outputs
    //============================================
// MUX Logic for Shared Resources
// Only the active block (determined by current_block) can access shared resources
//============================================
// Multiplex shared resources and outputs using continuous assignments
assign initial_edge_features_re = block_initial_edge_features_re[current_block];
assign edge_buf0_re = block_edge_buf0_re[current_block];
assign edge_buf0_we = block_edge_buf0_we[current_block];
assign edge_buf1_re = block_edge_buf1_re[current_block];
assign edge_buf1_we = block_edge_buf1_we[current_block];
assign initial_node_features_edge_re = block_initial_node_features_edge_re[current_block];
assign node_buf0_re_edge = block_node_buf0_re_edge[current_block];
assign node_buf1_re_edge = block_node_buf1_re_edge[current_block];
assign source_node_index_re = block_source_node_index_re[current_block];
assign destination_node_index_re = block_destination_node_index_re[current_block];
assign edge_address = block_edge_address[current_block];
assign load_edge_address = block_load_edge_address[current_block];
assign edge_index = block_edge_index[current_block];
assign in_node_index_ss = block_in_node_index_ss[current_block];
assign out_node_index_ss = block_out_node_index_ss[current_block];
assign scatter_sum_we = block_scatter_sum_we[current_block];
assign edge_net_node_index = block_edge_net_node_index[current_block];
assign edge_output = block_edge_output[current_block];
assign scatter_sum_features_in_re = block_scatter_sum_features_in_re[current_block];
assign scatter_sum_features_out_re = block_scatter_sum_features_out_re[current_block];
assign node_buf0_re_node = block_node_buf0_re_node[current_block];
assign node_buf0_we = block_node_buf0_we[current_block];
assign node_buf1_re_node = block_node_buf1_re_node[current_block];
assign node_buf1_we = block_node_buf1_we[current_block];
assign initial_node_features_node_re = block_initial_node_features_node_re[current_block];
assign node_address = block_node_address[current_block];
assign node_index = block_node_index[current_block];
assign node_output = block_node_output[current_block];
    // always @(*) begin
    //     initial_edge_features_re = block_initial_edge_features_re[current_block];
    //     edge_buf0_re = block_edge_buf0_re[current_block];
    //     edge_buf0_we = block_edge_buf0_we[current_block];
    //     edge_buf1_re = block_edge_buf1_re[current_block];
    //     edge_buf1_we = block_edge_buf1_we[current_block];
    //     initial_node_features_edge_re = block_initial_node_features_edge_re[current_block];
    //     node_buf0_re_edge = block_node_buf0_re_edge[current_block];
    //     node_buf1_re_edge = block_node_buf1_re_edge[current_block];
    //     source_node_index_re = block_source_node_index_re[current_block];
    //     destination_node_index_re = block_destination_node_index_re[current_block];
    //     edge_address = block_edge_address[current_block];
    //     edge_index = block_edge_index[current_block];
    //     in_node_index_ss = block_in_node_index_ss[current_block];
    //     out_node_index_ss = block_out_node_index_ss[current_block];
    //     scatter_sum_we = block_scatter_sum_we[current_block];
    //     edge_net_node_index = block_edge_net_node_index[current_block];
    //     edge_output = block_edge_output[current_block];
    //     scatter_sum_features_in_re = block_scatter_sum_features_in_re[current_block];
    //     scatter_sum_features_out_re = block_scatter_sum_features_out_re[current_block];
    //     node_buf0_re_node = block_node_buf0_re_node[current_block];
    //     node_buf0_we = block_node_buf0_we[current_block];
    //     node_buf1_re_node = block_node_buf1_re_node[current_block];
    //     node_buf1_we = block_node_buf1_we[current_block];
    //     initial_node_features_node_re = block_initial_node_features_node_re[current_block];
    //     node_address = block_node_address[current_block];
    //     node_index = block_node_index[current_block];
    //     node_output = block_node_output[current_block];
    // end
    // // Initial Edge Features
    // assign initial_edge_features_re = (state == BLOCK0) ? block_initial_edge_features_re[0] :
    //                                  (state == BLOCK1) ? block_initial_edge_features_re[1] :
    //                                  (state == BLOCK2) ? block_initial_edge_features_re[2] :
    //                                  (state == BLOCK3) ? block_initial_edge_features_re[3] :
    //                                  (state == BLOCK4) ? block_initial_edge_features_re[4] :
    //                                  (state == BLOCK5) ? block_initial_edge_features_re[5] :
    //                                  (state == BLOCK6) ? block_initial_edge_features_re[6] :
    //                                  (state == BLOCK7) ? block_initial_edge_features_re[7] : 1'b0;
    
    // // Edge Buffer 0
    // assign edge_buf0_re = (state == BLOCK0) ? block_edge_buf0_re[0] :
    //                      (state == BLOCK1) ? block_edge_buf0_re[1] :
    //                      (state == BLOCK2) ? block_edge_buf0_re[2] :
    //                      (state == BLOCK3) ? block_edge_buf0_re[3] :
    //                      (state == BLOCK4) ? block_edge_buf0_re[4] :
    //                      (state == BLOCK5) ? block_edge_buf0_re[5] :
    //                      (state == BLOCK6) ? block_edge_buf0_re[6] :
    //                      (state == BLOCK7) ? block_edge_buf0_re[7] : 1'b0;
    
    // assign edge_buf0_we = (state == BLOCK0) ? block_edge_buf0_we[0] :
    //                      (state == BLOCK1) ? block_edge_buf0_we[1] :
    //                      (state == BLOCK2) ? block_edge_buf0_we[2] :
    //                      (state == BLOCK3) ? block_edge_buf0_we[3] :
    //                      (state == BLOCK4) ? block_edge_buf0_we[4] :
    //                      (state == BLOCK5) ? block_edge_buf0_we[5] :
    //                      (state == BLOCK6) ? block_edge_buf0_we[6] :
    //                      (state == BLOCK7) ? block_edge_buf0_we[7] : 1'b0;
    
    // // Edge Buffer 1
    // assign edge_buf1_re = (state == BLOCK0) ? block_edge_buf1_re[0] :
    //                      (state == BLOCK1) ? block_edge_buf1_re[1] :
    //                      (state == BLOCK2) ? block_edge_buf1_re[2] :
    //                      (state == BLOCK3) ? block_edge_buf1_re[3] :
    //                      (state == BLOCK4) ? block_edge_buf1_re[4] :
    //                      (state == BLOCK5) ? block_edge_buf1_re[5] :
    //                      (state == BLOCK6) ? block_edge_buf1_re[6] :
    //                      (state == BLOCK7) ? block_edge_buf1_re[7] : 1'b0;
    
    // assign edge_buf1_we = (state == BLOCK0) ? block_edge_buf1_we[0] :
    //                      (state == BLOCK1) ? block_edge_buf1_we[1] :
    //                      (state == BLOCK2) ? block_edge_buf1_we[2] :
    //                      (state == BLOCK3) ? block_edge_buf1_we[3] :
    //                      (state == BLOCK4) ? block_edge_buf1_we[4] :
    //                      (state == BLOCK5) ? block_edge_buf1_we[5] :
    //                      (state == BLOCK6) ? block_edge_buf1_we[6] :
    //                      (state == BLOCK7) ? block_edge_buf1_we[7] : 1'b0;
    
    // // Initial Node Features Edge
    // assign initial_node_features_edge_re = (state == BLOCK0) ? block_initial_node_features_edge_re[0] :
    //                                       (state == BLOCK1) ? block_initial_node_features_edge_re[1] :
    //                                       (state == BLOCK2) ? block_initial_node_features_edge_re[2] :
    //                                       (state == BLOCK3) ? block_initial_node_features_edge_re[3] :
    //                                       (state == BLOCK4) ? block_initial_node_features_edge_re[4] :
    //                                       (state == BLOCK5) ? block_initial_node_features_edge_re[5] :
    //                                       (state == BLOCK6) ? block_initial_node_features_edge_re[6] :
    //                                       (state == BLOCK7) ? block_initial_node_features_edge_re[7] : 1'b0;
    
    // // Node Buffer 0 Edge
    // assign node_buf0_re_edge = (state == BLOCK0) ? block_node_buf0_re_edge[0] :
    //                           (state == BLOCK1) ? block_node_buf0_re_edge[1] :
    //                           (state == BLOCK2) ? block_node_buf0_re_edge[2] :
    //                           (state == BLOCK3) ? block_node_buf0_re_edge[3] :
    //                           (state == BLOCK4) ? block_node_buf0_re_edge[4] :
    //                           (state == BLOCK5) ? block_node_buf0_re_edge[5] :
    //                           (state == BLOCK6) ? block_node_buf0_re_edge[6] :
    //                           (state == BLOCK7) ? block_node_buf0_re_edge[7] : 1'b0;
    
    // // Node Buffer 1 Edge
    // assign node_buf1_re_edge = (state == BLOCK0) ? block_node_buf1_re_edge[0] :
    //                           (state == BLOCK1) ? block_node_buf1_re_edge[1] :
    //                           (state == BLOCK2) ? block_node_buf1_re_edge[2] :
    //                           (state == BLOCK3) ? block_node_buf1_re_edge[3] :
    //                           (state == BLOCK4) ? block_node_buf1_re_edge[4] :
    //                           (state == BLOCK5) ? block_node_buf1_re_edge[5] :
    //                           (state == BLOCK6) ? block_node_buf1_re_edge[6] :
    //                           (state == BLOCK7) ? block_node_buf1_re_edge[7] : 1'b0;
    
    // // Connectivity
    // assign source_node_index_re = (state == BLOCK0) ? block_source_node_index_re[0] :
    //                              (state == BLOCK1) ? block_source_node_index_re[1] :
    //                              (state == BLOCK2) ? block_source_node_index_re[2] :
    //                              (state == BLOCK3) ? block_source_node_index_re[3] :
    //                              (state == BLOCK4) ? block_source_node_index_re[4] :
    //                              (state == BLOCK5) ? block_source_node_index_re[5] :
    //                              (state == BLOCK6) ? block_source_node_index_re[6] :
    //                              (state == BLOCK7) ? block_source_node_index_re[7] : 1'b0;
    
    // assign destination_node_index_re = (state == BLOCK0) ? block_destination_node_index_re[0] :
    //                                   (state == BLOCK1) ? block_destination_node_index_re[1] :
    //                                   (state == BLOCK2) ? block_destination_node_index_re[2] :
    //                                   (state == BLOCK3) ? block_destination_node_index_re[3] :
    //                                   (state == BLOCK4) ? block_destination_node_index_re[4] :
    //                                   (state == BLOCK5) ? block_destination_node_index_re[5] :
    //                                   (state == BLOCK6) ? block_destination_node_index_re[6] :
    //                                   (state == BLOCK7) ? block_destination_node_index_re[7] : 1'b0;
    
    // // Edge Address
    // assign edge_address = (state == BLOCK0) ? block_edge_address[0] :
    //                      (state == BLOCK1) ? block_edge_address[1] :
    //                      (state == BLOCK2) ? block_edge_address[2] :
    //                      (state == BLOCK3) ? block_edge_address[3] :
    //                      (state == BLOCK4) ? block_edge_address[4] :
    //                      (state == BLOCK5) ? block_edge_address[5] :
    //                      (state == BLOCK6) ? block_edge_address[6] :
    //                      (state == BLOCK7) ? block_edge_address[7] : {RAM_ADDR_BITS_FOR_EDGE{1'b0}};
    
    // assign edge_index = (state == BLOCK0) ? block_edge_index[0] :
    //                    (state == BLOCK1) ? block_edge_index[1] :
    //                    (state == BLOCK2) ? block_edge_index[2] :
    //                    (state == BLOCK3) ? block_edge_index[3] :
    //                    (state == BLOCK4) ? block_edge_index[4] :
    //                    (state == BLOCK5) ? block_edge_index[5] :
    //                    (state == BLOCK6) ? block_edge_index[6] :
    //                    (state == BLOCK7) ? block_edge_index[7] : {(RAM_ADDR_BITS_FOR_EDGE-5){1'b0}};
    
    // // Scatter-Sum Indices
    // assign in_node_index_ss = (state == BLOCK0) ? block_in_node_index_ss[0] :
    //                          (state == BLOCK1) ? block_in_node_index_ss[1] :
    //                          (state == BLOCK2) ? block_in_node_index_ss[2] :
    //                          (state == BLOCK3) ? block_in_node_index_ss[3] :
    //                          (state == BLOCK4) ? block_in_node_index_ss[4] :
    //                          (state == BLOCK5) ? block_in_node_index_ss[5] :
    //                          (state == BLOCK6) ? block_in_node_index_ss[6] :
    //                          (state == BLOCK7) ? block_in_node_index_ss[7] : {RAM_ADDR_BITS_FOR_NODE{1'b0}};
    
    // assign out_node_index_ss = (state == BLOCK0) ? block_out_node_index_ss[0] :
    //                           (state == BLOCK1) ? block_out_node_index_ss[1] :
    //                           (state == BLOCK2) ? block_out_node_index_ss[2] :
    //                           (state == BLOCK3) ? block_out_node_index_ss[3] :
    //                           (state == BLOCK4) ? block_out_node_index_ss[4] :
    //                           (state == BLOCK5) ? block_out_node_index_ss[5] :
    //                           (state == BLOCK6) ? block_out_node_index_ss[6] :
    //                           (state == BLOCK7) ? block_out_node_index_ss[7] : {RAM_ADDR_BITS_FOR_NODE{1'b0}};
    
    // assign scatter_sum_we = (state == BLOCK0) ? block_scatter_sum_we[0] :
    //                        (state == BLOCK1) ? block_scatter_sum_we[1] :
    //                        (state == BLOCK2) ? block_scatter_sum_we[2] :
    //                        (state == BLOCK3) ? block_scatter_sum_we[3] :
    //                        (state == BLOCK4) ? block_scatter_sum_we[4] :
    //                        (state == BLOCK5) ? block_scatter_sum_we[5] :
    //                        (state == BLOCK6) ? block_scatter_sum_we[6] :
    //                        (state == BLOCK7) ? block_scatter_sum_we[7] : 1'b0;
    
    // // Edge Net Node Index
    // assign edge_net_node_index = (state == BLOCK0) ? block_edge_net_node_index[0] :
    //                             (state == BLOCK1) ? block_edge_net_node_index[1] :
    //                             (state == BLOCK2) ? block_edge_net_node_index[2] :
    //                             (state == BLOCK3) ? block_edge_net_node_index[3] :
    //                             (state == BLOCK4) ? block_edge_net_node_index[4] :
    //                             (state == BLOCK5) ? block_edge_net_node_index[5] :
    //                             (state == BLOCK6) ? block_edge_net_node_index[6] :
    //                             (state == BLOCK7) ? block_edge_net_node_index[7] : {RAM_ADDR_BITS_FOR_NODE{1'b0}};
    
    // // Edge Output
    // assign edge_output = (state == BLOCK0) ? block_edge_output[0] :
    //                     (state == BLOCK1) ? block_edge_output[1] :
    //                     (state == BLOCK2) ? block_edge_output[2] :
    //                     (state == BLOCK3) ? block_edge_output[3] :
    //                     (state == BLOCK4) ? block_edge_output[4] :
    //                     (state == BLOCK5) ? block_edge_output[5] :
    //                     (state == BLOCK6) ? block_edge_output[6] :
    //                     (state == BLOCK7) ? block_edge_output[7] : {(DATA_BITS*EDGE_FEATURES){1'b0}};
    
    // // Scatter-Sum Features
    // assign scatter_sum_features_in_re = (state == BLOCK0) ? block_scatter_sum_features_in_re[0] :
    //                                    (state == BLOCK1) ? block_scatter_sum_features_in_re[1] :
    //                                    (state == BLOCK2) ? block_scatter_sum_features_in_re[2] :
    //                                    (state == BLOCK3) ? block_scatter_sum_features_in_re[3] :
    //                                    (state == BLOCK4) ? block_scatter_sum_features_in_re[4] :
    //                                    (state == BLOCK5) ? block_scatter_sum_features_in_re[5] :
    //                                    (state == BLOCK6) ? block_scatter_sum_features_in_re[6] :
    //                                    (state == BLOCK7) ? block_scatter_sum_features_in_re[7] : 1'b0;
    
    // assign scatter_sum_features_out_re = (state == BLOCK0) ? block_scatter_sum_features_out_re[0] :
    //                                     (state == BLOCK1) ? block_scatter_sum_features_out_re[1] :
    //                                     (state == BLOCK2) ? block_scatter_sum_features_out_re[2] :
    //                                     (state == BLOCK3) ? block_scatter_sum_features_out_re[3] :
    //                                     (state == BLOCK4) ? block_scatter_sum_features_out_re[4] :
    //                                     (state == BLOCK5) ? block_scatter_sum_features_out_re[5] :
    //                                     (state == BLOCK6) ? block_scatter_sum_features_out_re[6] :
    //                                     (state == BLOCK7) ? block_scatter_sum_features_out_re[7] : 1'b0;
    
    // // Node Buffer 0
    // assign node_buf0_re_node = (state == BLOCK0) ? block_node_buf0_re_node[0] :
    //                           (state == BLOCK1) ? block_node_buf0_re_node[1] :
    //                           (state == BLOCK2) ? block_node_buf0_re_node[2] :
    //                           (state == BLOCK3) ? block_node_buf0_re_node[3] :
    //                           (state == BLOCK4) ? block_node_buf0_re_node[4] :
    //                           (state == BLOCK5) ? block_node_buf0_re_node[5] :
    //                           (state == BLOCK6) ? block_node_buf0_re_node[6] :
    //                           (state == BLOCK7) ? block_node_buf0_re_node[7] : 1'b0;
    
    // assign node_buf0_we = (state == BLOCK0) ? block_node_buf0_we[0] :
    //                      (state == BLOCK1) ? block_node_buf0_we[1] :
    //                      (state == BLOCK2) ? block_node_buf0_we[2] :
    //                      (state == BLOCK3) ? block_node_buf0_we[3] :
    //                      (state == BLOCK4) ? block_node_buf0_we[4] :
    //                      (state == BLOCK5) ? block_node_buf0_we[5] :
    //                      (state == BLOCK6) ? block_node_buf0_we[6] :
    //                      (state == BLOCK7) ? block_node_buf0_we[7] : 1'b0;
    
    // // Node Buffer 1
    // assign node_buf1_re_node = (state == BLOCK0) ? block_node_buf1_re_node[0] :
    //                           (state == BLOCK1) ? block_node_buf1_re_node[1] :
    //                           (state == BLOCK2) ? block_node_buf1_re_node[2] :
    //                           (state == BLOCK3) ? block_node_buf1_re_node[3] :
    //                           (state == BLOCK4) ? block_node_buf1_re_node[4] :
    //                           (state == BLOCK5) ? block_node_buf1_re_node[5] :
    //                           (state == BLOCK6) ? block_node_buf1_re_node[6] :
    //                           (state == BLOCK7) ? block_node_buf1_re_node[7] : 1'b0;
    
    // assign node_buf1_we = (state == BLOCK0) ? block_node_buf1_we[0] :
    //                      (state == BLOCK1) ? block_node_buf1_we[1] :
    //                      (state == BLOCK2) ? block_node_buf1_we[2] :
    //                      (state == BLOCK3) ? block_node_buf1_we[3] :
    //                      (state == BLOCK4) ? block_node_buf1_we[4] :
    //                      (state == BLOCK5) ? block_node_buf1_we[5] :
    //                      (state == BLOCK6) ? block_node_buf1_we[6] :
    //                      (state == BLOCK7) ? block_node_buf1_we[7] : 1'b0;
    
    // // Initial Node Features Node
    // assign initial_node_features_node_re = (state == BLOCK0) ? block_initial_node_features_node_re[0] :
    //                                       (state == BLOCK1) ? block_initial_node_features_node_re[1] :
    //                                       (state == BLOCK2) ? block_initial_node_features_node_re[2] :
    //                                       (state == BLOCK3) ? block_initial_node_features_node_re[3] :
    //                                       (state == BLOCK4) ? block_initial_node_features_node_re[4] :
    //                                       (state == BLOCK5) ? block_initial_node_features_node_re[5] :
    //                                       (state == BLOCK6) ? block_initial_node_features_node_re[6] :
    //                                       (state == BLOCK7) ? block_initial_node_features_node_re[7] : 1'b0;
    
    // // Node Address
    // assign node_address = (state == BLOCK0) ? block_node_address[0] :
    //                      (state == BLOCK1) ? block_node_address[1] :
    //                      (state == BLOCK2) ? block_node_address[2] :
    //                      (state == BLOCK3) ? block_node_address[3] :
    //                      (state == BLOCK4) ? block_node_address[4] :
    //                      (state == BLOCK5) ? block_node_address[5] :
    //                      (state == BLOCK6) ? block_node_address[6] :
    //                      (state == BLOCK7) ? block_node_address[7] : {RAM_ADDR_BITS_FOR_NODE{1'b0}};
    
    // assign node_index = (state == BLOCK0) ? block_node_index[0] :
    //                    (state == BLOCK1) ? block_node_index[1] :
    //                    (state == BLOCK2) ? block_node_index[2] :
    //                    (state == BLOCK3) ? block_node_index[3] :
    //                    (state == BLOCK4) ? block_node_index[4] :
    //                    (state == BLOCK5) ? block_node_index[5] :
    //                    (state == BLOCK6) ? block_node_index[6] :
    //                    (state == BLOCK7) ? block_node_index[7] : {(RAM_ADDR_BITS_FOR_NODE-5){1'b0}};
    
    // // Node Output
    // assign node_output = (state == BLOCK0) ? block_node_output[0] :
    //                     (state == BLOCK1) ? block_node_output[1] :
    //                     (state == BLOCK2) ? block_node_output[2] :
    //                     (state == BLOCK3) ? block_node_output[3] :
    //                     (state == BLOCK4) ? block_node_output[4] :
    //                     (state == BLOCK5) ? block_node_output[5] :
    //                     (state == BLOCK6) ? block_node_output[6] :
    //                     (state == BLOCK7) ? block_node_output[7] : {(DATA_BITS*NODE_FEATURES){1'b0}};

endmodule
