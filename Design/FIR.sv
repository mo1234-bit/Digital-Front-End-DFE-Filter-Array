module FIR_compensator_pipelined #(
    parameter DATA_WIDTH   = 32,
    parameter COEFF_WIDTH  = 32,
    parameter COEFF_FRAC   = 15
)(
   (* keep = "true" *)  input  wire                          clk,
   (* keep = "true" *)  input  wire                          rst_n,
   (* keep = "true" *)  input  wire                          enable,
   (* keep = "true" *)  input  wire signed [DATA_WIDTH-1:0]  din,
   (* keep = "true" *)  input  wire  [15:0]TAPS, 
   (* keep = "true" *)  output reg  signed [DATA_WIDTH-1:0]  dout,
   (* keep = "true" *)  output reg                           dout_valid
);

    // Internal widths
    localparam integer ACC_WIDTH = DATA_WIDTH + COEFF_WIDTH + $clog2(512);

    // FIR coefficients (read from external file)
    reg signed [COEFF_WIDTH-1:0] h [0:512-1];
    initial begin
        
        $readmemh("coeffs.hex", h);
    end

    // Shift register (delay line)
    reg signed [DATA_WIDTH-1:0] shift_reg [0:512-1];
    integer i;

    // Partial products and accumulators (pipeline registers)
    reg signed [ACC_WIDTH-1:0] prod_stage [0:512-1];
    reg signed [ACC_WIDTH-1:0] acc_stage  [0:512-1];

    // Valid signal pipeline (tracks when output is ready)
    reg [512:0] valid_pipe;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < TAPS; i = i + 1) begin
                shift_reg[i]  <= 0;
                prod_stage[i] <= 0;
               
            end
            dout <= 0;
            dout_valid <= 0;
            valid_pipe <= 0;
        end else if (enable) begin
            // Shift input samples
            for (i = TAPS-1; i > 0; i = i - 1)
                shift_reg[i] <= shift_reg[i-1];
            shift_reg[0] <= din;

            // Multiply stage (parallel)
            for (i = 0; i < TAPS; i = i + 1) begin
                prod_stage[i] <= 
                    $signed({{(ACC_WIDTH-(DATA_WIDTH+COEFF_WIDTH)){shift_reg[i][DATA_WIDTH-1]}}, shift_reg[i]})
                    * $signed({{(ACC_WIDTH-COEFF_WIDTH){h[i][COEFF_WIDTH-1]}}, h[i]});
            end

            // Pipeline accumulation
            acc_stage[0] = prod_stage[0];
            for (i = 1; i < TAPS; i = i + 1)
                acc_stage[i] = acc_stage[i-1] + prod_stage[i];

            // Output normalization
            dout <= acc_stage[TAPS-1] >>> COEFF_FRAC;

            // Valid pipeline: shift through TAPS stages
            valid_pipe <= {valid_pipe[512:0], 1'b1};
            dout_valid <= valid_pipe[TAPS];
        end else begin
            dout_valid <= 0;
        end
    end

endmodule