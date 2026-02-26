module CIC #(
    parameter INPUTWIDTH = 32,
    parameter MAX_D = 17,
    parameter REGWIDTH = INPUTWIDTH + (4 * $clog2(MAX_D)) 
)(
   (* keep = "true" *)  input  wire                      clk,
   (* keep = "true" *)  input  wire                      rst_n,
    (* keep = "true" *) input  wire                      valid_in,
     (* keep = "true" *)  input  wire  [7:0]N, 
   (* keep = "true" *)  input  wire signed [INPUTWIDTH-1:0] d_in,
  (* keep = "true" *)   input  wire [7:0]    D,        
  (* keep = "true" *)   output reg  signed [INPUTWIDTH-1:0] d_out,
  (* keep = "true" *)   output reg                       valid_out
);

    // Internal registers
    reg signed [REGWIDTH-1:0] d_tmp, d_d_tmp;

    // Integrator stages
    reg signed [REGWIDTH-1:0] d1, d2, d3, d4;

    // Comb stages
    reg signed [REGWIDTH-1:0] d5, d_d5;
    reg signed [REGWIDTH-1:0] d6, d_d6;
    reg signed [REGWIDTH-1:0] d7, d_d7;
    reg signed [REGWIDTH-1:0] d8;

    // Counter for decimation
    reg [$clog2(MAX_D)-1:0] count;

    // Control signals
    reg v_comb;
    reg d_clk_tmp;

    // dynamic log2(D)
    reg [3:0] log2D;

    always @(*) begin

        case (D)
            1:  log2D = 0;
            2,3:  log2D = 1;
            4,5,6: log2D = 2;
            7,8,9,10,11,12: log2D = 3;
            13,14,15,16: log2D = 4;

            default: log2D = 0;
        endcase
        
    end


    // Integrator + Decimation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d1 <= 0; d2 <= 0; d3 <= 0; d4 <= 0;
            count <= 0;
            v_comb <= 0;
            valid_out<=0;
            d_tmp<=0;
        end else if(valid_in)begin
            valid_out <= d_clk_tmp;
            // Cascaded integrators
            d1 <= d_in + d1;
            d2 <= d1 + d2;
            d3 <= d2 + d3;
            d4 <= d3 + d4;

            // Downsampling control
            if (count == (D - 1)) begin
                count <= 0;
                d_tmp <= d4;
                d_clk_tmp <= 1'b1;
                v_comb <= 1'b1;
            end else begin
                count <= count + 1;
                d_clk_tmp <= 1'b0;
                v_comb <= 1'b0;
            end
        end
    end

    // Comb section
    always @(posedge clk or negedge rst_n) begin
        
        if (!rst_n) begin
            d5 <= 0; d_d5 <= 0;
            d6 <= 0; d_d6 <= 0;
            d7 <= 0; d_d7 <= 0;
            d8 <= 0;
            d_d_tmp <= 0;
            d_out <= 0;
        end else if (v_comb) begin
            d_d_tmp <= d_tmp;

            d5 <= d_tmp - d_d_tmp;
            d_d5 <= d5;

            d6 <= d5 - d_d5;
            d_d6 <= d6;

            d7 <= d6 - d_d6;
            d_d7 <= d7;

            d8 <= d7 - d_d7;

            // Use log2D instead of $clog2(D)
            d_out <= d8 >>> (N * log2D);
        end
    end

endmodule
