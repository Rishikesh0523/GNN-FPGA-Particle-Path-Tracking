`timescale 1ns / 1ps
module bram_dual #(
    parameter RAM_WIDTH       = 8,  // Changed to 8-bit for weights/inputs/biases
    parameter RAM_ADDR_BITS   = 12,
    parameter DATA_FILE       = "",
    parameter INIT_START_ADDR = 0,
    parameter INIT_END_ADDR   = 0
)(
    input clock,

    // Port A (Write Port)
    input                     we_a,       // write enable
    input                     en_a,       // enable
    input [RAM_ADDR_BITS-1:0] addr_a,     // write address
    input [RAM_WIDTH-1:0]     din_a,      // data input

    // Port B (Read Port)
    input                     en_b,       // enable
    input [RAM_ADDR_BITS-1:0] addr_b,     // read address
    output reg [RAM_WIDTH-1:0] dout_b     // data output
);
    // Memory array
    // Synthesis attribute to infer block RAM
    (* RAM_STYLE = "ULTRA" *) 
    reg [RAM_WIDTH-1:0] ram_name [(2**RAM_ADDR_BITS)-1:0];
    
    // Initialize from file if provided
    initial begin
        if (DATA_FILE != "") begin
            $readmemb(DATA_FILE, ram_name, INIT_START_ADDR, INIT_END_ADDR);
        end
    end
    
    // Write port (Port A)
    always @(posedge clock) begin
        if (en_a && we_a) begin
            ram_name[addr_a] <= din_a;
        end
    end
    
    // Read port (Port B)
    always @(posedge clock) begin
        if (en_b) begin
            dout_b <= ram_name[addr_b];
        end
    end
endmodule