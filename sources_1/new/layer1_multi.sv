`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 27.03.2026 10:45:35
// Design Name: 
// Module Name: layer1_multi
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

module layer1_multi #(
   parameter NUM_FILTERS = 16,
   parameter PIXEL_WIDTH  = 8,
   parameter ACC_WIDTH    = 32
)(
   input  logic clk,
   input  logic rst,

   input  logic valid_in,
   input  logic signed [71:0] window,

   output logic valid_out,
   output logic signed [PIXEL_WIDTH-1:0] out_pixel [NUM_FILTERS]
);

   localparam int i_zero   = -128;
   localparam int conv_zero = 33;
   localparam int relu_zero = -41;

   // -------------------------
   // PARAMETERS
   // -------------------------
   logic signed [31:0] bias      [NUM_FILTERS];
   logic signed [31:0] qm        [NUM_FILTERS];
   logic signed [31:0] shift     [NUM_FILTERS];

   logic signed [31:0] pos_qm    [NUM_FILTERS];
   logic signed [31:0] pos_shift [NUM_FILTERS];
   logic signed [31:0] neg_qm    [NUM_FILTERS];
   logic signed [31:0] neg_shift [NUM_FILTERS];

   // -------------------------
   // WEIGHTS
   // -------------------------
   logic signed [7:0] w_flat [0:NUM_FILTERS*9-1];
   logic signed [7:0] w      [NUM_FILTERS][0:8];

   logic signed [31:0] pos_qm_scalar    [0:0];
   logic signed [31:0] pos_shift_scalar  [0:0];
   logic signed [31:0] neg_qm_scalar    [0:0];
   logic signed [31:0] neg_shift_scalar  [0:0];

   initial begin
       $readmemh("weights.mem",        w_flat);
       $readmemh("bias.mem",           bias);
       $readmemh("conv_qm.mem",        qm);
       $readmemh("conv_shift.mem",     shift);

       $readmemh("relu_pos_qm.mem",    pos_qm_scalar);
       $readmemh("relu_pos_shift.mem", pos_shift_scalar);
       $readmemh("relu_neg_qm.mem",    neg_qm_scalar);
       $readmemh("relu_neg_shift.mem", neg_shift_scalar);
   end

   always_comb begin
       for (int f = 0; f < NUM_FILTERS; f++) begin
           for (int k = 0; k < 9; k++) begin
               w[f][k] = w_flat[f*9 + k];
           end

           pos_qm[f]    = pos_qm_scalar[0];
           pos_shift[f] = pos_shift_scalar[0];
           neg_qm[f]    = neg_qm_scalar[0];
           neg_shift[f] = neg_shift_scalar[0];
       end
   end

   // -------------------------
   // INPUT WINDOW REGISTER
   // -------------------------
   logic signed [7:0] pixels_reg [0:8];
   logic window_valid_r;

   always_ff @(posedge clk or posedge rst) begin
       if (rst) begin
           window_valid_r <= 1'b0;
           for (int k = 0; k < 9; k++) begin
               pixels_reg[k] <= '0;
           end
       end else begin
           window_valid_r <= valid_in;

           if (valid_in) begin
               pixels_reg[0] <= $signed(window[23:16]);
               pixels_reg[1] <= $signed(window[15:8]);
               pixels_reg[2] <= $signed(window[7:0]);

               pixels_reg[3] <= $signed(window[47:40]);
               pixels_reg[4] <= $signed(window[39:32]);
               pixels_reg[5] <= $signed(window[31:24]);

               pixels_reg[6] <= $signed(window[71:64]);
               pixels_reg[7] <= $signed(window[63:56]);
               pixels_reg[8] <= $signed(window[55:48]);
           end
       end
   end

   // -------------------------
   // PIPELINE REGISTERS
   // -------------------------
   logic signed [ACC_WIDTH-1:0] part0_reg [NUM_FILTERS];
   logic signed [ACC_WIDTH-1:0] part1_reg [NUM_FILTERS];
   logic signed [ACC_WIDTH-1:0] part2_reg [NUM_FILTERS];
   logic signed [ACC_WIDTH-1:0] acc_reg   [NUM_FILTERS];

   logic signed [ACC_WIDTH-1:0] rq_calc_reg [NUM_FILTERS];
   logic signed [ACC_WIDTH-1:0] rq_reg      [NUM_FILTERS];

   logic signed [ACC_WIDTH-1:0] centered_reg      [NUM_FILTERS];
   logic                        centered_sign_reg [NUM_FILTERS];
   logic signed [ACC_WIDTH-1:0] centered_pipe_reg [NUM_FILTERS];
   logic                        centered_pipe_sign [NUM_FILTERS];

   logic signed [ACC_WIDTH-1:0] scaled_mul_reg [NUM_FILTERS];
   logic signed [ACC_WIDTH-1:0] scaled_reg     [NUM_FILTERS];
   logic signed [ACC_WIDTH-1:0] relu_reg       [NUM_FILTERS];

   logic vld1, vld2, vld3, vld4, vld5, vld6, vld7, vld8;

   // -------------------------
   // STAGE 1: PARTIAL MAC
   // -------------------------
   always_ff @(posedge clk or posedge rst) begin
       if (rst) begin
           vld1 <= 1'b0;
           for (int f = 0; f < NUM_FILTERS; f++) begin
               part0_reg[f] <= '0;
               part1_reg[f] <= '0;
               part2_reg[f] <= '0;
           end
       end else begin
           vld1 <= window_valid_r;

           if (window_valid_r) begin
               for (int f = 0; f < NUM_FILTERS; f++) begin
                   part0_reg[f] <=
                       ($signed(pixels_reg[0]) - i_zero) * $signed(w[f][0]) +
                       ($signed(pixels_reg[1]) - i_zero) * $signed(w[f][1]) +
                       ($signed(pixels_reg[2]) - i_zero) * $signed(w[f][2]);

                   part1_reg[f] <=
                       ($signed(pixels_reg[3]) - i_zero) * $signed(w[f][3]) +
                       ($signed(pixels_reg[4]) - i_zero) * $signed(w[f][4]) +
                       ($signed(pixels_reg[5]) - i_zero) * $signed(w[f][5]);

                   part2_reg[f] <=
                       ($signed(pixels_reg[6]) - i_zero) * $signed(w[f][6]) +
                       ($signed(pixels_reg[7]) - i_zero) * $signed(w[f][7]) +
                       ($signed(pixels_reg[8]) - i_zero) * $signed(w[f][8]);
               end
           end
       end
   end

   // -------------------------
   // STAGE 2: FINAL ACCUMULATE + BIAS
   // -------------------------
   always_ff @(posedge clk or posedge rst) begin
       if (rst) begin
           vld2 <= 1'b0;
           for (int f = 0; f < NUM_FILTERS; f++) begin
               acc_reg[f] <= '0;
           end
       end else begin
           vld2 <= vld1;

           if (vld1) begin
               for (int f = 0; f < NUM_FILTERS; f++) begin
                   acc_reg[f] <= part0_reg[f] + part1_reg[f] + part2_reg[f] + bias[f];
               end
           end
       end
   end
   
   
   logic signed [ACC_WIDTH-1:0] rq_shift_reg [NUM_FILTERS];
   logic signed [ACC_WIDTH-1:0] rq_mul_reg   [NUM_FILTERS];
   logic [31:0]                 rq_qm_reg    [NUM_FILTERS];
   logic [31:0]                 rq_rshift_reg[NUM_FILTERS];
    
   logic vld3a, vld3b, vld3c;



      // STAGE 3A: register input and selected quant params
   always_ff @(posedge clk or posedge rst) begin
       if (rst) begin
           vld3a <= 1'b0;
           for (int f = 0; f < NUM_FILTERS; f++) begin
               rq_shift_reg[f]  <= '0;
               rq_qm_reg[f]      <= '0;
               rq_rshift_reg[f]  <= '0;
           end
       end else begin
           vld3a <= vld2;
    
           if (vld2) begin
               for (int f = 0; f < NUM_FILTERS; f++) begin
                   rq_shift_reg[f] <= acc_reg[f];
    
                   rq_qm_reg[f] <= qm[f];
                   if (shift[f] < 0)
                       rq_rshift_reg[f] <= -shift[f];
                   else
                       rq_rshift_reg[f] <= 0;
               end
           end
       end
   end
    
   // STAGE 3B: left shift + high_mul only
   always_ff @(posedge clk or posedge rst) begin
       if (rst) begin
           vld3b <= 1'b0;
           for (int f = 0; f < NUM_FILTERS; f++) begin
               rq_mul_reg[f] <= '0;
           end
       end else begin
           vld3b <= vld3a;
    
           if (vld3a) begin
               for (int f = 0; f < NUM_FILTERS; f++) begin
                   int shifted_val;
                   shifted_val = rq_shift_reg[f];
    
                   if (shift[f] > 0)
                       shifted_val = shifted_val <<< shift[f];
    
                   rq_mul_reg[f] <= high_mul(shifted_val, rq_qm_reg[f]);
               end
           end
       end
   end
    
   // STAGE 3C: div_pot only
   always_ff @(posedge clk or posedge rst) begin
       if (rst) begin
           vld3c <= 1'b0;
           for (int f = 0; f < NUM_FILTERS; f++) begin
               rq_calc_reg[f] <= '0;
           end
       end else begin
           vld3c <= vld3b;
    
           if (vld3b) begin
               for (int f = 0; f < NUM_FILTERS; f++) begin
                   rq_calc_reg[f] <= div_pot(rq_mul_reg[f], rq_rshift_reg[f]);
               end
           end
       end
   end
       // -------------------------
   // STAGE 4: ADD CONV ZERO
   // -------------------------
   always_ff @(posedge clk or posedge rst) begin
       if (rst) begin
           vld4 <= 1'b0;
           for (int f = 0; f < NUM_FILTERS; f++) begin
               rq_reg[f] <= '0;
           end
       end else begin
           vld4 <= vld3c;

           if (vld3c) begin
               for (int f = 0; f < NUM_FILTERS; f++) begin
                   rq_reg[f] <= rq_calc_reg[f] + conv_zero;
               end
           end
       end
   end

   // -------------------------
   // STAGE 5: CENTER + SIGN DETECT
   // -------------------------
   always_ff @(posedge clk or posedge rst) begin
       if (rst) begin
           vld5 <= 1'b0;
           for (int f = 0; f < NUM_FILTERS; f++) begin
               centered_reg[f]      <= '0;
               centered_sign_reg[f] <= 1'b0;
           end
       end else begin
           vld5 <= vld4;

           if (vld4) begin
               for (int f = 0; f < NUM_FILTERS; f++) begin
                   centered_reg[f]      <= rq_reg[f] - conv_zero;
                   centered_sign_reg[f] <= ((rq_reg[f] - conv_zero) >= 0);
               end
           end
       end
   end

   // -------------------------
   // STAGE 6: INSERT REGISTER BEFORE LEAKY RELU PATH
   // -------------------------
   always_ff @(posedge clk or posedge rst) begin
       if (rst) begin
           vld6 <= 1'b0;
           for (int f = 0; f < NUM_FILTERS; f++) begin
               centered_pipe_reg[f]  <= '0;
               centered_pipe_sign[f] <= 1'b0;
           end
       end else begin
           vld6 <= vld5;

           if (vld5) begin
               for (int f = 0; f < NUM_FILTERS; f++) begin
                   centered_pipe_reg[f]  <= centered_reg[f];
                   centered_pipe_sign[f] <= centered_sign_reg[f];
               end
           end
       end
   end



   logic signed [31:0] relu_x_reg   [NUM_FILTERS];
   logic signed [31:0] relu_shifted [NUM_FILTERS];
   logic signed [31:0] relu_mul     [NUM_FILTERS];
   logic signed [31:0] relu_out     [NUM_FILTERS];
    
   logic [31:0] relu_qm_reg   [NUM_FILTERS];
   logic [31:0] relu_shift_reg[NUM_FILTERS];
    
   logic vld8a, vld8b, vld8c,vld8d;
    
    
       always_ff @(posedge clk) begin
       vld8a <= vld6;
    
       if (vld6) begin
           for (int f = 0; f < NUM_FILTERS; f++) begin
               relu_x_reg[f] <= centered_pipe_reg[f];
    
               if (centered_pipe_sign[f]) begin
                   relu_qm_reg[f]    <= pos_qm[f];
                   relu_shift_reg[f] <= pos_shift[f];
               end else begin
                   relu_qm_reg[f]    <= neg_qm[f];
                   relu_shift_reg[f] <= neg_shift[f];
               end
           end
       end
   end
   // Stage B: variable shift only
   always_ff @(posedge clk) begin
       vld8b <= vld8a;
    
       if (vld8a) begin
           for (int f = 0; f < NUM_FILTERS; f++) begin
               int left_shift;
    
               left_shift = (relu_shift_reg[f] > 0) ? relu_shift_reg[f] : 0;
    
               relu_shifted[f] <= (left_shift > 0) 
                                ? (relu_x_reg[f] <<< left_shift)
                                : relu_x_reg[f];
           end
       end
   end
    
   // Stage C: multiplier only
   always_ff @(posedge clk) begin
       vld8c <= vld8b;
    
       if (vld8b) begin
           for (int f = 0; f < NUM_FILTERS; f++) begin
               relu_mul[f] <= high_mul(relu_shifted[f], relu_qm_reg[f]);
           end
       end
   end
    
   always_ff @(posedge clk) begin
       vld8d <= vld8c;
    
       if (vld8c) begin
           for (int f = 0; f < NUM_FILTERS; f++) begin
               int right_shift;
               int tmp;
    
               right_shift = (relu_shift_reg[f] < 0) ? -relu_shift_reg[f] : 0;
    
               tmp = div_pot(relu_mul[f], right_shift) + relu_zero;
    
               scaled_reg[f] <= tmp;
           end
       end
   end
        
   // -------------------------
   // STAGE 9: CLAMP + OUTPUT
   // -------------------------
   always_ff @(posedge clk or posedge rst) begin
       if (rst) begin
           valid_out <= 1'b0;
           for (int f = 0; f < NUM_FILTERS; f++) begin
               relu_reg[f]  <= '0;
               out_pixel[f] <= '0;
           end
       end else begin
           valid_out <= vld8d;

           if (vld8d) begin
               for (int f = 0; f < NUM_FILTERS; f++) begin
                   int tmp;
                   tmp = scaled_reg[f];

                   relu_reg[f] <= tmp;

                   if (tmp > 127)
                       out_pixel[f] <= 8'sd127;
                   else if (tmp < -128)
                       out_pixel[f] <= -8'sd128;
                   else
                       out_pixel[f] <= tmp[7:0];
               end
           end
       end
   end

   // -------------------------
   // QUANT HELPERS
   // -------------------------
   function automatic int high_mul(input int a, input int b);
       logic signed [63:0] ab;
       logic signed [63:0] nudge;
       begin
           if (a == 32'sh80000000 && b == 32'sh80000000)
               return 32'sh7fffffff;

           ab = $signed(a) * $signed(b);

           if (ab >= 0)
               nudge = 64'sd1 << 30;
           else
               nudge = (64'sd1 << 30) - 1;

           return (ab + nudge) >>> 31;
       end
   endfunction

   function automatic int div_pot(input int x, input int s);
       int mask;
       int remainder;
       int threshold;
       begin
           if (s == 0)
               return x;

           mask      = (1 << s) - 1;
           remainder = x & mask;
           threshold = (mask >> 1);

           if (x < 0)
               threshold = threshold + 1;

           if (remainder > threshold)
               return (x >>> s) + 1;
           else
               return (x >>> s);
       end
   endfunction

   function automatic int multiply_by_quantized_multiplier(
       input int x,
       input int qm,
       input int shift_in
   );
       int left_shift;
       int right_shift;
       int res;
       begin
           left_shift  = (shift_in > 0) ? shift_in : 0;
           right_shift = (shift_in < 0) ? (-shift_in) : 0;

           res = x;
           if (left_shift > 0)
               res = res <<< left_shift;

           res = high_mul(res, qm);
           res = div_pot(res, right_shift);

           return res;
       end
   endfunction

endmodule
