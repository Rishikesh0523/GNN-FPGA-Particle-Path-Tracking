`timescale 1ns / 1ps

module edge_encoder #(
    parameter NUM_EDGES    = 4,
    parameter NUM_FEATURES = 6,
    parameter DATA_BITS    = 8,
    parameter WEIGHT_BITS  = 8,
    parameter BIAS_BITS    = 8,
    parameter USE_RMS_NORM = 1,
    parameter ADDR_BITS    = 14,
    parameter OUT_FEATURES = 32,
    parameter MEM_FILE     = "edge_initial_features.mem"
) (
    input  clk,
    input  rstn,
    input  start,
    input  [ADDR_BITS-1:0] active_num_edges,
    output reg [OUT_FEATURES*DATA_BITS-1:0] encoded_data,
    output reg [ADDR_BITS-1:0]              edge_addr_out,
    output reg                              data_valid,
    output reg                              done
);

    //==========================================================================
    // Internal edge memory (unchanged)
    //==========================================================================
    reg [NUM_FEATURES*DATA_BITS-1:0] edge_mem [0:NUM_EDGES-1];
    reg [DATA_BITS-1:0] temp_array [0:(NUM_EDGES*NUM_FEATURES)-1];
    initial begin
        $readmemb(MEM_FILE, temp_array);
    end
    genvar j;
    generate
        for (j = 0; j < NUM_EDGES; j = j + 1) begin : mem_init
            always @(*) begin
                edge_mem[j] = {
                    temp_array[(j*6)+5], temp_array[(j*6)+4], temp_array[(j*6)+3],
                    temp_array[(j*6)+2], temp_array[(j*6)+1], temp_array[(j*6)+0]
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

    //==========================================================================
    // Layer control
    //==========================================================================
    reg layer1_held, layer2_held, layer3_held;

    edge_encoder_layer_1 #(
        .LAYER_NO(1), .NUM_NEURONS(OUT_FEATURES), .NUM_FEATURES(NUM_FEATURES),
        .DATA_BITS(DATA_BITS), .WEIGHT_BITS(WEIGHT_BITS), .BIAS_BITS(BIAS_BITS), .USE_RMS_NORM(USE_RMS_NORM)
    ) layer1_inst (
        .clk(clk), .rstn(layer1_held), .activation_function(1'b1),
        .data_in_flat(l1_data_in),
        .data_out_flat(layer1_out), .valid_out(layer1_done), .done()
    );

    edge_encoder_layer_2 #(
        .LAYER_NO(2), .NUM_NEURONS(OUT_FEATURES), .NUM_FEATURES(OUT_FEATURES),
        .DATA_BITS(DATA_BITS), .WEIGHT_BITS(WEIGHT_BITS), .BIAS_BITS(BIAS_BITS), .USE_RMS_NORM(USE_RMS_NORM)
    ) layer2_inst (
        .clk(clk), .rstn(layer2_held), .activation_function(1'b1),
        .data_in_flat(layer1_out_reg),
        .data_out_flat(layer2_out), .valid_out(layer2_done), .done()
    );

    edge_encoder_layer_3 #(
        .LAYER_NO(3), .NUM_NEURONS(OUT_FEATURES), .NUM_FEATURES(OUT_FEATURES),
        .DATA_BITS(DATA_BITS), .WEIGHT_BITS(WEIGHT_BITS), .BIAS_BITS(BIAS_BITS), .USE_RMS_NORM(USE_RMS_NORM)
    ) layer3_inst (
        .clk(clk), .rstn(layer3_held), .activation_function(1'b1),
        .data_in_flat(layer2_out_reg),
        .data_out_flat(layer3_out), .valid_out(layer3_done), .done()
    );

    //==========================================================================
    // FIFO
    //==========================================================================
    localparam FIFO_DEPTH = NUM_EDGES;
    localparam FIFO_AW = $clog2(FIFO_DEPTH);
    reg [OUT_FEATURES*DATA_BITS-1:0] fifo_l1out [0:FIFO_DEPTH-1];
    reg [ADDR_BITS-1:0]              fifo_idx   [0:FIFO_DEPTH-1];
    reg [FIFO_AW-1:0] fifo_wptr, fifo_rptr;
    reg [FIFO_AW:0] fifo_count;
    wire fifo_empty = (fifo_count == 0);
    wire fifo_full  = (fifo_count == FIFO_DEPTH);

    localparam LS_IDLE  = 2'd0,
               LS_READ  = 2'd1,
               LS_L1W   = 2'd2,
               LS_DRAIN = 2'd3;

    reg [1:0] ls_state;
    reg [ADDR_BITS-1:0] load_idx;
    reg [ADDR_BITS-1:0] edges_loaded;

    localparam CS_IDLE    = 3'd0,
               CS_L2W     = 3'd1,
               CS_L2_GAP  = 3'd2,
               CS_L3W     = 3'd3,
               CS_WRITE   = 3'd4,
               CS_NEXT    = 3'd5;

    reg [2:0] cs_state;
    reg [ADDR_BITS-1:0] compute_idx;
    reg [ADDR_BITS-1:0] edges_written;

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
            edges_loaded <= 0;
            layer1_held  <= 0;
            l1_data_in   <= 0;
        end else begin
            layer1_held <= 0;

            case (ls_state)
                LS_IDLE: begin
                    if (start) begin
                        load_idx     <= 0;
                        edges_loaded <= 0;
                        ls_state     <= LS_READ;
                    end
                end

                LS_READ: begin
                    l1_data_in <= edge_mem[load_idx];
                    ls_state   <= LS_L1W;

                    // --------------------------------------------------------
                    // DEBUG: Print the raw input features being fed into Layer 1
                    // Each feature is DATA_BITS wide, packed LSB-first in edge_mem
                    // --------------------------------------------------------
                    // $display("[%0t] [DBG] LOAD  edge=%0d  INPUT features = %0h %0h %0h %0h %0h %0h",
                    //     $time, load_idx,
                    //     edge_mem[load_idx][1*DATA_BITS-1 -: DATA_BITS],  // feature[0]
                    //     edge_mem[load_idx][2*DATA_BITS-1 -: DATA_BITS],  // feature[1]
                    //     edge_mem[load_idx][3*DATA_BITS-1 -: DATA_BITS],  // feature[2]
                    //     edge_mem[load_idx][4*DATA_BITS-1 -: DATA_BITS],  // feature[3]
                    //     edge_mem[load_idx][5*DATA_BITS-1 -: DATA_BITS],  // feature[4]
                    //     edge_mem[load_idx][6*DATA_BITS-1 -: DATA_BITS]   // feature[5]
                    // );
                end

                LS_L1W: begin
                    layer1_held <= 1;
                    if (layer1_done) begin
                        // --------------------------------------------------------
                        // DEBUG: Layer 1 output — print first 8 neurons for brevity
                        // Change the slice range or add more lines to see all 32
                        // --------------------------------------------------------
                        // $display("[%0t] [DBG] LAYER1 edge=%0d  out[0:7] = %0h %0h %0h %0h %0h %0h %0h %0h",
                        //     $time, load_idx,
                        //     layer1_out[1*DATA_BITS-1 -: DATA_BITS],
                        //     layer1_out[2*DATA_BITS-1 -: DATA_BITS],
                        //     layer1_out[3*DATA_BITS-1 -: DATA_BITS],
                        //     layer1_out[4*DATA_BITS-1 -: DATA_BITS],
                        //     layer1_out[5*DATA_BITS-1 -: DATA_BITS],
                        //     layer1_out[6*DATA_BITS-1 -: DATA_BITS],
                        //     layer1_out[7*DATA_BITS-1 -: DATA_BITS],
                        //     layer1_out[8*DATA_BITS-1 -: DATA_BITS]
                        // );
                        // $display("[%0t] [DBG] LAYER1 edge=%0d  out[full] = %0h",
                        //     $time, load_idx, layer1_out);

                        edges_loaded <= edges_loaded + 1;
                        if (edges_loaded + 1 < active_num_edges && !fifo_full) begin
                            load_idx <= load_idx + 1;
                            ls_state <= LS_READ;
                        end else if (edges_loaded + 1 >= active_num_edges) begin
                            ls_state <= LS_DRAIN;
                        end
                    end
                end

                LS_DRAIN: begin
                    // wait
                end

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
            edges_written <= 0;
            encoded_data  <= 0;
            edge_addr_out <= 0;
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
                        // --------------------------------------------------------
                        // DEBUG: Layer 2 output
                        // --------------------------------------------------------
                        // $display("[%0t] [DBG] LAYER2 edge=%0d  out[0:7] = %0h %0h %0h %0h %0h %0h %0h %0h",
                        //     $time, compute_idx,
                        //     layer2_out[1*DATA_BITS-1 -: DATA_BITS],
                        //     layer2_out[2*DATA_BITS-1 -: DATA_BITS],
                        //     layer2_out[3*DATA_BITS-1 -: DATA_BITS],
                        //     layer2_out[4*DATA_BITS-1 -: DATA_BITS],
                        //     layer2_out[5*DATA_BITS-1 -: DATA_BITS],
                        //     layer2_out[6*DATA_BITS-1 -: DATA_BITS],
                        //     layer2_out[7*DATA_BITS-1 -: DATA_BITS],
                        //     layer2_out[8*DATA_BITS-1 -: DATA_BITS]
                        // );
                        // $display("[%0t] [DBG] LAYER2 edge=%0d  out[full] = %0h",
                        //     $time, compute_idx, layer2_out);

                        layer2_held <= 0;
                        layer3_held <= 1;
                        cs_state    <= CS_L2_GAP;
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
                        // --------------------------------------------------------
                        // DEBUG: Layer 3 output (final encoder output)
                        // --------------------------------------------------------
                        // $display("[%0t] [DBG] LAYER3 edge=%0d  out[0:7] = %0h %0h %0h %0h %0h %0h %0h %0h",
                        //     $time, compute_idx,
                        //     layer3_out[1*DATA_BITS-1 -: DATA_BITS],
                        //     layer3_out[2*DATA_BITS-1 -: DATA_BITS],
                        //     layer3_out[3*DATA_BITS-1 -: DATA_BITS],
                        //     layer3_out[4*DATA_BITS-1 -: DATA_BITS],
                        //     layer3_out[5*DATA_BITS-1 -: DATA_BITS],
                        //     layer3_out[6*DATA_BITS-1 -: DATA_BITS],
                        //     layer3_out[7*DATA_BITS-1 -: DATA_BITS],
                        //     layer3_out[8*DATA_BITS-1 -: DATA_BITS]
                        // );
                        // $display("[%0t] [DBG] LAYER3 edge=%0d  out[full] = %0h",
                        //     $time, compute_idx, layer3_out);

                        layer3_held <= 0;
                        cs_state    <= CS_WRITE;
                    end
                end

                CS_WRITE: begin
                    encoded_data  <= layer3_out_reg;
                    edge_addr_out <= compute_idx;
                    data_valid    <= 1;

                    // --------------------------------------------------------
                    // DEBUG: Final write — confirms what gets latched to output
                    // --------------------------------------------------------
                    // $display("[%0t] [DBG] WRITE  edge=%0d  encoded_data = %0h  (data_valid=1)",
                    //     $time, compute_idx, layer3_out_reg);

                    cs_state <= CS_NEXT;
                end

                CS_NEXT: begin
                    edges_written <= edges_written + 1;
                    if (edges_written + 1 >= active_num_edges) begin
                        // $display("[%0t] [DBG] ALL DONE — %0d edges encoded", $time, NUM_EDGES);
                        done          <= 1;
                        cs_state      <= CS_IDLE;
                        edges_written <= 0;
                    end else begin
                        cs_state <= CS_IDLE;
                    end
                end

                default: cs_state <= CS_IDLE;
            endcase
        end
    end

endmodule
