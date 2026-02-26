module IIR(
   (* keep = "true" *)  input  wire                   clk,
  (* keep = "true" *)   input  wire                   n_rst,
   (* keep = "true" *)  input  wire signed [31:0]R, 
   (* keep = "true" *)  input  wire signed [31:0]CO_THETA,
   (* keep = "true" *)  input  wire signed   [31:0]   i_sample,
   (* keep = "true" *)  input wire i_valid,
   (* keep = "true" *)  output reg  signed   [31:0]   o_filtered_sample
);

    // Internal registers
    reg signed [36:0] z1;
    reg signed [34:0] z2;

    // Temps and intermediates
    reg signed [62:0] r_co_temp;
    reg signed [31:0] r_co;
    reg signed [31:0] r2_co;
    reg signed [63:0] feed_back1_temp;
    reg signed [31:0] feed_back1;
    reg signed [34:0] pre_z1;
    reg signed [62:0] in_co_temp;
    reg signed [31:0] in_co;
    reg signed [32:0] feed_forw1;
    reg signed [62:0] r2_temp;
    reg signed [31:0] r2;
    reg signed [62:0] feed_back2_temp;
    reg signed [31:0] feed_back2;
    reg signed [37:0] pre_out;

    // Combinational logic
    always @(*) begin
        r_co_temp = (CO_THETA * R);
        r_co      = r_co_temp[62:31];
        r2_co     = r_co <<< 1;
        in_co_temp = i_sample * CO_THETA;
        in_co      = in_co_temp[62:31];
        feed_forw1 = {{1{in_co[31]}}, in_co} <<< 1;
        r2_temp = R * R;
        r2      = r2_temp[62:31];
        pre_out = {{1{z1[36]}}, z1} + {{6{i_sample[31]}}, i_sample};
        o_filtered_sample = {pre_out[37], pre_out[30:0]};
        feed_back1_temp = o_filtered_sample * r2_co;
        feed_back1 = feed_back1_temp[63:32];
        pre_z1 = {{1{feed_back1[31]}}, feed_back1, 2'b0} - {{2{feed_forw1[32]}}, feed_forw1};
        feed_back2_temp = o_filtered_sample * r2;
        feed_back2 = feed_back2_temp[62:31];
    end

    // Sequential logic
    always @(posedge clk or negedge n_rst) begin
        if (!n_rst) begin
            z1 <= 0;
            z2 <= 0;
        end else if(i_valid) begin
            z1 <= {{1{pre_z1[34]}}, pre_z1, 1'b0} + {{2{z2[34]}}, z2};
            z2 <= {{3{i_sample[31]}}, i_sample} - {{1{feed_back2[31]}}, feed_back2, 2'b0};
        end
    end

endmodule
