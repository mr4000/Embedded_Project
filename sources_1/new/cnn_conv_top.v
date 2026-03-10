//`timescale 1ns / 1ps

//module cnn_conv_top(

//input        clk,
//input        rst,

//input  [15:0] pixel_in,
//input        pixel_valid,

//input [(3*3)*16-1:0] weights,

//output [31:0] conv_out,
//output        conv_valid
//);

////--------------------------------------------------
//// Window generator
////--------------------------------------------------

//wire [71:0] window;
//wire window_valid;

//imageControl imgCtrl(
//.i_clk(clk),
//.i_rst(rst),
//.i_pixel_data(pixel_in[7:0]),
//.i_pixel_data_valid(pixel_valid),
//.o_pixel_data(window),
//.o_pixel_data_valid(window_valid),
//.o_intr()
//);

////--------------------------------------------------
//// Extract pixels
////--------------------------------------------------

//wire [7:0] p0 = window[71:64];
//wire [7:0] p1 = window[63:56];
//wire [7:0] p2 = window[55:48];

//wire [7:0] p3 = window[47:40];
//wire [7:0] p4 = window[39:32];
//wire [7:0] p5 = window[31:24];

//wire [7:0] p6 = window[23:16];
//wire [7:0] p7 = window[15:8];
//wire [7:0] p8 = window[7:0];

////--------------------------------------------------
//// Extract weights
////--------------------------------------------------

//wire signed [15:0] w0 = weights[16*0 +: 16];
//wire signed [15:0] w1 = weights[16*1 +: 16];
//wire signed [15:0] w2 = weights[16*2 +: 16];
//wire signed [15:0] w3 = weights[16*3 +: 16];
//wire signed [15:0] w4 = weights[16*4 +: 16];
//wire signed [15:0] w5 = weights[16*5 +: 16];
//wire signed [15:0] w6 = weights[16*6 +: 16];
//wire signed [15:0] w7 = weights[16*7 +: 16];
//wire signed [15:0] w8 = weights[16*8 +: 16];

////--------------------------------------------------
//// Debug window print
////--------------------------------------------------

////always @(posedge clk)
////if(window_valid)
////$display("WINDOW = %d %d %d  %d %d %d  %d %d %d",
////p0,p1,p2,
////p3,p4,p5,
////p6,p7,p8);

////--------------------------------------------------
//// Parallel convolution
////--------------------------------------------------

//conv3x3 conv0(

//.clk(clk),
//.valid_in(window_valid),

//.p0(p0), .p1(p1), .p2(p2),
//.p3(p3), .p4(p4), .p5(p5),
//.p6(p6), .p7(p7), .p8(p8),

//.w0(w0), .w1(w1), .w2(w2),
//.w3(w3), .w4(w4), .w5(w5),
//.w6(w6), .w7(w7), .w8(w8),

//.conv_out(conv_out),
//.valid_out(conv_valid)

//);

//endmodule


`timescale 1ns / 1ps
```verilog
//////////////////////////////////////////////////////////////////////////////////
// Module Name : cnn_top_pipeline
//
// Description :
// This module implements the first convolution layer of a CNN accelerator.
// The design processes a streaming grayscale image and performs 3×3 convolution
// using multiple filters in parallel.
//
// Pipeline Architecture:
//
//      Pixel Stream (128×128 image)
//                 │
//                 ▼
//          imageControl
//     (Line buffers + window generator)
//     Generates sliding 3×3 pixel window
//                 │
//                 ▼
//           cnn_layer16
//     (16 parallel 3×3 convolution units)
//     Each filter produces one feature value
//                 │
//                 ▼
//        Feature Map Outputs
//        16 parallel convolution results
//
// Data Flow:
//
//  Input image        : 128 × 128 × 1
//  Kernel size        : 3 × 3
//  Number of filters  : 16
//
//  Output feature maps: 128 × 128 × 16
//
// Each clock cycle (after pipeline fill):
//  • A new 3×3 window is generated
//  • 16 convolutions are computed in parallel
//  • 16 feature values are produced
//
// Implementation Notes:
//
//  • Pixels are 8-bit grayscale values
//  • Weights are signed 16-bit values
//  • Convolution results are 32-bit values
//  • Window generator outputs 72-bit window (9 pixels)
//
// This module forms the first stage of a CNN / U-Net hardware accelerator.
//
//////////////////////////////////////////////////////////////////////////////////
```

module cnn_top_pipeline(

input clk,
input rst,

input [7:0] pixel_in,
input pixel_valid,

input signed [16*9*16-1:0] weights,

output [16*32-1:0] features,
output [15:0] feature_valid

);

//--------------------------------------------------
// Window generator
//--------------------------------------------------

wire [71:0] window;
wire window_valid;

imageControl imgCtrl(

.i_clk(clk),
.i_rst(rst),
.i_pixel_data(pixel_in),
.i_pixel_data_valid(pixel_valid),

.o_pixel_data(window),
.o_pixel_data_valid(window_valid),
.o_intr()

);

//--------------------------------------------------
// Extract 3x3 pixels
//--------------------------------------------------

wire [7:0] p0 = window[71:64];
wire [7:0] p1 = window[63:56];
wire [7:0] p2 = window[55:48];

wire [7:0] p3 = window[47:40];
wire [7:0] p4 = window[39:32];
wire [7:0] p5 = window[31:24];

wire [7:0] p6 = window[23:16];
wire [7:0] p7 = window[15:8];
wire [7:0] p8 = window[7:0];

//--------------------------------------------------
// 16-filter CNN layer
//--------------------------------------------------

cnn_layer16 layer0(

.clk(clk),
.valid_in(window_valid),

.p0(p0), .p1(p1), .p2(p2),
.p3(p3), .p4(p4), .p5(p5),
.p6(p6), .p7(p7), .p8(p8),

.weights(weights),

.feature(features),
.valid_out(feature_valid)

);

endmodule
