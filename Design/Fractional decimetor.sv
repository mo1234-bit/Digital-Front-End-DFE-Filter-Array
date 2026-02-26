module Fractional_decimetor (
   (* keep = "true" *)  input clk,    // Clock
   (* keep = "true" *)  input rst_n,  // Asynchronous reset active low
   (* keep = "true" *)  input data_in_valid,
    (* keep = "true" *)  input   [7:0]  L,
   (* keep = "true" *)  input   [7:0]M, 
   (* keep = "true" *)  input    [15:0]TAPS, 
   (* keep = "true" *)  input signed[31:0]data_in,
   (* keep = "true" *)  output signed[31:0]data_out,
  (* keep = "true" *)   output data_out_valid,
                        output  signed[31:0]dout,dout_fir,
                        output wire dout_valid,dout_valid_fir
    
);
parameter DATA_WIDTH = 32;
    parameter COEFF_WIDTH  = 32;
    parameter COEFF_FRAC   = 15;

    wire fir_en;
logic [12:0]count,count_in,count_fir;

always@(posedge clk)begin
    if(!rst_n)begin
        count<=0;
        count_in<=0;
        count_fir<=0;end
    else 
    if(dout_valid)
        count<=count+1;
    if(data_in_valid)
        count_in<=count_in+1;

    if(data_out_valid)
        count_fir<=count_fir+1;

    
        
end
assign fir_en =
    dout_valid ||
    ( (count != L*count_in + TAPS) &&
      (count_in != 0) &&
      (count_fir != (count_in * L) /M) );


  upsampler #(
.DATA_WIDTH(DATA_WIDTH)
)upsample(
     clk,
     rst_n,
     data_in_valid,      // Input sample valid
     data_in,           // Input sample
     L,
     dout_valid,     // Output sample valid
     dout           // Output sample
);

FIR_compensator_pipelined #(
     .DATA_WIDTH(DATA_WIDTH),
    .COEFF_WIDTH(COEFF_WIDTH),
.COEFF_FRAC(COEFF_FRAC)
)FIR(
   clk,
   rst_n,
   fir_en,
   dout,
   TAPS,
   dout_fir,
   dout_valid_fir
);
wire down_en = dout_valid_fir;

downsampler #(
     .DATA_WIDTH(DATA_WIDTH)
)down(
        clk,
       rst_n,
      down_en,      // Input sample valid
     dout_fir,           // Input sample
     M, 
     data_out_valid,     // Output sample valid
      data_out           // Output sample
);

endmodule : Fractional_decimetor