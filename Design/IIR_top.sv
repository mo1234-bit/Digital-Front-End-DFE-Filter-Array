module IIR_top (
   (* keep = "true" *)  input  wire              clk,
  (* keep = "true" *)   input  wire              n_rst,
  (* keep = "true" *)   input  wire signed [31:0] i_sample,
     (* keep = "true" *)  input  wire signed [31:0]R1, 
   (* keep = "true" *)  input  wire signed [31:0]CO_THETA1, 
   (* keep = "true" *)  input  wire signed [31:0]R2, 
   (* keep = "true" *)  input  wire signed [31:0]CO_THETA2,
(* keep = "true" *) input wire i_valid_1,
 (* keep = "true" *)   input wire i_valid_2,
   (* keep = "true" *)  output data_valid_out,
   (* keep = "true" *)  output wire signed [31:0] o_filtered_sample
);


    // Internal connection between cascaded filters
    wire signed [31:0] mid_sample;
    wire signed [31:0] second_sample;
    wire signed [31:0] in_stage2=(i_valid_1)?mid_sample:i_sample;
    // First IIR stage: notch at f1
    IIR  IIR_stage1 (
        .clk(clk),
        .n_rst(n_rst),
        .i_sample(i_sample),
        .i_valid          (i_valid_1),
        .o_filtered_sample(mid_sample),
          .R(R1),
        .CO_THETA(CO_THETA1)
    );

    // Second IIR stage: notch at f2
    IIR  IIR_stage2 (
        .clk(clk),
        .n_rst(n_rst),
        .i_sample(in_stage2),
        .i_valid          (i_valid_2),
        .o_filtered_sample(second_sample),
        .R(R2),
        .CO_THETA(CO_THETA2)
    );
assign data_valid_out=i_valid_1 || i_valid_2;
assign o_filtered_sample=(i_valid_1 && i_valid_2)?second_sample:(i_valid_1)?mid_sample:(i_valid_2)?second_sample:o_filtered_sample;
endmodule