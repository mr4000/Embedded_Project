`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.03.2026 11:04:42
// Design Name: 
// Module Name: imageControl
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

`timescale 1ns / 1ps

//This design streams a 128×128 image row-by-row into four rotating line buffers, using demultiplexer logic to store each incoming row into one buffer.
//Once three complete rows are available, the controller reads three line buffers in parallel, rotating the selection across rows.
//Each line buffer supplies horizontally adjacent pixels, and the controller multiplexes the outputs to form a sliding 3×3 pixel window suitable for convolution.

module imageControl(
    input            i_clk,
    input            i_rst,
    input [7:0]      i_pixel_data,
    input            i_pixel_data_valid,
    output [71:0]    o_pixel_data,
    output           o_pixel_data_valid,
    output  reg         o_intr
);

    // =============================================
    // Reset Synchronization
    // =============================================
    reg [2:0] reset_sync;
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) reset_sync <= 3'b111;
        else reset_sync <= {reset_sync[1:0], 1'b0};
    end
    wire sync_rst = reset_sync[2];

    // =============================================
    // Input Pipeline Registers
    // =============================================
    reg [7:0] i_pixel_data_r;
    reg i_pixel_data_valid_r;
    always @(posedge i_clk) begin
        i_pixel_data_r <= i_pixel_data;
        i_pixel_data_valid_r <= i_pixel_data_valid;
    end

    // =============================================
    // Line Buffer Control Logic (Registered)
    // =============================================
    reg [6:0] pixelCounter;
    reg [1:0] currentWrLineBuffer; 
    reg [3:0] lineBuffDataValid;
    reg [3:0] lineBuffRdData;
    reg [1:0] currentRdLineBuffer;
    wire [23:0] lb0data, lb1data, lb2data, lb3data;
    reg [6:0] rdCounter;
    reg rd_line_buffer;
    reg [11:0] totalPixelCounter;
    reg rdState;

    // Additional pipeline registers
    reg [1:0] currentRdLineBuffer_r;
    reg rd_line_buffer_r;
    reg [3:0] lineBuffDataValid_r;
    reg [3:0] lineBuffRdData_r;
    
    localparam IDLE = 1'b0,
               RD_BUFFER = 1'b1;

    assign o_pixel_data_valid = rd_line_buffer_r;

    // =============================================
    // Total Pixel Counter (Fixed Timing)
    // =============================================
    reg count_en, count_dir; // 1=inc, 0=dec
    
    always @(posedge i_clk or posedge sync_rst) begin
        if (sync_rst) begin
            totalPixelCounter <= 0;
            count_en <= 0;
            count_dir <= 0;
        end else begin
            count_en <= i_pixel_data_valid_r ^ rd_line_buffer;
            count_dir <= i_pixel_data_valid_r & ~rd_line_buffer;
            
            if (count_en) begin
                if (count_dir) totalPixelCounter <= totalPixelCounter + 1;
                else totalPixelCounter <= totalPixelCounter - 1;
            end
        end
    end

    // =============================================
    // Read State Machine (Registered Outputs)
    // =============================================
    always @(posedge i_clk or posedge sync_rst) begin
        if (sync_rst) begin
            rdState <= IDLE;
            rd_line_buffer <= 1'b0;
            o_intr <= 1'b0;
            rd_line_buffer_r <= 1'b0;
        end else begin
            rd_line_buffer_r <= rd_line_buffer;
            
            case(rdState)
                IDLE: begin
                    o_intr <= 1'b0;
                    if(totalPixelCounter >= 384) begin
                        rd_line_buffer <= 1'b1;
                        rdState <= RD_BUFFER;
                    end
                end
                RD_BUFFER: begin
                    if(rdCounter == 127) begin
                        rdState <= IDLE;
                        rd_line_buffer <= 1'b0;
                        o_intr <= 1'b1;
                    end
                end
            endcase
        end
    end

    // =============================================
    // Write Pointer Logic
    // =============================================
    always @(posedge i_clk or posedge sync_rst) begin
        if (sync_rst) begin
            pixelCounter <= 0;
            currentWrLineBuffer <= 0;
        end else begin
            if(i_pixel_data_valid_r) begin
                pixelCounter <= pixelCounter + 1;
                if(pixelCounter == 127)
                    currentWrLineBuffer <= currentWrLineBuffer + 1;
            end
        end
    end

    // =============================================
    // Registered Line Buffer Controls
    // =============================================
    always @(posedge i_clk or posedge sync_rst) begin
        if (sync_rst) begin
            lineBuffDataValid_r <= 4'h0;
            currentRdLineBuffer_r <= 0;
        end else begin
            // Registered WE generation
            lineBuffDataValid_r <= 4'h0;
            lineBuffDataValid_r[currentWrLineBuffer] <= i_pixel_data_valid_r;
            
            // Registered buffer pointers
            currentRdLineBuffer_r <= currentRdLineBuffer;
        end
    end

    // =============================================
    // Read Pointer Logic
    // =============================================
    always @(posedge i_clk or posedge sync_rst) begin
        if (sync_rst) begin
            rdCounter <= 0;
            currentRdLineBuffer <= 0;
        end else begin
            if(rd_line_buffer) begin
                rdCounter <= rdCounter + 1;
                if(rdCounter == 127)
                    currentRdLineBuffer <= currentRdLineBuffer + 1;
            end
        end
    end

    // =============================================
    // Registered Read Data Controls
    // =============================================
    always @(posedge i_clk or posedge sync_rst) begin
        if (sync_rst) begin
            lineBuffRdData_r <= 4'h0;
        end else begin
            lineBuffRdData_r <= 4'h0;
            case (currentRdLineBuffer_r)
                0: lineBuffRdData_r[2:0] <= {3{rd_line_buffer_r}};
                1: lineBuffRdData_r[3:1] <= {3{rd_line_buffer_r}};
                2: {lineBuffRdData_r[3:2], lineBuffRdData_r[0]} <= {3{rd_line_buffer_r}};
                3: {lineBuffRdData_r[3], lineBuffRdData_r[1:0]} <= {3{rd_line_buffer_r}};
            endcase
        end
    end

    // =============================================
    // Output Pixel Data (Registered)
    // =============================================
    reg [71:0] o_pixel_data_r;
    always @(posedge i_clk) begin
        case(currentRdLineBuffer_r)
            0: o_pixel_data_r <= {lb2data, lb1data, lb0data};
            1: o_pixel_data_r <= {lb3data, lb2data, lb1data};
            2: o_pixel_data_r <= {lb0data, lb3data, lb2data};
            3: o_pixel_data_r <= {lb1data, lb0data, lb3data};
        endcase
    end

    assign o_pixel_data = o_pixel_data_r;

    // =============================================
    // Line Buffer Instantiations
    // =============================================
    lineBuffer lB0(
        .i_clk(i_clk),
        .i_rst(sync_rst),
        .i_data(i_pixel_data_r),
        .i_data_valid(lineBuffDataValid_r[0]),
        .o_data(lb0data),
        .i_rd_data(lineBuffRdData_r[0])
    ); 
 
    lineBuffer lB1(
        .i_clk(i_clk),
        .i_rst(sync_rst),
        .i_data(i_pixel_data_r),
        .i_data_valid(lineBuffDataValid_r[1]),
        .o_data(lb1data),
        .i_rd_data(lineBuffRdData_r[1])
    ); 
  
    lineBuffer lB2(
        .i_clk(i_clk),
        .i_rst(sync_rst),
        .i_data(i_pixel_data_r),
        .i_data_valid(lineBuffDataValid_r[2]),
        .o_data(lb2data),
        .i_rd_data(lineBuffRdData_r[2])
    ); 
   
    lineBuffer lB3(
        .i_clk(i_clk),
        .i_rst(sync_rst),
        .i_data(i_pixel_data_r),
        .i_data_valid(lineBuffDataValid_r[3]),
        .o_data(lb3data),
        .i_rd_data(lineBuffRdData_r[3])
    );    

endmodule
