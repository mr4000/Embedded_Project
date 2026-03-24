`timescale 1ns / 1ps

`define PADDED_WIDTH   130
`define PADDED_HEIGHT  130
`define PADDED_SIZE    (`PADDED_WIDTH * `PADDED_HEIGHT)
`define EXPECTED_OUT   16384   // 128x128

module tb_layer1_top;

parameter int NUM_FILTERS = 16;

// ----------------------------------------
// CLOCK / RESET
// ----------------------------------------
reg clk;
reg rst;

initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// ----------------------------------------
// INPUT STREAM
// ----------------------------------------
reg signed [7:0] i_pixel_data;
reg i_pixel_valid;

// ----------------------------------------
// OUTPUT
// ----------------------------------------
wire valid_out;
logic signed [7:0] out_pixel [NUM_FILTERS];

// ----------------------------------------
// INTERNAL (row sync from imageControl)
// ----------------------------------------
wire intr;

// ----------------------------------------
// MEMORY (PADDED IMAGE)
// ----------------------------------------
logic signed [7:0] pixel_mem [0:`PADDED_SIZE-1];

// ----------------------------------------
// VARIABLES
// ----------------------------------------
integer i;
integer sentSize = 0;
integer receivedData = 0;
integer outfile;

// ----------------------------------------
// LOAD INPUT (IMPORTANT: PADDED IMAGE)
// ----------------------------------------
initial begin
    $readmemh("input_padded.mem", pixel_mem);

    outfile = $fopen("rtl_output.txt", "w");

    if (outfile == 0) begin
        $display("ERROR: could not open output file");
        $stop;
    end

    $display("Loaded input_padded.mem successfully");
end

// ----------------------------------------
// STIMULUS
// ----------------------------------------
initial begin
    rst = 1;
    i_pixel_valid = 0;
    i_pixel_data  = 0;

    #100;
    rst = 0;
    #50;

    // ------------------------------------
    // SEND FIRST 3 ROWS (PIPELINE FILL)
    // ------------------------------------
    for(i = 0; i < 3 * `PADDED_WIDTH; i++) begin
        @(posedge clk);
        i_pixel_data  <= pixel_mem[i];
        i_pixel_valid <= 1;
    end

    @(posedge clk);
    i_pixel_valid <= 0;
    sentSize = 3 * `PADDED_WIDTH;

    // ------------------------------------
    // REMAINING ROWS (INTR SYNC)
    // ------------------------------------
    while(sentSize < `PADDED_SIZE) begin
        @(posedge intr);

        for(i = 0; i < `PADDED_WIDTH; i++) begin
            @(posedge clk);
            if (sentSize + i < `PADDED_SIZE) begin
                i_pixel_data  <= pixel_mem[sentSize + i];
                i_pixel_valid <= 1;
            end
        end

        @(posedge clk);
        i_pixel_valid <= 0;
        sentSize += `PADDED_WIDTH;
    end
end

// ----------------------------------------
// OUTPUT CAPTURE
// ----------------------------------------
always @(posedge clk) begin
    if(valid_out) begin
        receivedData++;

        for(int j = 0; j < NUM_FILTERS; j++) begin
            $fwrite(outfile, "%0d ", $signed(out_pixel[j]));
        end
        $fwrite(outfile, "\n");

        if(receivedData % 1000 == 0)
            $display("Processed %0d / %0d", receivedData, `EXPECTED_OUT);
    end

    if(receivedData == `EXPECTED_OUT) begin
        $display("? SUCCESS DONE");
        $fclose(outfile);
        $stop;
    end
end

// ----------------------------------------
// DUT (TOP MODULE)
// ----------------------------------------
layer1_top #(
    .NUM_FILTERS(NUM_FILTERS)
) dut (
    .clk(clk),
    .rst(rst),

    .i_pixel_data(i_pixel_data),
    .i_pixel_valid(i_pixel_valid),

    .valid_out(valid_out),
    .out_pixel(out_pixel)
);

// ----------------------------------------
// INTR (FROM imageControl)
// ----------------------------------------
assign intr = dut.img_ctrl.o_intr;

endmodule
