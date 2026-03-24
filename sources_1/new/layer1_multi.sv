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

    // -------------------------
    // ZERO POINTS
    // -------------------------
    localparam int i_zero    = -128;
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
    logic signed [31:0] pos_shift_scalar [0:0];
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

        for (int f = 0; f < NUM_FILTERS; f++) begin
            pos_qm[f]    = pos_qm_scalar[0];
            pos_shift[f] = pos_shift_scalar[0];
            neg_qm[f]    = neg_qm_scalar[0];
            neg_shift[f] = neg_shift_scalar[0];
        end
    end

    always_comb begin
        for (int f = 0; f < NUM_FILTERS; f++) begin
            for (int k = 0; k < 9; k++) begin
                w[f][k] = w_flat[f*9 + k];
            end
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
    logic signed [ACC_WIDTH-1:0] acc_reg  [NUM_FILTERS];
    logic signed [ACC_WIDTH-1:0] rq_reg   [NUM_FILTERS];
    logic signed [ACC_WIDTH-1:0] relu_reg  [NUM_FILTERS];

    logic vld1, vld2, vld3;

    // -------------------------
    // STAGE 1: CONV + BIAS
    // -------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            vld1 <= 1'b0;
            for (int f = 0; f < NUM_FILTERS; f++) begin
                acc_reg[f] <= '0;
            end
        end else begin
            for (int f = 0; f < NUM_FILTERS; f++) begin
                int acc_tmp;
                acc_tmp = 0;

                for (int k = 0; k < 9; k++) begin
                    acc_tmp += (pixels_reg[k] - i_zero) * w[f][k];
                end

                acc_reg[f] <= acc_tmp + bias[f];
            end

            vld1 <= window_valid_r;
        end
    end

    // -------------------------
    // STAGE 2: REQUANT
    // -------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            vld2 <= 1'b0;
            for (int f = 0; f < NUM_FILTERS; f++) begin
                rq_reg[f] <= '0;
            end
        end else begin
            for (int f = 0; f < NUM_FILTERS; f++) begin
                rq_reg[f] <= multiply_by_quantized_multiplier(acc_reg[f], qm[f], shift[f]) + conv_zero;
            end

            vld2 <= vld1;
        end
    end

    // -------------------------
    // STAGE 3: LEAKY RELU
    // -------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            vld3 <= 1'b0;
            for (int f = 0; f < NUM_FILTERS; f++) begin
                relu_reg[f] <= '0;
            end
        end else begin
            for (int f = 0; f < NUM_FILTERS; f++) begin
                int centered;
                int scaled;

                centered = rq_reg[f] - conv_zero;

                if (centered >= 0)
                    scaled = multiply_by_quantized_multiplier(centered, pos_qm[f], pos_shift[f]);
                else
                    scaled = multiply_by_quantized_multiplier(centered, neg_qm[f], neg_shift[f]);

                relu_reg[f] <= scaled + relu_zero;
            end

            vld3 <= vld2;
        end
    end

    // -------------------------
    // OUTPUT CLAMP
    // -------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out <= 1'b0;
            for (int f = 0; f < NUM_FILTERS; f++) begin
                out_pixel[f] <= '0;
            end
        end else begin
            valid_out <= vld3;

            for (int f = 0; f < NUM_FILTERS; f++) begin
                if (relu_reg[f] > 127)
                    out_pixel[f] <= 127;
                else if (relu_reg[f] < -128)
                    out_pixel[f] <= -128;
                else
                    out_pixel[f] <= relu_reg[f][7:0];
            end
        end
    end


    function automatic int high_mul(input int a, input int b);
    logic signed [63:0] ab;
    logic signed [63:0] nudge;

    begin
        // Saturation edge case
        if (a == 32'sh80000000 && b == 32'sh80000000)
            return 32'sh7fffffff;

        ab = $signed(a) * $signed(b);

        // TFLite exact rounding
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

            mask = (1 << s) - 1;
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
        input int shift
    );
        int left_shift;
        int right_shift;
        int res;
        begin
            left_shift  = (shift > 0) ? shift : 0;
            right_shift = (shift < 0) ? (-shift) : 0;

            res = x;
            if (left_shift > 0)
                res = res <<< left_shift;

            res = high_mul(res, qm);
            res = div_pot(res, right_shift);

            return res;
        end
    endfunction


endmodule
