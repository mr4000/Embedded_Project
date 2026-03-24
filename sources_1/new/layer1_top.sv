`timescale 1ns / 1ps

module layer1_top #(
    parameter NUM_FILTERS = 16,
    parameter int KERNEL_SIZE  = 9,
    parameter int PIXEL_WIDTH  = 8
)(
    input  logic clk,
    input  logic rst,

    // input stream
    input  logic signed [7:0] i_pixel_data,
    input  logic i_pixel_valid,

    // output
    output logic valid_out,
    output logic signed [7:0] out_pixel [NUM_FILTERS]
);

    // -------------------------
    // INTERNAL SIGNALS
    // -------------------------
    logic signed [71:0] window;
    logic window_valid;
    logic intr;

    // -------------------------
    // IMAGE CONTROL
    // -------------------------
    imageControl img_ctrl (
        .i_clk(clk),
        .i_rst(rst),
        .i_pixel_data(i_pixel_data),
        .i_pixel_data_valid(i_pixel_valid),
        .o_pixel_data(window),
        .o_pixel_data_valid(window_valid),
        .o_intr(intr)
    );
    
    

    // -------------------------
    // CNN LAYER
    // -------------------------
    layer1_multi #(
        .NUM_FILTERS(NUM_FILTERS)
    ) cnn (
        .clk(clk),
        .rst(rst),
        .valid_in(window_valid),
        .window(window),
        .valid_out(valid_out),
        .out_pixel(out_pixel)
    );


          

endmodule
