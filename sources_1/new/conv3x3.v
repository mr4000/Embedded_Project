`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.03.2026 13:03:02
// Design Name: 
// Module Name: conv3x3
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module conv3x3(

input clk,
input valid_in,

input [7:0] p0,p1,p2,
input [7:0] p3,p4,p5,
input [7:0] p6,p7,p8,

input signed [15:0] w0,w1,w2,
input signed [15:0] w3,w4,w5,
input signed [15:0] w6,w7,w8,

output reg [31:0] conv_out,
output reg valid_out
);

wire signed [23:0] m0 = p0 * w0;
wire signed [23:0] m1 = p1 * w1;
wire signed [23:0] m2 = p2 * w2;
wire signed [23:0] m3 = p3 * w3;
wire signed [23:0] m4 = p4 * w4;
wire signed [23:0] m5 = p5 * w5;
wire signed [23:0] m6 = p6 * w6;
wire signed [23:0] m7 = p7 * w7;
wire signed [23:0] m8 = p8 * w8;

wire signed [31:0] sum =
      m0+m1+m2+
      m3+m4+m5+
      m6+m7+m8;

always @(posedge clk)
begin
    conv_out <= sum;
    valid_out <= valid_in;
end

endmodule
