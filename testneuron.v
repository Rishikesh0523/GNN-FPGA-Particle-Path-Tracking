`timescale 1ns / 1ps
// ============================================================
// neuron_tb — N=4 parallel MAC test
//
// NEURON_WIDTH=8, all inputs=3, all weights=2
// Expected: 8 × (3×2) = 48
//
// With N=4: counter runs 1..NEURON_WIDTH/4 = 1..2
// Pipeline trace:
//   counter=1: multiplier computes indices 0,1,2,3 → prod=6,6,6,6 → partial=24 (registered)
//   counter=2: multiplier computes indices 4,5,6,7 → prod=6,6,6,6 → partial=24 (registered)
//              accumulator loads partial from counter=1 = 24
//   counter=3: accumulator += partial from counter=2 = 24 → acc=48, data_out=24
//   counter=4: data_out = 48  ← STABLE
// ============================================================

module neuron_tb;

    localparam NEURON_WIDTH = 8;
    localparam DATA_BITS    = 8;
    localparam WEIGHT_BITS  = 8;
    localparam BIAS_BITS    = 8;
    localparam OUT_BITS     = DATA_BITS + WEIGHT_BITS + 8;  // 24
    localparam STEPS        = NEURON_WIDTH / 4;             // 2
    localparam PIPELINE_LAT = 2;
    localparam integer EXPECTED_OUT = 48;   // 8 × (3×2)

    reg                               clk;
    reg                               rstn;
    reg                               activation_function;
    reg  [NEURON_WIDTH*DATA_BITS-1:0] data_in_flat;
    reg  [31:0]                       counter;
    wire signed [OUT_BITS-1:0]        data_out;

    initial clk = 0;
    always #5 clk = ~clk;

    neuron #(
        .NEURON_WIDTH (NEURON_WIDTH),
        .DATA_BITS    (DATA_BITS),
        .WEIGHT_BITS  (WEIGHT_BITS),
        .BIAS_BITS    (BIAS_BITS),
        .WeightFile   ("test_weights.mif"),
        .BiasFile     ("test_bias.mif")
    ) dut (
        .clk                 (clk),
        .rstn                (rstn),
        .activation_function (activation_function),
        .data_in_flat        (data_in_flat),
        .counter             (counter),
        .data_out            (data_out)
    );

    initial begin
        $dumpfile("neuron_tb.vcd");
        $dumpvars(0, neuron_tb);
    end

    integer i;

    initial begin
        rstn                = 0;
        activation_function = 1;
        counter             = 0;
        // All inputs = 3, packed: x[0]=3 at LSB
        data_in_flat = 0;
        begin : fill
            integer j;
            for (j = 0; j < NEURON_WIDTH; j = j + 1)
                data_in_flat[j*DATA_BITS +: DATA_BITS] = 8'sd3;
        end

        repeat(2) @(posedge clk); #1;
        rstn = 1;

        $display("=====================================================");
        $display("  N=4 parallel MAC neuron test");
        $display("  NEURON_WIDTH=%0d  DATA=%0d-bit  WEIGHT=%0d-bit",
                 NEURON_WIDTH, DATA_BITS, WEIGHT_BITS);
        $display("  inputs=all 3  weights=all 2  bias=0");
        $display("  STEPS=%0d (counter runs 1..%0d)", STEPS, STEPS);
        $display("  expected = %0d", EXPECTED_OUT);
        $display("=====================================================");
        $display("  ctr   data_out   note");
        $display("-----------------------------------------------------");

        // Run counter 1 .. STEPS + PIPELINE_LAT
        for (i = 1; i <= STEPS + PIPELINE_LAT; i = i + 1) begin
            counter = i;
            @(posedge clk); #1;
            $display("  %0d     %0d %s",
                counter, $signed(data_out),
                (i <= STEPS)          ? "<- MAC"    :
                (i == STEPS+1)        ? "<- flush"  :
                                        "<- stable/read here");
        end

        $display("=====================================================");
        if ($signed(data_out) === EXPECTED_OUT)
            $display("  RESULT: PASS  data_out = %0d", $signed(data_out));
        else
            $display("  RESULT: FAIL  got %0d  expected %0d",
                     $signed(data_out), EXPECTED_OUT);
        $display("=====================================================");

        $finish;
    end

endmodule