`timescale 1ns / 1ps

module edge_decoder
#(
    parameter NUM_EDGES      = 4,
    parameter NUM_FEATURES   = 32,
    parameter DATA_BITS      = 8,
    parameter WEIGHT_BITS    = 8,
    parameter BIAS_BITS      = 8,
    parameter USE_RMS_NORM = 1,
    parameter ADDR_BITS      = 14,
    parameter OUT_FEATURES   = 32,
    parameter MEM_FILE       = "",
    parameter OUTPUT_FILE    = "edge_decoder_output.txt"
)
(
    input  clk,
    input  rstn,
    input  start,
    input  [ADDR_BITS-1:0] active_num_edges,

    // Current Edge features from the Edge PingPong 0 Buffer
    input  [DATA_BITS*NUM_FEATURES-1:0] edge_features,
    output reg              edge_features_re,
    input                   edge_features_valid,
    
    output reg [DATA_BITS-1:0] decoded_data,
    output reg [ADDR_BITS-1:0] edge_addr_out,
    output reg data_valid,
    
    output reg done
);

    //============================================
    // FSM States
    //============================================
    localparam [2:0] IDLE        = 3'b000,
                     READ_EDGE   = 3'b001,
                     LAYER1      = 3'b010,
                     LAYER2      = 3'b011,
                     LAYER3      = 3'b100,  // Added Layer3 state
                     WRITE       = 3'b101,
                     NEXT_EDGE   = 3'b110,
                     FINISH      = 3'b111;  // Added FINISH state
    
    reg [2:0] state, next_state;
    reg [ADDR_BITS-1:0] edge_idx;
    reg process_complete;
    
    //============================================
    // Internal Edge Memory
    //============================================
    reg [NUM_FEATURES*DATA_BITS-1:0] edge_mem [0:NUM_EDGES-1];
    reg [NUM_FEATURES*DATA_BITS-1:0] current_edge_data;
    
    //============================================
    // File handle for writing output
    //============================================
    integer output_file_handle = 0;
    integer edge_counter;
    integer byte_counter;
    integer file_handle;
    integer read_success;
    integer i;
    
    //============================================
    // Layer Interconnections
    //============================================
    reg layer1_start;
    reg layer2_start;
    reg layer3_start;

    wire [NUM_FEATURES*DATA_BITS-1:0] layer1_in;
    wire [OUT_FEATURES*DATA_BITS-1:0] layer1_out;
    wire layer1_done;
    
    wire [OUT_FEATURES*DATA_BITS-1:0] layer2_out;
    wire layer2_done;

    wire [DATA_BITS-1:0] layer3_out;
    wire layer3_done;
    
    // Data registers
    reg [OUT_FEATURES*DATA_BITS-1:0] layer1_out_reg;
    reg [OUT_FEATURES*DATA_BITS-1:0] layer2_out_reg;
    reg [DATA_BITS-1:0] decoded_features_reg;
    reg layer1_held, layer2_held, layer3_held;

    always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        layer1_held <= 0;
        layer2_held <= 0;
        layer3_held <= 0;
    end else begin
        // Default: deassert
        layer1_held <= 0;
        layer2_held <= 0;
        layer3_held <= 0;

        case (state)
            LAYER1: layer1_held <= 1;
            LAYER2: layer2_held <= 1;
            LAYER3: layer3_held <= 1;
        endcase
    end
end
    
    //============================================
    // Instantiate Layer 1
    //============================================
    Edge_Decoder_Layer #(
        .LAYER_NO      (1),
        .NUM_NEURONS   (OUT_FEATURES),
        .NUM_FEATURES  (NUM_FEATURES),
        .DATA_BITS     (DATA_BITS),
        .WEIGHT_BITS   (WEIGHT_BITS),
        .BIAS_BITS     (BIAS_BITS),
        .USE_RMS_NORM (USE_RMS_NORM)
    ) layer1_inst (
        .clk                 (clk),
        .rstn                (layer1_held),
        .activation_function (1'b1),
        .start (layer1_start), 
        .data_in_flat        (layer1_in),
        .data_out_flat       (layer1_out),
        .valid_out                (layer1_done)
    );
    
    //============================================
    // Instantiate Layer 2
    //============================================
    edge_output_layer #(
        .LAYER_NO      (1),
        .NUM_NEURONS   (32),
        .NUM_FEATURES  (OUT_FEATURES),
        .DATA_BITS     (DATA_BITS),
        .WEIGHT_BITS   (WEIGHT_BITS),
        .BIAS_BITS     (BIAS_BITS),
        .USE_RMS_NORM (USE_RMS_NORM)
    ) layer2_inst (
        .clk                 (clk),
        .rstn                (layer2_held),
        .activation_function (1'b1),
        .start (layer2_start),
        .data_in_flat        (layer1_out_reg),
        .data_out_flat       (layer2_out),
        .valid_out                (layer2_done)
    );

    edge_output_transform #(
        .LAYER_NO      (2),
        .NUM_NEURONS   (1),
        .NUM_FEATURES  (OUT_FEATURES),
        .DATA_BITS     (DATA_BITS),
        .WEIGHT_BITS   (WEIGHT_BITS),
        .BIAS_BITS     (BIAS_BITS)
    ) layer3_inst (
        .clk                 (clk),
        .rstn                (layer3_held),
        .activation_function (1'b0),  // No activation for final layer
        .start (layer3_start),  // Start when layer3 is enabled
        .data_in_flat        (layer2_out_reg),
        .data_out_flat       (layer3_out),
        .done                (layer3_done)
    );

    
    //============================================
    // Layer 1 Input Assignment
    //============================================
    assign layer1_in = current_edge_data;
    reg [DATA_BITS-1:0] temp_array [0:(NUM_EDGES*NUM_FEATURES)-1];
    integer j, k;
    
    //============================================
    // State Register
    //============================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
        end else begin
            // if (state != next_state) begin
            //     case (next_state)
            //         // IDLE:       $display("[DECODER][%0t] FSM: IDLE (edge_idx=%0d)", $time, edge_idx);
            //         // READ_EDGE:  $display("[DECODER][%0t] FSM: READ_EDGE (edge_idx=%0d)", $time, edge_idx);
            //         // LAYER1:     $display("[DECODER][%0t] FSM: LAYER1 (edge_idx=%0d)", $time, edge_idx);
            //         // LAYER2:     $display("[DECODER][%0t] FSM: LAYER2 (edge_idx=%0d, layer1_done=%b)", $time, edge_idx, layer1_done);
            //         // LAYER3:     $display("[DECODER][%0t] FSM: LAYER3 (edge_idx=%0d, layer2_done=%b)", $time, edge_idx, layer2_done);
            //         // WRITE:      $display("[DECODER][%0t] FSM: WRITE (edge_idx=%0d, layer2_done=%b)", $time, edge_idx, layer2_done);
            //         // NEXT_EDGE:  $display("[DECODER][%0t] FSM: NEXT_EDGE (edge_idx=%0d)", $time, edge_idx);
            //         // FINISH:     $display("[DECODER][%0t] FSM: FINISH (edge_idx=%0d)", $time, edge_idx);
            //     endcase
            // end
            state <= next_state;
        end
    end

    
    //============================================
    // Next State Logic - FIXED
    //============================================
    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (start) begin
                    next_state = READ_EDGE;
                    // $display("Decoder Start READ EDGE STATE");
                end
                    
            end
            
            READ_EDGE: begin
                if (edge_features_valid)
                next_state = LAYER1;
            end
            
            LAYER1: begin
                if (layer1_done)
                    next_state = LAYER2;
            end
            
            LAYER2: begin
                if (layer2_done)
                    next_state = LAYER3;
            end

            LAYER3: begin
                if (layer3_done)
                    next_state = WRITE;
            end
            
            WRITE: begin
                next_state = NEXT_EDGE;
            end
            
            NEXT_EDGE: begin
                if (edge_idx >= active_num_edges - 1)  // Last edge completed
                    next_state = FINISH;
                else
                    next_state = READ_EDGE;     // Process next edge
            end
            
            FINISH: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    //============================================
    // Edge Index Counter - FIXED
    //============================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            edge_idx <= 0;
            process_complete <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        edge_idx <= 0;
                        process_complete <= 0;
                    end
                end

                NEXT_EDGE: begin
                    if (edge_idx < active_num_edges - 1) begin
                        edge_idx <= edge_idx + 1;  // Increment only if not last edge
                    end
                end
                
                FINISH: begin
                    process_complete <= 1;  // Set complete flag in FINISH state
                    edge_idx <= 0;          // Reset index
                end
                
                default: ;
            endcase
        end
    end
    
    //============================================
    // Output Logic - FIXED
    //============================================
    always @(*) begin
        done = 0;
        decoded_data = 0;
        edge_addr_out = 0;
        data_valid = 0;
        edge_features_re = 0;
        
        case (state)
            IDLE: begin
                if (start && output_file_handle == 0 && OUTPUT_FILE != "") begin
                    output_file_handle = $fopen(OUTPUT_FILE, "w");
                end
            end

            READ_EDGE: begin
                edge_features_re = 1;
                edge_addr_out = edge_idx;
            end
            WRITE: begin
                decoded_data = decoded_features_reg;
                edge_addr_out = edge_idx;
                data_valid = 1;
                if (output_file_handle != 0 && OUTPUT_FILE != "") begin
                        $fwrite(output_file_handle, "%b\n", decoded_features_reg);
                    end
            end
            
            FINISH: begin
                done = 1;  // Assert done in FINISH state
                if (output_file_handle != 0 && OUTPUT_FILE != "") begin
                        $fclose(output_file_handle);
                        output_file_handle = 0;
                        // $display("[DECODER] Output file closed: %s", OUTPUT_FILE);
                    end
            end
            
            default: ;
        endcase
    end
    
    
    
    //============================================
    // Data Path Registers
    //============================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            current_edge_data <= 0;
            layer1_out_reg <= 0;
            layer2_out_reg <= 0;
            decoded_features_reg <= 0;
        end else begin
            case (state)
                READ_EDGE: begin
                    if (edge_features_valid) begin
                        current_edge_data <= edge_features;
                        $display("[DECODER][%0t]   Edge %0d READ_EDGE: edge_features=%h", $time, edge_idx, edge_features);
                    end
                end
                
                LAYER1: begin
                    if (layer1_done) begin
                        layer1_out_reg <= layer1_out;
                        $display("[DECODER][%0t]   Edge %0d Layer1 Output: %h", $time, edge_idx, layer1_out);
                    end
                end

                LAYER2: begin
                    if (layer2_done) begin
                        layer2_out_reg <= layer2_out;
                        $display("[DECODER][%0t]   Edge %0d Layer2 Output: %h", $time, edge_idx, layer2_out);
                    end
                end
                
                LAYER3: begin
                    // $display("[DECODER][%0t]   Edge %0d Layer3: layer3_start=%b, layer3_done=%b, layer3_out=%h", 
                    //        $time, edge_idx, layer3_start, layer3_done, layer3_out);
                    if (layer3_done) begin
                        decoded_features_reg <= layer3_out;
                        $display("[DECODER][%0t]   Edge %0d Layer3 Output (Final): %h", $time, edge_idx, layer3_out);
                    end
                end
                
                WRITE: begin
                    // $display("[DECODER][%0t]   Edge %0d WRITE: decoded_data=%h, valid=%b", 
                    //        $time, edge_idx, decoded_features_reg, 1'b1);
                end
                
                // FINISH: begin
                //     // $display("[DECODER][%0t] ========================================", $time);
                //     // $display("[DECODER][%0t] ALL %0d EDGES PROCESSED COMPLETELY", $time, NUM_EDGES);
                //     // $display("[DECODER][%0t] ========================================", $time);
                // end
                
                default: ;
            endcase
        end
    end

    initial begin
        if (OUTPUT_FILE != "") begin
            output_file_handle = $fopen(OUTPUT_FILE, "w");
            // if (output_file_handle == 0) begin
            //     $display("[DECODER] ERROR: Could not open output file: %s", OUTPUT_FILE);
            // end else begin
            //     $display("[DECODER] Output file opened: %s", OUTPUT_FILE);
            // end
        end
    end
    
    //============================================
    // Debug Display
    //============================================
    // initial begin
        // $display("========================================");
        // $display("Edge Encoder with Internal Memory Load");
        // $display("  Memory File:        %s", MEM_FILE);
        // $display("  Number of Edges:    %0d", NUM_EDGES);
        // $display("  Features per Edge:  %0d", NUM_FEATURES);
        // $display("  Total bits/edge:    %0d bits", NUM_FEATURES * DATA_BITS);
        // $display("  3-Layer Architecture:");
        // $display("    Layer 1: %0d -> %0d", NUM_FEATURES, OUT_FEATURES);
        // $display("    Layer 2: %0d -> %0d", OUT_FEATURES, OUT_FEATURES);
        // $display("    Layer 3: %0d -> %0d", OUT_FEATURES, OUT_FEATURES);
        // $display("========================================");
    // end

endmodule
