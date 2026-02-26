module FIR_IIR #(
   parameter DATA_WIDTH = 32,     
    parameter COEFF_WIDTH  = 32,
    parameter COEFF_FRAC   = 15,
    parameter REGWIDTH = DATA_WIDTH + (4 * $clog2(17)) ,
      parameter ADDR_WIDTH = 4 
)(
   (* keep = "true" *)  input clk,  clk_1  ,clk_spi, mosi,cs_n,
   (* keep = "true" *)  input  wire  rst_n,   
    (* keep = "true" *) input  wire signed [DATA_WIDTH-1:0] data_in,      
    (* keep = "true" *) input  wire  data_in_valid,
   (* keep = "true" *)  output wire  signed [DATA_WIDTH-1:0] data_out,
    (* keep = "true" *) output wire data_out_valid,
   (* keep = "true" *)   output ready, miso
);

   wire signed[DATA_WIDTH-1:0]output_Resampler,fifo_out;
   wire signed[DATA_WIDTH-1:0]data_out_cic;
   wire data_out_valid_cic,data_out_valid_IIR,en,full,empty;
   wire [7:0]  L;
   wire [7:0]M; 
   wire  [15:0]TAPS; 
   wire  [7:0]N,enable,bypass;
   reg[7:0]counter;
   reg ready_buf;
   wire FIR_OUTPUT_valid, UPSAMPLE_OUTPUT_valid,wr_sys_en; 
   wire signed [31:0]R1,UPSAMPLE_OUTPUT, FIR_OUTPUT ; 
   wire signed [31:0]CO_THETA1; 
   wire signed [31:0]R2; 
   wire  signed[31:0]CO_THETA2; 
   wire [7:0]    D; 
    wire [7:0] wr_data;
   wire wr_en;
 wire addr;
 wire [7:0]rd_data;
 assign wr_sys_en=(FIR_OUTPUT_valid || UPSAMPLE_OUTPUT_valid || data_out_valid_IIR || data_out_valid_cic ||  data_out_valid)?1:0;


always@(posedge clk)begin
   if(!rst_n)begin
      ready_buf<=1;
   counter<=0;
end
   else if(data_in_valid)begin
      counter<=counter+1;
       ready_buf<=0;
end
 if(counter==L-8'd1)begin
       ready_buf<=0;
       counter<=0;
    end
    else 
      ready_buf<=1;
end
assign ready=(data_in_valid)?1'b0:ready_buf;


 spi_slave spi(
    // SPI Interface
          .sclk(clk_spi),
          .cs_n(cs_n),
          .mosi(mosi),
          .miso(miso),

    // Register File Interface
          .rf_wr_en(wr_en),
          .rf_addr(addr),
          .rf_wdata(wr_data),
          .rf_rdata(rd_data)
);

register_file #(
  64,
   8
)regf(
      .clk(clk_spi),
      .rst_n(rst_n),
      .wr_data(wr_data),
      .wr_en(wr_en),
      .addr(addr),
      .rd_data(rd_data),
      .L(L),
      .M(M), 
      .TAPS(TAPS), 
      .N(N), 
      .R1(R1), 
      .CO_THETA1(CO_THETA1), 
      .R2(R2), 
      .CO_THETA2(CO_THETA2), 
      .D(D),
      .enable(enable),
      .bypass(bypass),
      .wr_sys_en(wr_sys_en),
      .FIR_OUTPUT(FIR_OUTPUT),
      .UPSAMPLE_OUTPUT(UPSAMPLE_OUTPUT),
      .FRAC_OUTPUT(output_Resampler),
      .IIR_OUTPUT(data_out_cic),
      .CIC_OUTPUT(data_out)
);


Fractional_decimetor#(
     .DATA_WIDTH(DATA_WIDTH) , 
     .COEFF_WIDTH(COEFF_WIDTH)  ,  
     .COEFF_FRAC(COEFF_FRAC) 
)fractional(
    .clk(clk),
    .rst_n(rst_n),
    .data_in(data_in),      
    .data_in_valid (data_in_valid &&enable[0]),
    .data_out(output_Resampler),     
    .data_out_valid(data_out_valid_IIR),
    .L(L),
    .TAPS(TAPS),
    .M(M), 
    .dout(UPSAMPLE_OUTPUT),
    .dout_fir(FIR_OUTPUT),
    .dout_valid(UPSAMPLE_OUTPUT_valid),
    .dout_valid_fir(FIR_OUTPUT_valid)
);

fifo  #(
     .DATA_WIDTH(DATA_WIDTH) ,
     .ADDR_WIDTH(ADDR_WIDTH) 
)fifo(
        .wr_clk(clk),
        .rst_n(rst_n),
        .wr_data(output_Resampler),
        .wr_en(data_out_valid_IIR),
        .rd_data(fifo_out),
        .en(en),
        .rd_clk(clk_1)
    );

IIR_top  IIR(
            .clk(clk_1),
            .n_rst(rst_n),
            .i_sample(fifo_out),
            .i_valid_1          (en && enable[1]),
            .i_valid_2          (en && enable[2]),
            .data_valid_out   (data_out_valid_cic),
            .o_filtered_sample(data_out_cic),
            .R1       (R1),
            .CO_THETA1(CO_THETA1),
            .R2       (R2),
            .CO_THETA2(CO_THETA2)
);
CIC #(
   .INPUTWIDTH(DATA_WIDTH),
   .MAX_D     (17),
   .REGWIDTH  (REGWIDTH) )CIC(
    .clk(clk_1),
    .rst_n(rst_n),
    .valid_in(data_out_valid_cic && enable[3]),
    .d_in(data_out_cic),
    .D(D),     
    .N(N),
    .d_out(data_out),
    .valid_out(data_out_valid)
);



endmodule : FIR_IIR

