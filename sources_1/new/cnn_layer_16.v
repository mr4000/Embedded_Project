module cnn_layer16(

input clk,
input valid_in,

input [7:0] p0,p1,p2,
input [7:0] p3,p4,p5,
input [7:0] p6,p7,p8,

input signed [16*9*16-1:0] weights,

output [16*32-1:0] feature,
output [15:0] valid_out

);

genvar i;

generate

for(i=0;i<16;i=i+1)
begin: FILTERS

conv3x3 conv(

.clk(clk),
.valid_in(valid_in),

.p0(p0), .p1(p1), .p2(p2),
.p3(p3), .p4(p4), .p5(p5),
.p6(p6), .p7(p7), .p8(p8),

.w0(weights[(i*9+0)*16 +: 16]),
.w1(weights[(i*9+1)*16 +: 16]),
.w2(weights[(i*9+2)*16 +: 16]),
.w3(weights[(i*9+3)*16 +: 16]),
.w4(weights[(i*9+4)*16 +: 16]),
.w5(weights[(i*9+5)*16 +: 16]),
.w6(weights[(i*9+6)*16 +: 16]),
.w7(weights[(i*9+7)*16 +: 16]),
.w8(weights[(i*9+8)*16 +: 16]),

.conv_out(feature[i*32 +: 32]),
.valid_out(valid_out[i])

);

end

endgenerate

endmodule