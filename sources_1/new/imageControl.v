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

`timescale 1ns / 1ps

module imageControl(
    input                    i_clk,
    input                    i_rst,
    input [7:0]              i_pixel_data,
    input                    i_pixel_data_valid,
    output reg [71:0]        o_pixel_data,
    output                   o_pixel_data_valid,
    output reg               o_intr
);

reg [7:0]  pixelCounter;         
reg [1:0]  currentWrLineBuffer;
reg [3:0]  lineBuffDataValid;
reg [3:0]  lineBuffRdData;
reg [1:0]  currentRdLineBuffer;
wire [23:0] lb0data;
wire [23:0] lb1data;
wire [23:0] lb2data;
wire [23:0] lb3data;
reg [7:0]  rdCounter;            
reg        rd_line_buffer;
reg [11:0] totalPixelCounter;    
reg        rdState;

// --- New Vertical Logic Registers ---
reg [6:0]  rowCounter; // Tracks 0 to 127 (7 bits)
reg        allRowsDone;

localparam IDLE = 'b0,
           RD_BUFFER = 'b1;

// Output valid only if we are reading AND we haven't finished the image
assign o_pixel_data_valid = rd_line_buffer && !allRowsDone;

// --- Buffer Occupancy Counter ---
always @(posedge i_clk) begin
    if(i_rst)
        totalPixelCounter <= 0;
    else begin
        if(i_pixel_data_valid && !rd_line_buffer)
            totalPixelCounter <= totalPixelCounter + 1;
        else if(!i_pixel_data_valid && rd_line_buffer)
            totalPixelCounter <= totalPixelCounter - 1; 
    end
end

// --- Read Control State Machine (with Vertical Limit) ---
always @(posedge i_clk) begin
    if(i_rst) begin
        rdState <= IDLE;
        rd_line_buffer <= 1'b0;
        o_intr <= 1'b0;
        rowCounter <= 0;
        allRowsDone <= 1'b0;
    end else begin
        case(rdState)
            IDLE: begin
                o_intr <= 1'b0;
                // Wait for 3 lines (390 pixels) AND ensure we aren't done with the image
                if(totalPixelCounter >= 390 && !allRowsDone) begin
                    rd_line_buffer <= 1'b1;
                    rdState <= RD_BUFFER;
                end
            end
            RD_BUFFER: begin
                if(rdCounter == 127) begin
                    rdState <= IDLE;
                    rd_line_buffer <= 1'b0;
                    o_intr <= 1'b1;
                    
                    // Vertical Logic: Increment row counter
                    if(rowCounter == 127) begin
                        allRowsDone <= 1'b1; // Stop processing after 128 rows
                    end else begin
                        rowCounter <= rowCounter + 1;
                    end
                end
            end
        endcase
    end
end

// --- Write Logic (Always runs to keep buffers synced) ---
always @(posedge i_clk) begin
    if(i_rst)
        pixelCounter <= 0;
    else if(i_pixel_data_valid)
        pixelCounter <= (pixelCounter == 129) ? 0 : pixelCounter + 1;
end

always @(posedge i_clk) begin
    if(i_rst)
        currentWrLineBuffer <= 0;
    else if(pixelCounter == 129 && i_pixel_data_valid)
        currentWrLineBuffer <= currentWrLineBuffer + 1;
end

always @(*) begin
    lineBuffDataValid = 4'h0;
    lineBuffDataValid[currentWrLineBuffer] = i_pixel_data_valid;
end

// --- Read Counter Logic ---
always @(posedge i_clk) begin
    if(i_rst)
        rdCounter <= 0;
    else if(rd_line_buffer)
        rdCounter <= (rdCounter == 127) ? 0 : rdCounter + 1;
end

always @(posedge i_clk) begin
    if(i_rst)
        currentRdLineBuffer <= 0;
    else if(rdCounter == 127 && rd_line_buffer)
        currentRdLineBuffer <= currentRdLineBuffer + 1;
end

// --- Multiplexing and Buffer Control ---
always @(*) begin
    case(currentRdLineBuffer)
        0: o_pixel_data = {lb2data, lb1data, lb0data};
        1: o_pixel_data = {lb3data, lb2data, lb1data};
        2: o_pixel_data = {lb0data, lb3data, lb2data};
        3: o_pixel_data = {lb1data, lb0data, lb3data};
        default: o_pixel_data = 72'h0;
    endcase
end

always @(*) begin
    // Note: We use rd_line_buffer here to drive the lineBuffer rdPntr
    case(currentRdLineBuffer)
        0: lineBuffRdData = {1'b0, rd_line_buffer, rd_line_buffer, rd_line_buffer};
        1: lineBuffRdData = {rd_line_buffer, rd_line_buffer, rd_line_buffer, 1'b0};
        2: lineBuffRdData = {rd_line_buffer, rd_line_buffer, 1'b0, rd_line_buffer};
        3: lineBuffRdData = {rd_line_buffer, 1'b0, rd_line_buffer, rd_line_buffer};
        default: lineBuffRdData = 4'h0;
    endcase
end

// --- Instantiations ---
lineBuffer lB0(.i_clk(i_clk), .i_rst(i_rst), .i_data(i_pixel_data), .i_data_valid(lineBuffDataValid[0]), .o_data(lb0data), .i_rd_data(lineBuffRdData[0])); 
lineBuffer lB1(.i_clk(i_clk), .i_rst(i_rst), .i_data(i_pixel_data), .i_data_valid(lineBuffDataValid[1]), .o_data(lb1data), .i_rd_data(lineBuffRdData[1])); 
lineBuffer lB2(.i_clk(i_clk), .i_rst(i_rst), .i_data(i_pixel_data), .i_data_valid(lineBuffDataValid[2]), .o_data(lb2data), .i_rd_data(lineBuffRdData[2])); 
lineBuffer lB3(.i_clk(i_clk), .i_rst(i_rst), .i_data(i_pixel_data), .i_data_valid(lineBuffDataValid[3]), .o_data(lb3data), .i_rd_data(lineBuffRdData[3])); 

endmodule

