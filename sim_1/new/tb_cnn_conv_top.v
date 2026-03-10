//`timescale 1ns/1ps

//module tb_cnn_conv_top;

//    reg clk;
//    reg rst;
    
//    reg [15:0] pixel_in;
//    reg pixel_valid;
    
//    wire [31:0] conv_out;
//    wire conv_valid;
    
//    reg [(3*3)*16-1:0] weights;
    
//    cnn_conv_top DUT(
    
//    .clk(clk),
//    .rst(rst),
    
//    .pixel_in(pixel_in),
//    .pixel_valid(pixel_valid),
    
//    .weights(weights),
    
//    .conv_out(conv_out),
//    .conv_valid(conv_valid)
    
//    );
    
//    //--------------------------------
//    // Clock
//    //--------------------------------
    
//    always #5 clk = ~clk;
    
    
//    //--------------------------------
//    // Image generation
//    //--------------------------------
    
//    integer i;
    
//    initial begin
    
//    clk = 0;
//    rst = 1;
    
//    pixel_in = 0;
//    pixel_valid = 0;
    
//    #20
//    rst = 0;
    
    
//    //--------------------------------
//    // Kernel (all ones)
//    //--------------------------------
    
//    weights = {
//    16'd1,16'd1,16'd1,
//    16'd1,16'd1,16'd1,
//    16'd1,16'd1,16'd1
//    };
    
    
//    //--------------------------------
//    // Stream 128x128 image
//    //--------------------------------
    
//    #20
    
//    for(i=0;i<128*128;i=i+1)
//    begin
//        @(posedge clk);
//        pixel_valid = 1;
//        pixel_in = i % 256;
//    end
    
//    @(posedge clk);
//    pixel_valid = 0;
    
//    #2000
    
//    $finish;
    
//    end
    
    
//    //--------------------------------
//    // Monitor outputs
//    //--------------------------------
    
//    always @(posedge clk)
//    begin
//        if(conv_valid)
//            $display("time=%0t conv_out=%d", $time, conv_out);
//    end


//endmodule


`timescale 1ns/1ps

module tb_cnn_top_pipeline;

reg clk;
reg rst;

reg [7:0] pixel_in;
reg pixel_valid;

wire [16*32-1:0] features;
wire [15:0] feature_valid;

reg signed [16*9*16-1:0] weights;

cnn_top_pipeline DUT(

.clk(clk),
.rst(rst),

.pixel_in(pixel_in),
.pixel_valid(pixel_valid),

.weights(weights),

.features(features),
.feature_valid(feature_valid)

);

//--------------------------------
// Clock
//--------------------------------

always #5 clk = ~clk;


//--------------------------------
// Variables
//--------------------------------

integer i;
integer f;
integer count;


//--------------------------------
// Initial block
//--------------------------------

initial begin

clk = 0;
rst = 1;

pixel_in = 0;
pixel_valid = 0;

count = 0;

#20
rst = 0;


//--------------------------------
// Initialize weights
//--------------------------------
// All weights = 1 (easy to verify)

for(i=0;i<16*9;i=i+1)
begin
    weights[i*16 +: 16] = 16'd1;
end


//--------------------------------
// Stream image (128x128)
//--------------------------------

#20

for(i=0;i<128*128;i=i+1)
begin
    @(posedge clk);
    pixel_valid = 1;
    pixel_in = i % 256;
end

@(posedge clk);
pixel_valid = 0;

end


//--------------------------------
// Monitor outputs
//--------------------------------

always @(posedge clk)
begin
    if(feature_valid[0])
    begin

        count = count + 1;

        $display("time=%0t  output=%0d", $time, count);

        for(f=0; f<16; f=f+1)
        begin
            $display("feature[%0d] = %d",
                f,
                features[f*32 +: 32]
            );
        end

        $display("-------------------------");


        //--------------------------------
        // Exit after enough outputs
        //--------------------------------

        if(count == 10)
        begin
            $display("Simulation finished after %d outputs", count);
            $finish;
        end

    end
end

endmodule
