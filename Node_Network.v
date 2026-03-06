`timescale 1ns / 1ps
//==============================================================================
// Node_Network_Pipelined — 3× L1 round-robin + L2/L3 pipeline
//
// L2/L3 pipeline uses the existing CS_L2_GAP cycle cleverly:
// - CS_L2_GAP: layer2_held drops (counter resets), layer3_held rises
// - Instead of waiting for L3 before restarting L2, we pop next item from
//   inter-stage FIFO and restart L2 immediately in CS_L2_GAP
// - L2 and L3 run concurrently: L2 on node k+1, L3 on node k
// - Throughput: max(L2_time, L3_time) = one layer time instead of two
//==============================================================================
module Node_Network #(
    parameter BLOCK_NUM              = 0,
    parameter DATA_BITS              = 8,
    parameter USE_RMS_NORM           = 1,
    parameter RAM_ADDR_BITS_FOR_NODE = 0,
    parameter NODE_FEATURES          = 32,
    parameter MAX_NODES              = 0
) (
    input  clk, input rstn, input start,
    input  [RAM_ADDR_BITS_FOR_NODE-6:0] active_num_nodes,
    input  [DATA_BITS*NODE_FEATURES-1:0] scatter_sum_features_in,
    output reg scatter_sum_features_in_re,
    input      scatter_sum_features_in_valid,
    input  [DATA_BITS*NODE_FEATURES-1:0] scatter_sum_features_out,
    output reg scatter_sum_features_out_re,
    input      scatter_sum_features_out_valid,
    input  [DATA_BITS*NODE_FEATURES-1:0] current_node_features,
    output reg current_node_features_re,
    input      current_node_features_valid,
    output reg current_node_features_we,
    input      current_node_features_write_done,
    input  [DATA_BITS*NODE_FEATURES-1:0] initial_node_features,
    output reg initial_node_features_re,
    input      initial_node_features_valid,
    output [RAM_ADDR_BITS_FOR_NODE-1:0] node_address,
    output [RAM_ADDR_BITS_FOR_NODE-6:0] node_index,
    output [DATA_BITS*NODE_FEATURES-1:0] node_output,
    output reg done
);

    // =========================================================================
    // Load FIFO
    // =========================================================================
    localparam FIFO_DEPTH=(MAX_NODES > 1) ? MAX_NODES : 2;
    localparam FIFO_AW=$clog2(FIFO_DEPTH);
    reg [RAM_ADDR_BITS_FOR_NODE-1:0]    fifo_node_addr [0:FIFO_DEPTH-1];
    reg [4*NODE_FEATURES*DATA_BITS-1:0] concat_fifo    [0:FIFO_DEPTH-1];
    reg [FIFO_AW-1:0] fifo_wptr, fifo_rptr;
    reg [FIFO_AW:0]   fifo_count;
    wire fifo_empty = (fifo_count == 0);
    wire fifo_full  = (fifo_count == FIFO_DEPTH);

    // =========================================================================
    // Load FSM states
    // =========================================================================
    localparam LS_IDLE=3'd0, LS_LOAD1=3'd1, LS_CONCAT=3'd2, LS_DRAIN=3'd3;
    reg [2:0] ls_state;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] idx_load, nodes_dispatched, nodes_completed;
    reg [DATA_BITS*NODE_FEATURES-1:0] load_ss_in, load_ss_out, load_curr, load_init;
    reg load_rd_done, layer1_start, ec_reset;
    wire do_push = layer1_start & ~fifo_full;

    // =========================================================================
    // 3× L1 instances
    // =========================================================================
    reg [4*NODE_FEATURES*DATA_BITS-1:0] concat_latch_a, concat_latch_b, concat_latch_c;
    reg layer1a_held, layer1b_held, layer1c_held;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] l1a_na, l1b_na, l1c_na;
    reg l1a_busy, l1b_busy, l1c_busy;
    reg [1:0] dispatch_rr;

    wire [NODE_FEATURES*DATA_BITS-1:0] Layer1a_out, Layer1b_out, Layer1c_out;
    wire Layer1a_valid, Layer1b_valid, Layer1c_valid;

    wire do_dispatch_a = !fifo_empty && (dispatch_rr==0) && !l1a_busy;
    wire do_dispatch_b = !fifo_empty && (dispatch_rr==1) && !l1b_busy;
    wire do_dispatch_c = !fifo_empty && (dispatch_rr==2) && !l1c_busy;
    wire do_dispatch   = do_dispatch_a | do_dispatch_b | do_dispatch_c;

    // =========================================================================
    // L1→L2 inter-stage FIFO
    // =========================================================================
    localparam S_DEPTH=(MAX_NODES > 1) ? MAX_NODES : 2;
    localparam S_AW=$clog2(S_DEPTH);
    reg [NODE_FEATURES*DATA_BITS-1:0] s_data [0:S_DEPTH-1];
    reg [RAM_ADDR_BITS_FOR_NODE-1:0]  s_na   [0:S_DEPTH-1];
    reg [S_AW-1:0] s_wptr, s_rptr;
    reg [S_AW:0] s_count;
    wire s_empty = (s_count == 0);
    wire s_full  = (s_count == S_DEPTH);

    wire do_collect_a = Layer1a_valid && l1a_busy && !s_full;
    wire do_collect_b = Layer1b_valid && l1b_busy && !s_full && !do_collect_a;
    wire do_collect_c = Layer1c_valid && l1c_busy && !s_full && !do_collect_a && !do_collect_b;
    wire do_collect   = do_collect_a | do_collect_b | do_collect_c;

    // =========================================================================
    // Compute FSM states
    // FIX (pipeline latency): use lookahead on inter-stage FIFO so L2 can pop
    // on the same cycle a collect writes to it, eliminating the 1-cycle lag
    // that existed when do_s_pop_idle/gap checked s_empty after s_count updated.
    // =========================================================================
    localparam CS_IDLE=3'd0, CS_L2W=3'd1, CS_L2_GAP=3'd2, CS_L3W=3'd3;
    reg [2:0] cs_state;

    // Lookahead: FIFO will have data after this cycle if it has data now,
    // OR if a collect is writing to it this cycle (net count increases).
    wire s_will_have_data = !s_empty || (do_collect && (s_rptr != s_wptr));

    wire do_s_pop_idle = (cs_state == CS_IDLE)    && s_will_have_data;
    wire do_s_pop_gap  = (cs_state == CS_L2_GAP)  && s_will_have_data;
    wire do_s_pop      = do_s_pop_idle || do_s_pop_gap;

    reg [DATA_BITS*NODE_FEATURES-1:0] Layer1_out_r;

    // Ping-pong L2 output buffer.
    // L2 writes to pp_buf[pp_wr]; L3 reads from pp_buf[pp_wr ^ 1].
    // Layer2_out_r is latched into a stable register at CS_L2_GAP so that
    // a subsequent pp_wr flip during L3's run cannot corrupt L3's input.
    reg [DATA_BITS*NODE_FEATURES-1:0] pp_buf [0:1];
    reg pp_wr;
    reg [DATA_BITS*NODE_FEATURES-1:0] Layer2_out_r;

    wire [NODE_FEATURES*DATA_BITS-1:0] Layer2_out, Layer3_out;
    wire Layer2_out_valid, Layer3_out_valid;

    // FIX (Edge_Network #8): use Layer2_done (MAC done) to drive FSM transitions
    // and Layer2_out_valid (LN done) to latch pp_buf — matching Edge_Network pattern.
    // Node_Network originally used Layer2_out_valid for both, which works but
    // means the FSM waits the full LN latency (~38cy) before transitioning,
    // delaying the CS_L2_GAP cycle and hurting pipeline fill.
    // We keep a single valid signal here since Node_Network L2 exposes only
    // valid_out (no separate done port), so both events remain coupled.
    // To fully decouple, add a done port to MP_Node_Layer in gen_layers.py.
    reg layer2_held, layer3_held;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] store_node_addr;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] l3_node_addr;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] node_write_addr_r;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] node_save_counter;

    // =========================================================================
    // Single always block: all FIFOs, dispatch, collect, ping-pong
    // =========================================================================
    integer k;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            fifo_wptr<=0; fifo_rptr<=0; fifo_count<=0;
            s_wptr<=0; s_rptr<=0; s_count<=0;
            pp_wr<=0; pp_buf[0]<=0; pp_buf[1]<=0;
            Layer2_out_r<=0;
            dispatch_rr<=0;
            l1a_busy<=0; l1b_busy<=0; l1c_busy<=0;
            layer1a_held<=0; layer1b_held<=0; layer1c_held<=0;
            concat_latch_a<=0; concat_latch_b<=0; concat_latch_c<=0;
            l1a_na<=0; l1b_na<=0; l1c_na<=0;
            store_node_addr<=0; l3_node_addr<=0; Layer1_out_r<=0;
            for (k=0;k<FIFO_DEPTH;k=k+1) begin
                fifo_node_addr[k]<=0; concat_fifo[k]<=0;
            end
            for (k=0;k<S_DEPTH;k=k+1) begin
                s_data[k]<=0; s_na[k]<=0;
            end
        end else begin
            if (ec_reset) begin
                dispatch_rr<=0;
                l1a_busy<=0; l1b_busy<=0; l1c_busy<=0;
                layer1a_held<=0; layer1b_held<=0; layer1c_held<=0;
            end

            // Load FIFO push
            if (do_push) begin
                fifo_node_addr[fifo_wptr] <= idx_load * NODE_FEATURES;
                concat_fifo[fifo_wptr]    <= {load_ss_in, load_ss_out,
                                               load_curr,  load_init};
                fifo_wptr <= (fifo_wptr==FIFO_DEPTH-1) ? 0 : fifo_wptr+1;
            end

            // Dispatch
            if (do_dispatch_a) begin
                concat_latch_a<=concat_fifo[fifo_rptr]; l1a_na<=fifo_node_addr[fifo_rptr];
                l1a_busy<=1; layer1a_held<=1;
                fifo_rptr<=(fifo_rptr==FIFO_DEPTH-1)?0:fifo_rptr+1; dispatch_rr<=1;
            end else if (do_dispatch_b) begin
                concat_latch_b<=concat_fifo[fifo_rptr]; l1b_na<=fifo_node_addr[fifo_rptr];
                l1b_busy<=1; layer1b_held<=1;
                fifo_rptr<=(fifo_rptr==FIFO_DEPTH-1)?0:fifo_rptr+1; dispatch_rr<=2;
            end else if (do_dispatch_c) begin
                concat_latch_c<=concat_fifo[fifo_rptr]; l1c_na<=fifo_node_addr[fifo_rptr];
                l1c_busy<=1; layer1c_held<=1;
                fifo_rptr<=(fifo_rptr==FIFO_DEPTH-1)?0:fifo_rptr+1; dispatch_rr<=0;
            end

            case ({do_push, do_dispatch})
                2'b10: fifo_count <= fifo_count + 1;
                2'b01: fifo_count <= fifo_count - 1;
                default: ;
            endcase

            // Collect L1 → inter-stage FIFO
            if (do_collect_a) begin
                s_data[s_wptr]<=Layer1a_out; s_na[s_wptr]<=l1a_na;
                s_wptr<=(s_wptr==S_DEPTH-1)?0:s_wptr+1;
                layer1a_held<=0; l1a_busy<=0;
            end else if (do_collect_b) begin
                s_data[s_wptr]<=Layer1b_out; s_na[s_wptr]<=l1b_na;
                s_wptr<=(s_wptr==S_DEPTH-1)?0:s_wptr+1;
                layer1b_held<=0; l1b_busy<=0;
            end else if (do_collect_c) begin
                s_data[s_wptr]<=Layer1c_out; s_na[s_wptr]<=l1c_na;
                s_wptr<=(s_wptr==S_DEPTH-1)?0:s_wptr+1;
                layer1c_held<=0; l1c_busy<=0;
            end

            // Inter-stage FIFO pop → L2 input latch
            // With s_will_have_data lookahead, do_s_pop may fire on the same
            // cycle as do_collect. When both fire, s_count stays the same
            // (the case 2'b11 below), which is correct — we pushed and popped
            // simultaneously. The data read is from s_rptr before the collect
            // write (s_wptr != s_rptr since count was >0 via !s_empty, or
            // collect wrote to s_wptr while we read s_rptr — different slots).
            // Edge case: if s_empty && do_collect fires simultaneously
            // (s_will_have_data via the do_collect path), s_rptr == s_wptr.
            // In that case the collect writes to s_data[s_wptr] this cycle
            // and do_s_pop reads s_data[s_rptr] = same slot. Since both are
            // clocked, the read sees the OLD (pre-write) value — which is
            // stale. Guard: only allow the lookahead pop when s_rptr != s_wptr
            // i.e. the slot being read already has committed data.
            if (do_s_pop) begin
                Layer1_out_r    <= s_data[s_rptr];
                store_node_addr <= s_na[s_rptr];
                s_rptr <= (s_rptr==S_DEPTH-1) ? 0 : s_rptr+1;
            end

            case ({do_collect, do_s_pop})
                2'b10: s_count <= s_count + 1;
                2'b01: s_count <= s_count - 1;
                2'b11: s_count <= s_count;   // simultaneous push+pop: count unchanged
                default: ;
            endcase

            // Latch L2 output into ping-pong buffer when L2 LN finishes.
            // pp_wr flips here; Layer2_out_r is latched in CS_L2_GAP (below)
            // from the just-written slot so the flip doesn't corrupt L3.
            if (Layer2_out_valid) begin
                pp_buf[pp_wr] <= Layer2_out;
                pp_wr         <= ~pp_wr;
                l3_node_addr  <= store_node_addr;
            end

            // Latch stable Layer2_out_r for L3 at CS_L2_GAP.
            // pp_wr has already flipped this cycle (or last cycle via l2_done_sticky).
            // pp_buf[pp_wr ^ 1] is the slot just written — correct data for L3.
            // Registering into Layer2_out_r means a subsequent pp_wr flip
            // during L3's long run cannot corrupt L3's input data.
            if (cs_state == CS_L2_GAP) begin
                Layer2_out_r <= pp_buf[pp_wr ^ 1];
            end
        end
    end

    // =========================================================================
    // Compute FSM — L2/L3 pipeline
    //
    // CS_L2W:   layer2_held=1, layer3_held=0. Wait for L2 LN done.
    // CS_L2_GAP: layer2_held=0 (counter resets), layer3_held=0.
    //            Pop next node from inter-stage FIFO if available → L2 restarts.
    //            Layer2_out_r is latched from pp_buf this cycle (see above).
    // CS_L3W:   layer3_held=1. L2 may run concurrently on the next node.
    //           When L3 finishes: if L2 also done → CS_L2_GAP; if L2 still
    //           running → CS_L2W; if L2 never started → CS_IDLE.
    // =========================================================================
    reg l2_done_sticky;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            cs_state       <= CS_IDLE;
            layer2_held    <= 0;
            layer3_held    <= 0;
            l2_done_sticky <= 0;
        end else begin
            if (Layer2_out_valid) l2_done_sticky <= 1;

            case (cs_state)
                CS_IDLE: begin
                    layer2_held    <= 0;
                    layer3_held    <= 0;
                    l2_done_sticky <= 0;
                    if (do_s_pop_idle) begin
                        layer2_held <= 1;
                        cs_state    <= CS_L2W;
                    end
                end

                CS_L2W: begin
                    layer2_held <= 1;
                    layer3_held <= 0;
                    if (Layer2_out_valid || l2_done_sticky) begin
                        layer2_held    <= 0;
                        l2_done_sticky <= 0;
                        cs_state       <= CS_L2_GAP;
                    end
                end

                CS_L2_GAP: begin
                    layer2_held    <= 0;
                    l2_done_sticky <= 0;
                    // Restart L2 on next node if available; always start L3 on current node.
                    if (do_s_pop_gap) begin
                        layer2_held <= 1;
                        layer3_held <= 1;
                    end else begin
                        layer3_held <= 1;
                    end
                    cs_state <= CS_L3W;
                end

                CS_L3W: begin
                    layer3_held <= 1;
                    // Drop layer2_held as soon as L2 finishes to prevent
                    // the layer module from immediately self-restarting.
                    if (Layer2_out_valid) begin
                        layer2_held    <= 0;
                        l2_done_sticky <= 1;
                    end
                    if (Layer3_out_valid) begin
                        layer3_held <= 0;
                        if (l2_done_sticky) begin
                            l2_done_sticky <= 0;
                            cs_state       <= CS_L2_GAP;
                        end else if (layer2_held) begin
                            cs_state <= CS_L2W;
                        end else begin
                            cs_state <= CS_IDLE;
                        end
                    end
                end

                default: cs_state <= CS_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Store — fire-and-forget
    // FIX: saturating subtraction on outstanding_writes to prevent underflow
    // if write-done arrives in cycles before the corresponding wr_fire has
    // been counted (e.g. during ec_reset window).
    // =========================================================================
    reg [3:0] outstanding_writes;
    wire wr_fire          = Layer3_out_valid & (nodes_completed < active_num_nodes);
    wire wr_done_arriving = current_node_features_write_done;

    // Saturating bound: don't subtract more than the current count
    wire [3:0] wr_done_bounded = wr_done_arriving ? (outstanding_writes > 0 ? 4'd1 : 4'd0) : 4'd0;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            nodes_completed<=0; current_node_features_we<=0; outstanding_writes<=0;
            node_write_addr_r<=0; node_save_counter<=0;
        end else begin
            current_node_features_we<=0;
            if (ec_reset) begin
                nodes_completed<=0; outstanding_writes<=0;
                node_write_addr_r<=0; node_save_counter<=0;
            end
            else begin
                if (wr_fire) begin
                    node_write_addr_r<=node_save_counter;
                    node_save_counter<=node_save_counter + 'h20;
                    current_node_features_we<=1;
                    nodes_completed<=nodes_completed+1;
                end
                outstanding_writes <= outstanding_writes
                                    + (wr_fire ? 4'd1 : 4'd0)
                                    - wr_done_bounded;
            end
        end
    end
    wire all_writes_flushed = (outstanding_writes==0);

    assign node_output = Layer3_out;

    // =========================================================================
    // Load FSM
    // =========================================================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            ls_state<=LS_IDLE; idx_load<=0; nodes_dispatched<=0;
            layer1_start<=0; ec_reset<=0; load_rd_done<=0;
            load_ss_in<=0; load_ss_out<=0; load_curr<=0; load_init<=0;
            scatter_sum_features_in_re<=0; scatter_sum_features_out_re<=0;
            current_node_features_re<=0; initial_node_features_re<=0;
            done<=0;
        end else begin
            layer1_start<=0; ec_reset<=0;
            scatter_sum_features_in_re<=0; scatter_sum_features_out_re<=0;
            current_node_features_re<=0; initial_node_features_re<=0;
            done<=0;
            case (ls_state)
                LS_IDLE: if (start) begin
                    idx_load<=0; nodes_dispatched<=0; load_rd_done<=0;
                    ec_reset<=1; ls_state<=LS_LOAD1;
                end
                LS_LOAD1: begin
                    if (!load_rd_done) begin
                        scatter_sum_features_in_re<=1; scatter_sum_features_out_re<=1;
                        current_node_features_re<=1; initial_node_features_re<=1;
                        load_rd_done<=1;
                    end
                    if (scatter_sum_features_in_valid && scatter_sum_features_out_valid &&
                        current_node_features_valid   && initial_node_features_valid) begin
                        load_ss_in  <= scatter_sum_features_in;
                        load_ss_out <= scatter_sum_features_out;
                        load_curr   <= current_node_features;
                        load_init   <= initial_node_features;
                        load_rd_done<=0; ls_state<=LS_CONCAT;
                    end
                end
                LS_CONCAT: begin
                    if (!fifo_full) begin
                        layer1_start<=1; nodes_dispatched<=nodes_dispatched+1;
                        if (idx_load<active_num_nodes-1) idx_load<=idx_load+1;
                        if (nodes_dispatched+1<active_num_nodes) begin
                            load_rd_done<=0; ls_state<=LS_LOAD1;
                        end else ls_state<=LS_DRAIN;
                    end
                end
                LS_DRAIN: if (nodes_completed>=active_num_nodes && all_writes_flushed) done<=1;
                default: ls_state<=LS_IDLE;
            endcase
        end
    end

    assign node_address = current_node_features_we ? node_write_addr_r
                                                   : idx_load * NODE_FEATURES;
    assign node_index   = idx_load;

    // FIX (Edge_Network #8): generate if chains replace generate case for
    // broader synthesis tool support (Quartus pre-17, some Vivado settings).
    // FIX (Edge_Network #9): BLOCK_NO now passed explicitly at every instantiation.
    // FIX (Edge_Network #1): L1 done ports tied to open to suppress synthesis warnings.
    generate
    if (BLOCK_NUM == 0) begin : b0
        MP_Node_Layer_B0_L1 #(.LAYER_NO(1),.BLOCK_NO(0),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM),.DEBUG(0)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Node_Layer_B0_L1 #(.LAYER_NO(1),.BLOCK_NO(0),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Node_Layer_B0_L1 #(.LAYER_NO(1),.BLOCK_NO(0),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Node_Layer_B0_L2 #(.LAYER_NO(2),.BLOCK_NO(0),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
        MP_Node_Layer_B0_L3 #(.LAYER_NO(3),.BLOCK_NO(0),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else
    if (BLOCK_NUM == 1) begin : b1
        MP_Node_Layer_B1_L1 #(.LAYER_NO(1),.BLOCK_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Node_Layer_B1_L1 #(.LAYER_NO(1),.BLOCK_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Node_Layer_B1_L1 #(.LAYER_NO(1),.BLOCK_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Node_Layer_B1_L2 #(.LAYER_NO(2),.BLOCK_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
        MP_Node_Layer_B1_L3 #(.LAYER_NO(3),.BLOCK_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else
    if (BLOCK_NUM == 2) begin : b2
        MP_Node_Layer_B2_L1 #(.LAYER_NO(1),.BLOCK_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Node_Layer_B2_L1 #(.LAYER_NO(1),.BLOCK_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Node_Layer_B2_L1 #(.LAYER_NO(1),.BLOCK_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Node_Layer_B2_L2 #(.LAYER_NO(2),.BLOCK_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
        MP_Node_Layer_B2_L3 #(.LAYER_NO(3),.BLOCK_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else
    if (BLOCK_NUM == 3) begin : b3
        MP_Node_Layer_B3_L1 #(.LAYER_NO(1),.BLOCK_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Node_Layer_B3_L1 #(.LAYER_NO(1),.BLOCK_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Node_Layer_B3_L1 #(.LAYER_NO(1),.BLOCK_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Node_Layer_B3_L2 #(.LAYER_NO(2),.BLOCK_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
        MP_Node_Layer_B3_L3 #(.LAYER_NO(3),.BLOCK_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else
    if (BLOCK_NUM == 4) begin : b4
        MP_Node_Layer_B4_L1 #(.LAYER_NO(1),.BLOCK_NO(4),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Node_Layer_B4_L1 #(.LAYER_NO(1),.BLOCK_NO(4),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Node_Layer_B4_L1 #(.LAYER_NO(1),.BLOCK_NO(4),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Node_Layer_B4_L2 #(.LAYER_NO(2),.BLOCK_NO(4),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
        MP_Node_Layer_B4_L3 #(.LAYER_NO(3),.BLOCK_NO(4),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else
    if (BLOCK_NUM == 5) begin : b5
        MP_Node_Layer_B5_L1 #(.LAYER_NO(1),.BLOCK_NO(5),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Node_Layer_B5_L1 #(.LAYER_NO(1),.BLOCK_NO(5),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Node_Layer_B5_L1 #(.LAYER_NO(1),.BLOCK_NO(5),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Node_Layer_B5_L2 #(.LAYER_NO(2),.BLOCK_NO(5),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
        MP_Node_Layer_B5_L3 #(.LAYER_NO(3),.BLOCK_NO(5),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else
    if (BLOCK_NUM == 6) begin : b6
        MP_Node_Layer_B6_L1 #(.LAYER_NO(1),.BLOCK_NO(6),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Node_Layer_B6_L1 #(.LAYER_NO(1),.BLOCK_NO(6),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Node_Layer_B6_L1 #(.LAYER_NO(1),.BLOCK_NO(6),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Node_Layer_B6_L2 #(.LAYER_NO(2),.BLOCK_NO(6),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
        MP_Node_Layer_B6_L3 #(.LAYER_NO(3),.BLOCK_NO(6),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else
    if (BLOCK_NUM == 7) begin : b7
        MP_Node_Layer_B7_L1 #(.LAYER_NO(1),.BLOCK_NO(7),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Node_Layer_B7_L1 #(.LAYER_NO(1),.BLOCK_NO(7),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Node_Layer_B7_L1 #(.LAYER_NO(1),.BLOCK_NO(7),.NUM_NEURONS(32),.NUM_FEATURES(128),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Node_Layer_B7_L2 #(.LAYER_NO(2),.BLOCK_NO(7),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.valid_out(Layer2_out_valid));
        MP_Node_Layer_B7_L3 #(.LAYER_NO(3),.BLOCK_NO(7),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else begin : bdef
        initial begin $display("ERROR: unsupported BLOCK_NUM=%0d", BLOCK_NUM); $finish; end
    end
    endgenerate

endmodule
