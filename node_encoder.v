`timescale 1ns / 1ps

//==============================================================================
// node_encoder — pipelined version
// Same structure as pipelined edge_encoder.
// L1: 12 input features → ~12cy counter + ~22cy layer norm = ~34cy
// L2+L3: 32 features each → ~54cy each = ~108cy total
// Pipeline: next node's READ+L1 runs during current node's L2+L3.
// Effective per node: ~108cy vs ~145cy sequential = ~26% faster.
//==============================================================================

module node_encoder #(
    parameter NUM_NODES    = 8,
    parameter NUM_FEATURES = 12,
    parameter DATA_BITS    = 8,
    parameter WEIGHT_BITS  = 8,
    parameter BIAS_BITS    = 8,
    parameter USE_RMS_NORM = 1,
    parameter ADDR_BITS    = 14,
    parameter OUT_FEATURES = 32,
    parameter MEM_FILE     = "node_initial_features.mem"
) (
    input  clk,
    input  rstn,
    input  start,
    input  [ADDR_BITS-1:0] active_num_nodes,
    output reg [OUT_FEATURES*DATA_BITS-1:0] encoded_data,
    output reg [ADDR_BITS-1:0]              node_addr_out,
    output reg                              data_valid,
    output reg                              done
);

    //==========================================================================
    // Internal node memory
    //==========================================================================
    reg [NUM_FEATURES*DATA_BITS-1:0] node_mem [0:NUM_NODES-1];
    reg [DATA_BITS-1:0] temp_array [0:(NUM_NODES*NUM_FEATURES)-1];
    initial begin
        $readmemb(MEM_FILE, temp_array);
    end
    genvar j;
    generate
        for (j = 0; j < NUM_NODES; j = j + 1) begin : mem_init
            always @(*) begin
                node_mem[j] = {
                    temp_array[(j*12)+11], temp_array[(j*12)+10], temp_array[(j*12)+9],
                    temp_array[(j*12)+8],  temp_array[(j*12)+7],  temp_array[(j*12)+6],
                    temp_array[(j*12)+5],  temp_array[(j*12)+4],  temp_array[(j*12)+3],
                    temp_array[(j*12)+2],  temp_array[(j*12)+1],  temp_array[(j*12)+0]
                };
            end
        end
    endgenerate

    //==========================================================================
    // Layer wires
    //==========================================================================
    reg  [NUM_FEATURES*DATA_BITS-1:0]  l1_data_in;
    wire [OUT_FEATURES*DATA_BITS-1:0]  layer1_out;
    wire                               layer1_done;
    wire [OUT_FEATURES*DATA_BITS-1:0]  layer2_out;
    wire                               layer2_done;
    wire [OUT_FEATURES*DATA_BITS-1:0]  layer3_out;
    wire                               layer3_done;

    reg [OUT_FEATURES*DATA_BITS-1:0] layer1_out_reg;
    reg [OUT_FEATURES*DATA_BITS-1:0] layer2_out_reg;
    reg [OUT_FEATURES*DATA_BITS-1:0] layer3_out_reg;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            layer1_out_reg <= 0;
            layer2_out_reg <= 0;
            layer3_out_reg <= 0;
        end else begin
            if (layer1_done) layer1_out_reg <= layer1_out;
            if (layer2_done) layer2_out_reg <= layer2_out;
            if (layer3_done) layer3_out_reg <= layer3_out;
        end
    end

    reg layer1_held, layer2_held, layer3_held;

    node_encoder_layer_1 #(
        .LAYER_NO(1), .NUM_NEURONS(OUT_FEATURES), .NUM_FEATURES(NUM_FEATURES),
        .DATA_BITS(DATA_BITS), .WEIGHT_BITS(WEIGHT_BITS), .BIAS_BITS(BIAS_BITS), .USE_RMS_NORM(USE_RMS_NORM)
    ) layer1_inst (
        .clk(clk), .rstn(layer1_held), .activation_function(1'b1),
        .data_in_flat(l1_data_in),
        .data_out_flat(layer1_out), .valid_out(layer1_done), .done()
    );

    node_encoder_layer_2 #(
        .LAYER_NO(2), .NUM_NEURONS(OUT_FEATURES), .NUM_FEATURES(OUT_FEATURES),
        .DATA_BITS(DATA_BITS), .WEIGHT_BITS(WEIGHT_BITS), .BIAS_BITS(BIAS_BITS), .USE_RMS_NORM(USE_RMS_NORM)
    ) layer2_inst (
        .clk(clk), .rstn(layer2_held), .activation_function(1'b1),
        .data_in_flat(layer1_out_reg),
        .data_out_flat(layer2_out), .valid_out(layer2_done), .done()
    );

    node_encoder_layer_3 #(
        .LAYER_NO(3), .NUM_NEURONS(OUT_FEATURES), .NUM_FEATURES(OUT_FEATURES),
        .DATA_BITS(DATA_BITS), .WEIGHT_BITS(WEIGHT_BITS), .BIAS_BITS(BIAS_BITS), .USE_RMS_NORM(USE_RMS_NORM)
    ) layer3_inst (
        .clk(clk), .rstn(layer3_held), .activation_function(1'b1),
        .data_in_flat(layer2_out_reg),
        .data_out_flat(layer3_out), .valid_out(layer3_done), .done()
    );

    //==========================================================================
    // FIFO: holds (node_index, l1_output) between load and compute FSMs
    //==========================================================================
    localparam FIFO_DEPTH = NUM_NODES;
    localparam FIFO_AW = $clog2(FIFO_DEPTH);
    reg [OUT_FEATURES*DATA_BITS-1:0] fifo_l1out [0:FIFO_DEPTH-1];
    reg [ADDR_BITS-1:0]              fifo_idx   [0:FIFO_DEPTH-1];
    reg [FIFO_AW-1:0] fifo_wptr, fifo_rptr;
    reg [FIFO_AW:0] fifo_count;
    wire fifo_empty = (fifo_count == 0);
    wire fifo_full  = (fifo_count == FIFO_DEPTH);

    //==========================================================================
    // Load FSM states
    //==========================================================================
    localparam LS_IDLE  = 2'd0,
               LS_READ  = 2'd1,
               LS_L1W   = 2'd2,
               LS_DRAIN = 2'd3;

    reg [1:0] ls_state;
    reg [ADDR_BITS-1:0] load_idx;
    reg [ADDR_BITS-1:0] nodes_loaded;

    //==========================================================================
    // Compute FSM states
    //==========================================================================
    localparam CS_IDLE   = 3'd0,
               CS_L2W    = 3'd1,
               CS_L2_GAP = 3'd2,
               CS_L3W    = 3'd3,
               CS_WRITE  = 3'd4,
               CS_NEXT   = 3'd5;

    reg [2:0] cs_state;
    reg [ADDR_BITS-1:0] compute_idx;
    reg [ADDR_BITS-1:0] nodes_written;

    wire do_pop  = (cs_state == CS_IDLE) && !fifo_empty;
    wire do_push = layer1_done && (ls_state == LS_L1W) && !fifo_full;

    integer k;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            fifo_wptr <= 0; fifo_rptr <= 0; fifo_count <= 0;
            for (k = 0; k < FIFO_DEPTH; k = k + 1) begin
                fifo_l1out[k] <= 0; fifo_idx[k] <= 0;
            end
        end else begin
            if (do_push) begin
                fifo_l1out[fifo_wptr] <= layer1_out;
                fifo_idx[fifo_wptr]   <= load_idx;
                fifo_wptr <= (fifo_wptr == FIFO_DEPTH-1) ? 0 : fifo_wptr + 1;
            end
            if (do_pop) begin
                layer1_out_reg <= fifo_l1out[fifo_rptr];
                compute_idx    <= fifo_idx[fifo_rptr];
                fifo_rptr <= (fifo_rptr == FIFO_DEPTH-1) ? 0 : fifo_rptr + 1;
            end
            case ({do_push, do_pop})
                2'b10: fifo_count <= fifo_count + 1;
                2'b01: fifo_count <= fifo_count - 1;
                default: ;
            endcase
        end
    end

    //==========================================================================
    // Load FSM
    //==========================================================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            ls_state     <= LS_IDLE;
            load_idx     <= 0;
            nodes_loaded <= 0;
            layer1_held  <= 0;
            l1_data_in   <= 0;
        end else begin
            layer1_held <= 0;

            case (ls_state)
                LS_IDLE: begin
                    if (start) begin
                        load_idx     <= 0;
                        nodes_loaded <= 0;
                        ls_state     <= LS_READ;
                    end
                end

                LS_READ: begin
                    l1_data_in <= node_mem[load_idx];
                    ls_state   <= LS_L1W;
                end

                LS_L1W: begin
                    layer1_held <= 1;
                    if (layer1_done) begin
                        nodes_loaded <= nodes_loaded + 1;
                        if (nodes_loaded + 1 < active_num_nodes && !fifo_full) begin
                            load_idx <= load_idx + 1;
                            ls_state <= LS_READ;
                        end else if (nodes_loaded + 1 >= active_num_nodes) begin
                            ls_state <= LS_DRAIN;
                        end
                        // $display("[%0t] [DBG] LAYER1 node=%0d  out[full] = %0h",
//                            $time, load_idx, layer1_out);
                    end
                end

                LS_DRAIN: ; // wait for compute FSM

                default: ls_state <= LS_IDLE;
            endcase
        end
    end

    //==========================================================================
    // Compute FSM
    //==========================================================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            cs_state      <= CS_IDLE;
            layer2_held   <= 0;
            layer3_held   <= 0;
            nodes_written <= 0;
            encoded_data  <= 0;
            node_addr_out <= 0;
            data_valid    <= 0;
            done          <= 0;
            compute_idx   <= 0;
        end else begin
            data_valid <= 0;
            done       <= 0;

            case (cs_state)
                CS_IDLE: begin
                    layer2_held <= 0;
                    if (do_pop) begin
                        layer2_held <= 1;
                        cs_state    <= CS_L2W;
                    end
                end

                CS_L2W: begin
                    layer2_held <= 1;
                    if (layer2_done) begin
                        layer2_held <= 0;
                        layer3_held <= 1;
                        cs_state    <= CS_L2_GAP;
                    // $display("[%0t] [DBG] LAYER2 node=%0d  out[full] = %0h",
                    //     $time, compute_idx, layer2_out);
                    end
                end

                CS_L2_GAP: begin
                    layer2_held <= 0;
                    layer3_held <= 1;
                    cs_state    <= CS_L3W;
                end

                CS_L3W: begin
                    layer3_held <= 1;
                    if (layer3_done) begin
                        layer3_held <= 0;
                        cs_state    <= CS_WRITE;
                        // $display("[%0t] [DBG] LAYER3 node=%0d  out[full] = %0h",
                        //     $time, compute_idx, layer3_out);
                    end

                end

                CS_WRITE: begin
                    encoded_data  <= layer3_out_reg;
                    node_addr_out <= compute_idx;
                    data_valid    <= 1;
                    cs_state      <= CS_NEXT;
                end

                CS_NEXT: begin
                    nodes_written <= nodes_written + 1;
                    if (nodes_written + 1 >= active_num_nodes) begin
                        done          <= 1;
                        nodes_written <= 0;
                        cs_state      <= CS_IDLE;
                    end else begin
                        cs_state <= CS_IDLE;
                    end
                end

                default: cs_state <= CS_IDLE;
            endcase
        end
    end

endmodule
