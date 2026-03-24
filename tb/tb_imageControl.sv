`timescale 1ns / 1ps

module tb_imageControl;

    parameter WIDTH  = 130;
    parameter HEIGHT = 130;
    parameter SIZE   = WIDTH * HEIGHT;

    reg clk;
    reg rst;
    logic signed [7:0] pixel_data;
    reg pixel_data_valid;

    logic signed[71:0] o_pixel_data;
    wire o_pixel_data_valid;
    wire o_intr;

    // memory
    logic signed [7:0] mem [0:SIZE-1];

    integer i;
    integer sent_pixels;

    // file dump
    integer f_out;
    integer win_count;

    //--------------------------------------------------
    // Clock (100 MHz)
    //--------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //--------------------------------------------------
    // Load memory
    //--------------------------------------------------
    initial begin
        $readmemh("input_padded.mem", mem);
        $display("Input memory loaded.");
    end

    //--------------------------------------------------
    // DUT
    //--------------------------------------------------
    imageControl dut (
        .i_clk(clk),
        .i_rst(rst),
        .i_pixel_data(pixel_data),
        .i_pixel_data_valid(pixel_data_valid),
        .o_pixel_data(o_pixel_data),
        .o_pixel_data_valid(o_pixel_data_valid),
        .o_intr(o_intr)
    );

    //--------------------------------------------------
    // File open
    //--------------------------------------------------
    initial begin
        f_out = $fopen("rtl_tensors.txt", "w");
        win_count = 0;

        if (f_out == 0) begin
            $display("ERROR: Cannot open rtl_tensors.txt");
            $stop;
        end
    end

    //--------------------------------------------------
    // Stimulus (FIXED)
    //--------------------------------------------------
    initial begin
        //--------------------------------------------------
        // INIT
        //--------------------------------------------------
        rst = 1;
        pixel_data = 0;
        pixel_data_valid = 0;
        sent_pixels = 0;

        repeat (5) @(posedge clk);
        rst = 0;

        //--------------------------------------------------
        // STEP 1: INITIAL PIPELINE FILL (CRITICAL)
        //--------------------------------------------------
        for (i = 0; i < 4*WIDTH; i = i + 1) begin
            @(negedge clk);
            pixel_data <= mem[i];
            pixel_data_valid <= 1;
        end

        @(negedge clk);
        pixel_data_valid <= 0;

        sent_pixels = 4*WIDTH;

        //--------------------------------------------------
        // STEP 2: CONTROLLED STREAMING
        //--------------------------------------------------
        while (sent_pixels < SIZE) begin

            wait(o_intr);
            @(posedge clk);

            for (i = 0; i < WIDTH; i = i + 1) begin
                @(negedge clk);
                if (sent_pixels + i < SIZE)
                    pixel_data <= mem[sent_pixels + i];
                else
                    pixel_data <= 0;

                pixel_data_valid <= 1;
            end

            @(negedge clk);
            pixel_data_valid <= 0;

            sent_pixels = sent_pixels + WIDTH;
        end

        //--------------------------------------------------
        // PIPELINE DRAIN
        //--------------------------------------------------
        repeat (2000) @(posedge clk);

        //--------------------------------------------------
        // FINISH
        //--------------------------------------------------
        $display("====================================");
        $display("Dump complete!");
        $display("Total windows = %0d", win_count);
        $display("====================================");

        $fclose(f_out);
        $finish;
    end

    //--------------------------------------------------
    // Dump ALL windows to file (UNCHANGED)
    //--------------------------------------------------
    always @(posedge clk) begin
        if (o_pixel_data_valid) begin
            win_count = win_count + 1;

            $fwrite(f_out, "%0d %0d %0d %0d %0d %0d %0d %0d %0d\n",
            $signed(o_pixel_data[23:16]),
            $signed(o_pixel_data[15:8]),
            $signed(o_pixel_data[7:0]),
        
            $signed(o_pixel_data[47:40]),
            $signed(o_pixel_data[39:32]),
            $signed(o_pixel_data[31:24]),
        
            $signed(o_pixel_data[71:64]),
            $signed(o_pixel_data[63:56]),
            $signed(o_pixel_data[55:48])
        );
        end
    end

endmodule
