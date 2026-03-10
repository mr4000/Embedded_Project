// -----------------------------------------------------------------------------
// Module Name : lineBuffer
// Purpose     : 1-D Line Buffer with Sliding 3-Sample Output Window
//
// Description :
//   - Stores incoming 8-bit streaming samples (e.g., grayscale pixels)
//   - Maintains separate read and write pointers
//   - Outputs three consecutive samples in parallel:
//           { sample[n], sample[n+1], sample[n+2] }
//
// Typical Use Cases:
//   - Image/video pipelines
//   - 1-D 3-tap FIR filter
//   - 1x3 convolution kernel
//   - Horizontal window extraction (for 3x3 Sobel, blur, sharpening, etc.)
//
// Notes:
//   - Implements single line buffer of depth 128
//   - No circular wrap logic added yet (overflow will naturally wrap because
//     of pointer width but not logically guarded)
//   - Output is combinational and always reflects current rd pointer window
// -----------------------------------------------------------------------------

module lineBuffer(
    input        i_clk,          // system clock
    input        i_rst,          // synchronous reset
    input  [7:0] i_data,         // incoming 8-bit sample/pixel
    input        i_data_valid,   // write enable for input data
    output [23:0] o_data,        // 3-sample parallel output window
    input        i_rd_data       // read enable / advance window
);

// -----------------------------------------------------------------------------
// Line buffer storage
// 128 x 8-bit memory to hold one line of data
// -----------------------------------------------------------------------------
reg [7:0] line [127:0];

// -----------------------------------------------------------------------------
// Write and read pointer declarations
// 7-bit because 2^7 = 128 entries
// -----------------------------------------------------------------------------
reg [6:0] wrPntr;   // points to next write location
reg [6:0] rdPntr;   // points to current read base index

// -----------------------------------------------------------------------------
// WRITE LOGIC
// Writes incoming sample into buffer when i_data_valid is high
// -----------------------------------------------------------------------------
always @(posedge i_clk) begin
    if (i_data_valid)
        line[wrPntr] <= i_data;
end

// -----------------------------------------------------------------------------
// WRITE POINTER UPDATE
// - Reset -> pointer = 0
// - On valid data -> increment pointer
//   (wrap-around relies implicitly on 7-bit width)
// -----------------------------------------------------------------------------
always @(posedge i_clk) begin
    if (i_rst)
        wrPntr <= 'd0;
    else if (i_data_valid)
        wrPntr <= wrPntr + 'd1;
end

// -----------------------------------------------------------------------------
// OUTPUT WINDOW FORMATION
// o_data packs 3 consecutive samples:
//   MSB -> line[rdPntr]
//         line[rdPntr+1]
//   LSB -> line[rdPntr+2]
//
// This gives a sliding 3-point window used in many filters/convolutions
// -----------------------------------------------------------------------------
assign o_data = { line[rdPntr],
                  line[rdPntr+1],
                  line[rdPntr+2] };

// -----------------------------------------------------------------------------
// READ POINTER UPDATE
// - Reset -> pointer = 0
// - On i_rd_data -> advance read window by 1 position
// -----------------------------------------------------------------------------
always @(posedge i_clk) begin
    if (i_rst)
        rdPntr <= 'd0;
    else if (i_rd_data)
        rdPntr <= rdPntr + 'd1;
end

endmodule
