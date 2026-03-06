`timescale 1ns / 1ps
//==============================================================================
// Edge_Network_Pipelined — 3× L1 round-robin + L2/L3 pipeline
//
// L2/L3 pipeline via CS_L2_GAP:
//   CS_L2W:    L2 runs on edge k
//   CS_L2_GAP: layer2_held=0 for 1cy (counter resets), layer3_held=1 (L3 starts on k)
//              if inter-stage FIFO has edge k+1: load it, L2 restarts next cycle
//   CS_L3W:    L3 runs on edge k, L2 may run concurrently on edge k+1
//
// Throughput: max(L2_time, L3_time) = one layer time (they are equal)
//==============================================================================
module Edge_Network #(
    parameter BLOCK_NUM              = 0,
    parameter DATA_BITS              = 8,
    parameter USE_RMS_NORM           = 1,
    parameter RAM_ADDR_BITS_FOR_NODE = 0,
    parameter RAM_ADDR_BITS_FOR_EDGE = 0,
    parameter NODE_FEATURES          = 32,
    parameter EDGE_FEATURES          = 32,
    parameter MAX_EDGES              = 0
) (
    input  clk, input rstn, input start,
    input  [RAM_ADDR_BITS_FOR_EDGE-6:0] active_num_edges,
    input  [DATA_BITS*EDGE_FEATURES-1:0] initial_edge_features,
    output reg initial_edge_features_re,
    input      initial_edge_features_valid,
    input  [DATA_BITS*EDGE_FEATURES-1:0] current_edge_features,
    output reg current_edge_features_re,
    input      current_edge_features_valid,
    output reg current_edge_features_we,
    input      current_edge_features_write_done,
    input  [DATA_BITS*NODE_FEATURES-1:0] initial_node_features,
    output reg initial_node_features_re,
    input      initial_node_features_valid,
    input  [DATA_BITS*NODE_FEATURES-1:0] current_node_features,
    output reg current_node_features_re,
    input      current_node_features_valid,
    input  [RAM_ADDR_BITS_FOR_NODE-1:0] source_node_index,
    output reg source_node_index_re,
    input      source_node_index_valid,
    input  [RAM_ADDR_BITS_FOR_NODE-1:0] destination_node_index,
    output reg destination_node_index_re,
    input      destination_node_index_valid,
    output [RAM_ADDR_BITS_FOR_EDGE-1:0] edge_address,
    output [RAM_ADDR_BITS_FOR_EDGE-1:0] load_edge_address,
    output [RAM_ADDR_BITS_FOR_EDGE-6:0] edge_index,
    output [RAM_ADDR_BITS_FOR_NODE-1:0] in_node_index_ss,
    input  in_node_ss_write_done,
    output [RAM_ADDR_BITS_FOR_NODE-1:0] out_node_index_ss,
    output reg scatter_sum_we,
    input  out_node_ss_write_done,
    output reg [RAM_ADDR_BITS_FOR_NODE-1:0] node_index,
    output reg [DATA_BITS*EDGE_FEATURES-1:0] edge_output,
    output reg done
);

    // =========================================================================
    // Load FIFO
    // =========================================================================
    localparam FIFO_DEPTH=(MAX_EDGES > 1) ? MAX_EDGES : 2;
    localparam FIFO_AW=$clog2(FIFO_DEPTH);
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0]    fifo_edge_addr [0:FIFO_DEPTH-1];
    reg [RAM_ADDR_BITS_FOR_NODE-1:0]    fifo_src       [0:FIFO_DEPTH-1];
    reg [RAM_ADDR_BITS_FOR_NODE-1:0]    fifo_dest      [0:FIFO_DEPTH-1];
    reg [6*EDGE_FEATURES*DATA_BITS-1:0] concat_fifo    [0:FIFO_DEPTH-1];
    reg [FIFO_AW-1:0] fifo_wptr, fifo_rptr;
    reg [FIFO_AW:0]   fifo_count;
    wire fifo_empty = (fifo_count == 0);
    wire fifo_full  = (fifo_count == FIFO_DEPTH);

    // =========================================================================
    // Load FSM
    // =========================================================================
    localparam LS_IDLE=3'd0, LS_LOAD1=3'd1, LS_LOAD2=3'd2,
               LS_LOAD3=3'd3, LS_CONCAT=3'd4, LS_DRAIN=3'd5;
    reg [2:0] ls_state;
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0] idx_load, edges_dispatched, edges_completed;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] load_src, load_dest;
    reg [DATA_BITS*NODE_FEATURES-1:0] load_init_src, load_curr_src;
    reg [DATA_BITS*NODE_FEATURES-1:0] load_init_dest, load_curr_dest;
    reg [DATA_BITS*EDGE_FEATURES-1:0] load_init_edge, load_curr_edge;
    reg load_rd1_done, load_rd2_done, load_rd3_done;
    reg layer1_start, ec_reset;
    wire do_push = layer1_start & ~fifo_full;

    // =========================================================================
    // 3× L1 round-robin
    // =========================================================================
    reg [6*EDGE_FEATURES*DATA_BITS-1:0] concat_latch_a, concat_latch_b, concat_latch_c;
    reg layer1a_held, layer1b_held, layer1c_held;
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0] l1a_ea, l1b_ea, l1c_ea;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] l1a_src, l1b_src, l1c_src;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] l1a_dst, l1b_dst, l1c_dst;
    reg l1a_busy, l1b_busy, l1c_busy;
    reg [1:0] dispatch_rr;

    wire [EDGE_FEATURES*DATA_BITS-1:0] Layer1a_out, Layer1b_out, Layer1c_out;
    reg [EDGE_FEATURES*DATA_BITS-1:0] Layer1a_out_reg, Layer1b_out_reg, Layer1c_out_reg;
    wire Layer1a_valid, Layer1b_valid, Layer1c_valid;

    wire do_dispatch_a = !fifo_empty && (dispatch_rr==0) && !l1a_busy;
    wire do_dispatch_b = !fifo_empty && (dispatch_rr==1) && !l1b_busy;
    wire do_dispatch_c = !fifo_empty && (dispatch_rr==2) && !l1c_busy;
    wire do_dispatch   = do_dispatch_a | do_dispatch_b | do_dispatch_c;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            Layer1a_out_reg <= 0;
            Layer1b_out_reg <= 0;
            Layer1c_out_reg <= 0;
        end else begin
            if (Layer1a_valid) begin
            Layer1a_out_reg <= Layer1a_out;
            // $display("[%0t] [DBG] LAYER1 edge=%0d  out[reg] = %0h",$time, idx_load, Layer1a_out);
            end 
                
            if (Layer1b_valid) Layer1b_out_reg <= Layer1b_out;
            if (Layer1c_valid) Layer1c_out_reg <= Layer1c_out;
        end
    end

    // =========================================================================
    // L1→L2 inter-stage FIFO
    // =========================================================================
    localparam S_DEPTH=(MAX_EDGES > 1) ? MAX_EDGES : 2;
    localparam S_AW=$clog2(S_DEPTH);
    reg [EDGE_FEATURES*DATA_BITS-1:0] s_data [0:S_DEPTH-1];
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0]  s_ea   [0:S_DEPTH-1];
    reg [RAM_ADDR_BITS_FOR_NODE-1:0]  s_src  [0:S_DEPTH-1];
    reg [RAM_ADDR_BITS_FOR_NODE-1:0]  s_dst  [0:S_DEPTH-1];
    reg [S_AW-1:0] s_wptr, s_rptr;
    reg [S_AW:0] s_count;
    wire s_empty = (s_count == 0);
    wire s_full  = (s_count == S_DEPTH);

    wire do_collect_a = Layer1a_valid && l1a_busy && !s_full;
    wire do_collect_b = Layer1b_valid && l1b_busy && !s_full && !do_collect_a;
    wire do_collect_c = Layer1c_valid && l1c_busy && !s_full && !do_collect_a && !do_collect_b;
    wire do_collect   = do_collect_a | do_collect_b | do_collect_c;

    // =========================================================================
    // Compute FSM
    // =========================================================================
    localparam CS_IDLE=3'd0, CS_L2W=3'd1, CS_L2_GAP=3'd2, CS_L3W=3'd3;
    reg [2:0] cs_state;

    // L2 pops inter-stage FIFO on IDLE or during L2_GAP (pipeline restart)
    wire do_s_pop_idle = (cs_state == CS_IDLE) && !s_empty;
    wire do_s_pop_gap  = (cs_state == CS_L2_GAP) && !s_empty;
    wire do_s_pop      = do_s_pop_idle || do_s_pop_gap;

    // L2/L3 signals
    reg layer2_held, layer3_held;
    wire [EDGE_FEATURES*DATA_BITS-1:0] Layer2_out, Layer3_out;
    wire Layer2_done;      // MAC done (~10cy) → FSM transition, drop layer2_held
    wire Layer2_valid;     // LN done  (~38cy) → latch pp_buf, data ready for L3
    wire Layer3_out_valid; // L3 LN done

    reg [DATA_BITS*EDGE_FEATURES-1:0] Layer1_out_r;
    // L2 output ping-pong buffer: L2 writes to pp_buf[pp_wr], flips pp_wr when done
    reg [DATA_BITS*EDGE_FEATURES-1:0] pp_buf [0:1];
    reg pp_wr;
    // L3 input: stable register latched when L3 starts (CS_L2_GAP)
    // Must NOT be a combinational wire from pp_buf — pp_wr flip would corrupt L3 mid-run
    reg [DATA_BITS*EDGE_FEATURES-1:0] Layer2_out_r;

    // Metadata: current edge in L2, current edge in L3
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0] l2_ea, l3_ea;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] l2_src, l2_dst;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] store_src_r, store_dst_r;
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0] l3_ea_stable;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] l3_src_stable, l3_dst_stable;
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0] edge_write_addr_r;
    reg [RAM_ADDR_BITS_FOR_EDGE-1:0] edge_save_counter;
    reg [RAM_ADDR_BITS_FOR_NODE-1:0] in_node_index_ss_r, out_node_index_ss_r;

    // =========================================================================
    // Single always block: FIFOs, dispatch, collect, ping-pong
    // =========================================================================
    integer k;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            fifo_wptr<=0; fifo_rptr<=0; fifo_count<=0;
            s_wptr<=0; s_rptr<=0; s_count<=0;
            pp_wr<=0; pp_buf[0]<=0; pp_buf[1]<=0;
            dispatch_rr<=0;
            l1a_busy<=0; l1b_busy<=0; l1c_busy<=0;
            layer1a_held<=0; layer1b_held<=0; layer1c_held<=0;
            concat_latch_a<=0; concat_latch_b<=0; concat_latch_c<=0;
            l1a_ea<=0; l1b_ea<=0; l1c_ea<=0;
            l1a_src<=0; l1b_src<=0; l1c_src<=0;
            l1a_dst<=0; l1b_dst<=0; l1c_dst<=0;
            Layer1_out_r<=0;
            Layer2_out_r<=0;
            l2_ea<=0; l2_src<=0; l2_dst<=0;
            l3_ea<=0; store_src_r<=0; store_dst_r<=0;
            l3_ea_stable<=0; l3_src_stable<=0; l3_dst_stable<=0;
            for (k=0;k<FIFO_DEPTH;k=k+1) begin
                fifo_edge_addr[k]<=0; fifo_src[k]<=0;
                fifo_dest[k]<=0; concat_fifo[k]<=0;
            end
            for (k=0;k<S_DEPTH;k=k+1) begin
                s_data[k]<=0; s_ea[k]<=0; s_src[k]<=0; s_dst[k]<=0;
            end
        end else begin

            // Load FIFO push
            if (do_push) begin
                fifo_edge_addr[fifo_wptr] <= idx_load * EDGE_FEATURES;
                fifo_src[fifo_wptr]       <= load_src;
                fifo_dest[fifo_wptr]      <= load_dest;
                concat_fifo[fifo_wptr]    <= {load_curr_edge, load_init_edge,
                                               load_curr_src,  load_init_src,
                                               load_curr_dest, load_init_dest};
                fifo_wptr <= (fifo_wptr==FIFO_DEPTH-1) ? 0 : fifo_wptr+1;
            end

            // Dispatch
            if (do_dispatch_a) begin
                concat_latch_a<=concat_fifo[fifo_rptr]; l1a_ea<=fifo_edge_addr[fifo_rptr];
                l1a_src<=fifo_src[fifo_rptr]; l1a_dst<=fifo_dest[fifo_rptr];
                l1a_busy<=1; layer1a_held<=1;
                fifo_rptr<=(fifo_rptr==FIFO_DEPTH-1)?0:fifo_rptr+1; dispatch_rr<=1;
            end else if (do_dispatch_b) begin
                concat_latch_b<=concat_fifo[fifo_rptr]; l1b_ea<=fifo_edge_addr[fifo_rptr];
                l1b_src<=fifo_src[fifo_rptr]; l1b_dst<=fifo_dest[fifo_rptr];
                l1b_busy<=1; layer1b_held<=1;
                fifo_rptr<=(fifo_rptr==FIFO_DEPTH-1)?0:fifo_rptr+1; dispatch_rr<=2;
            end else if (do_dispatch_c) begin
                concat_latch_c<=concat_fifo[fifo_rptr]; l1c_ea<=fifo_edge_addr[fifo_rptr];
                l1c_src<=fifo_src[fifo_rptr]; l1c_dst<=fifo_dest[fifo_rptr];
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
                s_data[s_wptr]<=Layer1a_out; s_ea[s_wptr]<=l1a_ea;
                s_src[s_wptr]<=l1a_src; s_dst[s_wptr]<=l1a_dst;
                s_wptr<=(s_wptr==S_DEPTH-1)?0:s_wptr+1;
                layer1a_held<=0; l1a_busy<=0;
                // $display("[%0t] [DBG] LAYER1 edge=%0d  out[full] = %0h",$time, l1a_ea, Layer1a_out);
            end else if (do_collect_b) begin
                s_data[s_wptr]<=Layer1b_out; s_ea[s_wptr]<=l1b_ea;
                s_src[s_wptr]<=l1b_src; s_dst[s_wptr]<=l1b_dst;
                s_wptr<=(s_wptr==S_DEPTH-1)?0:s_wptr+1;
                layer1b_held<=0; l1b_busy<=0;
                // $display("[%0t] [DBG] LAYER1 edge=%0d  out[full] = %0h",$time, l1b_ea, Layer1b_out);
            end else if (do_collect_c) begin
                s_data[s_wptr]<=Layer1c_out; s_ea[s_wptr]<=l1c_ea;
                s_src[s_wptr]<=l1c_src; s_dst[s_wptr]<=l1c_dst;
                s_wptr<=(s_wptr==S_DEPTH-1)?0:s_wptr+1;
                layer1c_held<=0; l1c_busy<=0;
                // $display("[%0t] [DBG] LAYER1 edge=%0d  out[full] = %0h",$time, l1c_ea, Layer1c_out);
            end

            case ({do_collect, do_s_pop})
                2'b10: s_count <= s_count + 1;
                2'b01: s_count <= s_count - 1;
                2'b11: s_count <= s_count;
                default: ;
            endcase

            // Pop inter-stage FIFO → L2 input
            if (do_s_pop) begin
                Layer1_out_r <= s_data[s_rptr];
                l2_ea        <= s_ea[s_rptr];
                // $display("[%0t] [DBG] LAYER2 edge=%0d  in = %0h",$time, s_ea[s_rptr], s_data[s_rptr]);
                l2_src       <= s_src[s_rptr];
                l2_dst       <= s_dst[s_rptr];
                s_rptr       <= (s_rptr==S_DEPTH-1) ? 0 : s_rptr+1;
            end

            // Latch L2 output into ping-pong buffer when L2 done fires
            // Latch L2 output when VALID (LN done ~38cy) — data_out_flat is ready
            if (Layer2_valid_r) begin
                pp_buf[pp_wr] <= Layer2_out;
                // $display("[%0t] [DBG] LAYER2 edge=%0d  out[full] = %0h",$time, l2_ea, Layer2_out);
                pp_wr         <= ~pp_wr;
                l3_ea         <= l2_ea;
                store_src_r  <= l2_src;
                store_dst_r  <= l2_dst;
            end

            // Latch stable Layer2_out_r for L3 in CS_L2_GAP
            // pp_wr has just flipped (Layer2_done fired this cycle or last)
            // pp_buf[pp_wr ^ 1] = the slot just written = correct data for L3
            // We latch into a stable register so pp_wr flipping again
            // during L3's computation doesn't corrupt L3's input
            if (cs_state == CS_L2_GAP) begin
                Layer2_out_r  <= pp_buf[pp_wr ^ 1'b1];
                l3_ea_stable  <= l3_ea;
                l3_src_stable <= store_src_r;
                l3_dst_stable <= store_dst_r;
            end
        end
    end
    reg Layer2_valid_r;

always @(posedge clk or negedge rstn) begin
    if (!rstn) Layer2_valid_r <= 0;
    else        Layer2_valid_r <= Layer2_valid;
end

    // =========================================================================
    // Compute FSM — L2/L3 pipeline
    //
    // CS_L2W:    layer2_held=1, layer3_held=0. Wait for L2 done.
    // CS_L2_GAP: layer2_held=0 (L2 counter resets), layer3_held=0.
    //            If next edge ready: pop FIFO → Layer1_out_r latches,
    //            set layer2_held=1 so L2 starts in CS_L3W.
    // CS_L3W:    layer3_held=1 on entry (same cycle layer2_held already 1).
    //            Both L2 and L3 see start=1 on first cycle of CS_L3W.
    //            Both finish same cycle → go to CS_L2_GAP for next pair.
    // =========================================================================
    reg l2_done_sticky;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            cs_state    <= CS_IDLE;
            layer2_held <= 0; layer3_held <= 0;
            l2_done_sticky <= 0;
        end else begin
            if (Layer2_valid_r) l2_done_sticky <= 1;

            case (cs_state)
                CS_IDLE: begin
                    layer2_held <= 0; layer3_held <= 0; l2_done_sticky <= 0;
                    if (do_s_pop_idle) begin
                        layer2_held <= 1; cs_state <= CS_L2W;
                    end
                end

                CS_L2W: begin
                    layer2_held <= 1; layer3_held <= 0;
                    if (Layer2_valid_r || l2_done_sticky) begin
                        layer2_held <= 0; l2_done_sticky <= 0;
                        cs_state <= CS_L2_GAP;
                        
                    end
                end

                CS_L2_GAP: begin
                    layer2_held <= 0; l2_done_sticky <= 0;
                    // Pre-load next edge and start both L2 and L3 simultaneously
                    // Both layer2_held and layer3_held become 1 at end of this cycle
                    // → both counters start from 0 on first cycle of CS_L3W
                    if (do_s_pop_gap) begin
                        layer2_held <= 1; // L2 starts on first cycle of CS_L3W
                        layer3_held <= 1; // L3 also starts on first cycle of CS_L3W
                    end else begin
                        layer3_held <= 1; // L3 starts even without pipeline
                    end
                    cs_state <= CS_L3W;
                end

                CS_L3W: begin
                    layer3_held <= 1;
                    // Drop layer2_held as soon as L2 valid_out fires
                    // to prevent layer module from immediately restarting
                    if (Layer2_valid_r) begin
                        layer2_held <= 0; l2_done_sticky <= 1;
                    end
                    if (Layer3_out_valid) begin
                        layer3_held <= 0;
                        // $display("[%0t] [DBG] LAYER3 edge=%0d  out[full] = %0h",$time, l3_ea, Layer3_out);
                        if (l2_done_sticky) begin
                            // L2 already finished → go to GAP for next edge
                            l2_done_sticky <= 0;
                            cs_state <= CS_L2_GAP;
                        end else if (layer2_held) begin
                            // L2 still running
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
    // =========================================================================
    reg [4:0] outstanding_writes;
    wire wr_fire  = Layer3_out_valid & (edges_completed < active_num_edges);
    wire [2:0] wr_dones = current_edge_features_write_done
                        + in_node_ss_write_done + out_node_ss_write_done;

    wire [4:0] wr_dones_bounded = (wr_dones > outstanding_writes) ? outstanding_writes[2:0] : wr_dones;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            edges_completed<=0; edge_output<=0;
            current_edge_features_we<=0; scatter_sum_we<=0; outstanding_writes<=0;
            edge_write_addr_r<=0; edge_save_counter<=0;
            in_node_index_ss_r<=0; out_node_index_ss_r<=0;
        end else begin
            current_edge_features_we<=0; scatter_sum_we<=0;
            if (ec_reset) begin
                edges_completed<=0; outstanding_writes<=0;
                edge_write_addr_r<=0; edge_save_counter<=0;
                in_node_index_ss_r<=0; out_node_index_ss_r<=0;
            end
            else begin
                if (wr_fire) begin
                    edge_output<=Layer3_out;
                    edge_write_addr_r<=edge_save_counter;
                    edge_save_counter<=edge_save_counter + 'h20;
                    in_node_index_ss_r<=l3_dst_stable * NODE_FEATURES;
                    out_node_index_ss_r<=l3_src_stable * NODE_FEATURES;
                    current_edge_features_we<=1; scatter_sum_we<=1;
                    edges_completed<=edges_completed+1;
                end
                // Saturating subtraction prevents underflow if write-done pulses
                // arrive before the corresponding wr_fire has been counted
                outstanding_writes <= outstanding_writes + (wr_fire ? 3 : 0) - wr_dones_bounded;
            end
        end
    end
    wire all_writes_flushed = (outstanding_writes==0);


    // =========================================================================
    // Load FSM
    // =========================================================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            ls_state<=LS_IDLE; idx_load<=0; edges_dispatched<=0;
            layer1_start<=0; ec_reset<=0;
            load_rd1_done<=0; load_rd2_done<=0; load_rd3_done<=0;
            load_src<=0; load_dest<=0;
            load_init_src<=0; load_curr_src<=0;
            load_init_dest<=0; load_curr_dest<=0;
            load_init_edge<=0; load_curr_edge<=0;
            initial_edge_features_re<=0; current_edge_features_re<=0;
            initial_node_features_re<=0; current_node_features_re<=0;
            source_node_index_re<=0; destination_node_index_re<=0;
            node_index<=0; done<=0;
        end else begin
            layer1_start<=0; ec_reset<=0;
            initial_edge_features_re<=0; current_edge_features_re<=0;
            initial_node_features_re<=0; current_node_features_re<=0;
            source_node_index_re<=0; destination_node_index_re<=0;
            done<=0;
            case (ls_state)
                LS_IDLE: if (start) begin
                    idx_load<=0; edges_dispatched<=0;
                    load_rd1_done<=0; load_rd2_done<=0; load_rd3_done<=0;
                    ec_reset<=1; ls_state<=LS_LOAD1;
                end
                LS_LOAD1: begin
                    if (!load_rd1_done) begin
                        initial_edge_features_re<=1; current_edge_features_re<=1;
                        source_node_index_re<=1; destination_node_index_re<=1;
                        load_rd1_done<=1;
                    end
                    if (initial_edge_features_valid && current_edge_features_valid &&
                        source_node_index_valid && destination_node_index_valid) begin
                        load_init_edge<=initial_edge_features; load_curr_edge<=current_edge_features;
                        load_src<=source_node_index; load_dest<=destination_node_index;
                        load_rd1_done<=0; ls_state<=LS_LOAD2;
                    end
                end
                LS_LOAD2: begin
                    if (!load_rd2_done) begin
                        node_index<=load_src*NODE_FEATURES;
                        initial_node_features_re<=1; current_node_features_re<=1;
                        load_rd2_done<=1;
                    end
                    if (initial_node_features_valid && current_node_features_valid) begin
                        load_init_src<=initial_node_features; load_curr_src<=current_node_features;
                        load_rd2_done<=0; ls_state<=LS_LOAD3;
                    end
                end
                LS_LOAD3: begin
                    if (!load_rd3_done) begin
                        node_index<=load_dest*NODE_FEATURES;
                        initial_node_features_re<=1; current_node_features_re<=1;
                        load_rd3_done<=1;
                    end
                    if (initial_node_features_valid && current_node_features_valid) begin
                        load_init_dest<=initial_node_features; load_curr_dest<=current_node_features;
                        load_rd3_done<=0; ls_state<=LS_CONCAT;
                    end
                end
                LS_CONCAT: begin
            //         $display("[%0t] PUSH: init_src=%0h curr_src=%0h init_dst=%0h curr_dst=%0h init_e=%0h curr_e=%0h",
            //  $time, load_init_src, load_curr_src, load_init_dest, load_curr_dest,
            //  load_init_edge, load_curr_edge);
                    if (!fifo_full) begin
                        layer1_start<=1; edges_dispatched<=edges_dispatched+1;
                        if (idx_load<active_num_edges-1) idx_load<=idx_load+1;
                        if (edges_dispatched+1<active_num_edges) begin
                            load_rd1_done<=0; load_rd2_done<=0; load_rd3_done<=0;
                            ls_state<=LS_LOAD1;
                        end else ls_state<=LS_DRAIN;
                    end
                end
                LS_DRAIN: if (edges_completed>=active_num_edges && all_writes_flushed) done<=1;
                default: ls_state<=LS_IDLE;
            endcase
        end
    end

    assign load_edge_address = idx_load * EDGE_FEATURES;
    assign edge_index        = idx_load;
    assign edge_address      = edge_write_addr_r;
    assign out_node_index_ss = out_node_index_ss_r;
    assign in_node_index_ss  = in_node_index_ss_r;

    // generate if chains replace generate case for broader synthesis tool support.
    // BLOCK_NO is now passed explicitly at every instantiation.
    // L1 done ports are tied to open (L1 completion is tracked via valid_out/busy,
    // not via done; tying explicitly eliminates synthesis warnings).
    generate
    if (BLOCK_NUM == 0) begin : b0
        MP_Edge_Layer_B0_L1 #(.LAYER_NO(1),.BLOCK_NO(0),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM),.DEBUG(0)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Edge_Layer_B0_L1 #(.LAYER_NO(1),.BLOCK_NO(0),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM),.DEBUG(0)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Edge_Layer_B0_L1 #(.LAYER_NO(1),.BLOCK_NO(0),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM),.DEBUG(0)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Edge_Layer_B0_L2 #(.LAYER_NO(2),.BLOCK_NO(0),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.done(Layer2_done),.valid_out(Layer2_valid));
        MP_Edge_Layer_B0_L3 #(.LAYER_NO(3),.BLOCK_NO(0),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM),.DEBUG(0)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else
    if (BLOCK_NUM == 1) begin : b1
        MP_Edge_Layer_B1_L1 #(.LAYER_NO(1),.BLOCK_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Edge_Layer_B1_L1 #(.LAYER_NO(1),.BLOCK_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Edge_Layer_B1_L1 #(.LAYER_NO(1),.BLOCK_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Edge_Layer_B1_L2 #(.LAYER_NO(2),.BLOCK_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.done(Layer2_done),.valid_out(Layer2_valid));
        MP_Edge_Layer_B1_L3 #(.LAYER_NO(3),.BLOCK_NO(1),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else
    if (BLOCK_NUM == 2) begin : b2
        MP_Edge_Layer_B2_L1 #(.LAYER_NO(1),.BLOCK_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Edge_Layer_B2_L1 #(.LAYER_NO(1),.BLOCK_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Edge_Layer_B2_L1 #(.LAYER_NO(1),.BLOCK_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Edge_Layer_B2_L2 #(.LAYER_NO(2),.BLOCK_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.done(Layer2_done),.valid_out(Layer2_valid));
        MP_Edge_Layer_B2_L3 #(.LAYER_NO(3),.BLOCK_NO(2),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else
    if (BLOCK_NUM == 3) begin : b3
        MP_Edge_Layer_B3_L1 #(.LAYER_NO(1),.BLOCK_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Edge_Layer_B3_L1 #(.LAYER_NO(1),.BLOCK_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Edge_Layer_B3_L1 #(.LAYER_NO(1),.BLOCK_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Edge_Layer_B3_L2 #(.LAYER_NO(2),.BLOCK_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.done(Layer2_done),.valid_out(Layer2_valid));
        MP_Edge_Layer_B3_L3 #(.LAYER_NO(3),.BLOCK_NO(3),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else
    if (BLOCK_NUM == 4) begin : b4
        MP_Edge_Layer_B4_L1 #(.LAYER_NO(1),.BLOCK_NO(4),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Edge_Layer_B4_L1 #(.LAYER_NO(1),.BLOCK_NO(4),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Edge_Layer_B4_L1 #(.LAYER_NO(1),.BLOCK_NO(4),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Edge_Layer_B4_L2 #(.LAYER_NO(2),.BLOCK_NO(4),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.done(Layer2_done),.valid_out(Layer2_valid));
        MP_Edge_Layer_B4_L3 #(.LAYER_NO(3),.BLOCK_NO(4),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else
    if (BLOCK_NUM == 5) begin : b5
        MP_Edge_Layer_B5_L1 #(.LAYER_NO(1),.BLOCK_NO(5),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Edge_Layer_B5_L1 #(.LAYER_NO(1),.BLOCK_NO(5),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Edge_Layer_B5_L1 #(.LAYER_NO(1),.BLOCK_NO(5),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Edge_Layer_B5_L2 #(.LAYER_NO(2),.BLOCK_NO(5),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.done(Layer2_done),.valid_out(Layer2_valid));
        MP_Edge_Layer_B5_L3 #(.LAYER_NO(3),.BLOCK_NO(5),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else
    if (BLOCK_NUM == 6) begin : b6
        MP_Edge_Layer_B6_L1 #(.LAYER_NO(1),.BLOCK_NO(6),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Edge_Layer_B6_L1 #(.LAYER_NO(1),.BLOCK_NO(6),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Edge_Layer_B6_L1 #(.LAYER_NO(1),.BLOCK_NO(6),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Edge_Layer_B6_L2 #(.LAYER_NO(2),.BLOCK_NO(6),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.done(Layer2_done),.valid_out(Layer2_valid));
        MP_Edge_Layer_B6_L3 #(.LAYER_NO(3),.BLOCK_NO(6),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else
    if (BLOCK_NUM == 7) begin : b7
        MP_Edge_Layer_B7_L1 #(.LAYER_NO(1),.BLOCK_NO(7),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1a (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1a_held),.data_in_flat(concat_latch_a),.data_out_flat(Layer1a_out),.valid_out(Layer1a_valid),.done());
        MP_Edge_Layer_B7_L1 #(.LAYER_NO(1),.BLOCK_NO(7),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1b (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1b_held),.data_in_flat(concat_latch_b),.data_out_flat(Layer1b_out),.valid_out(Layer1b_valid),.done());
        MP_Edge_Layer_B7_L1 #(.LAYER_NO(1),.BLOCK_NO(7),.NUM_NEURONS(32),.NUM_FEATURES(192),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l1c (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer1c_held),.data_in_flat(concat_latch_c),.data_out_flat(Layer1c_out),.valid_out(Layer1c_valid),.done());
        MP_Edge_Layer_B7_L2 #(.LAYER_NO(2),.BLOCK_NO(7),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l2 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer2_held),.data_in_flat(Layer1_out_r),.data_out_flat(Layer2_out),.done(Layer2_done),.valid_out(Layer2_valid));
        MP_Edge_Layer_B7_L3 #(.LAYER_NO(3),.BLOCK_NO(7),.NUM_NEURONS(32),.NUM_FEATURES(32),.DATA_BITS(8),.WEIGHT_BITS(8),.BIAS_BITS(8),.USE_RMS_NORM(USE_RMS_NORM)) l3 (.clk(clk),.rstn(rstn),.activation_function(1'b1),.start(layer3_held),.data_in_flat(Layer2_out_r),.data_out_flat(Layer3_out),.valid_out(Layer3_out_valid));
    end else begin : bdef
        initial begin $display("ERROR: unsupported BLOCK_NUM=%0d", BLOCK_NUM); $finish; end
    end
    endgenerate

endmodule
