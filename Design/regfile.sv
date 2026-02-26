module register_file #(
    parameter REG_SIZE=64,
    DATA_WIDTH=8
    )(

    //general ports
    input  wire                      clk,
    input  wire                      rst_n,

    // SPI Ports
       //write ports
    input  wire [DATA_WIDTH-1:0]     wr_data,
    input  wire                      wr_en,
    input  wire [DATA_WIDTH-1:0]     addr,
        // read output
    output wire [DATA_WIDTH-1:0]     rd_data,
    // system ports

       // read ports
    output reg  [DATA_WIDTH-1:0]   L,
    output reg [DATA_WIDTH-1:0] M, 
    output reg   [2*DATA_WIDTH-1:0] TAPS, 
    output reg  [DATA_WIDTH-1:0]  N, 
    output reg signed  [4*DATA_WIDTH-1:0] R1, 
    output reg signed [4*DATA_WIDTH-1:0] CO_THETA1, 
    output reg signed  [4*DATA_WIDTH-1:0] R2, 
    output reg  signed [4*DATA_WIDTH-1:0] CO_THETA2, 
    output reg  [DATA_WIDTH-1:0]     D,
    output reg  [DATA_WIDTH-1:0]     enable,
    output reg  [DATA_WIDTH-1:0]     bypass,

        //write ports
    input  wire                      wr_sys_en,
    input wire signed  [4*DATA_WIDTH-1:0] FIR_OUTPUT,
    input wire signed  [4*DATA_WIDTH-1:0] UPSAMPLE_OUTPUT,
    input wire signed  [4*DATA_WIDTH-1:0] FRAC_OUTPUT,
    input wire signed  [4*DATA_WIDTH-1:0] IIR_OUTPUT,
    input wire signed  [4*DATA_WIDTH-1:0] CIC_OUTPUT
    
);
  //try to syn with fast system
    // Register file memory
    reg [DATA_WIDTH-1:0] registers [REG_SIZE-1:0];
    
    
    // Register Address Map
    localparam ADDR_CIC_D           = 'd1;  // CIC decimation factor
    localparam ADDR_CIC_N           = 'd2;  // CIC stages
    
    localparam ADDR_FRAC_L          = 'd3;  // Fractional L
    localparam ADDR_FRAC_M          = 'd4;  // Fractional M
    
    localparam ADDR_FIR_TAPS_1        = 'd5;  // FIR number of taps
    localparam ADDR_FIR_TAPS_2        = 'd6;  // FIR number of taps
    localparam ADDR_FIR_COEFF_FRAC  = 'd7;  // FIR coefficient fractional bits
    
    localparam ADDR_IIR_R1_1          = 'd8;  // IIR R1
    localparam ADDR_IIR_R1_2          = 'd9;  // IIR R1
    localparam ADDR_IIR_R1_3          = 'd10;  // IIR R1
    localparam ADDR_IIR_R1_4          = 'd11;  // IIR R1
    localparam ADDR_IIR_CO_THETA1_1   = 'd12;  // IIR CO_THETA1
    localparam ADDR_IIR_CO_THETA1_2   = 'd13;  // IIR CO_THETA1
    localparam ADDR_IIR_CO_THETA1_3   = 'd14;  // IIR CO_THETA1
    localparam ADDR_IIR_CO_THETA1_4   = 'd15;  // IIR CO_THETA1
    localparam ADDR_IIR_R2_1         = 'd16;  // IIR R2
    localparam ADDR_IIR_R2_2          = 'd17;  // IIR R2
    localparam ADDR_IIR_R2_3          = 'd18;  // IIR R2
    localparam ADDR_IIR_R2_4          = 'd19;  // IIR R2
    localparam ADDR_IIR_CO_THETA2_1   = 'd20;  // IIR CO_THETA2
    localparam ADDR_IIR_CO_THETA2_2   = 'd21;  // IIR CO_THETA2
    localparam ADDR_IIR_CO_THETA2_3   = 'd22;  // IIR CO_THETA2
    localparam ADDR_IIR_CO_THETA2_4   = 'd23;  // IIR CO_THETA2
 

    localparam ADDR_FIR_OUTPUT_1           = 'd24;  // FIR_OUTPUT (SPI read-only)
    localparam ADDR_FIR_OUTPUT_2           = 'd25;  // FIR_OUTPUT (SPI read-only)
    localparam ADDR_FIR_OUTPUT_3           = 'd26;  // FIR_OUTPUT (SPI read-only)
    localparam ADDR_FIR_OUTPUT_4           = 'd27;  // FIR_OUTPUT (SPI read-only)

    localparam ADDR_UPSAMPLE_OUTPUT_1      = 'd28;  // UPSAMPLE_OUTPUT (SPI read-only)
    localparam ADDR_UPSAMPLE_OUTPUT_2      = 'd29;  // UPSAMPLE_OUTPUT (SPI read-only)
    localparam ADDR_UPSAMPLE_OUTPUT_3      = 'd30;  // UPSAMPLE_OUTPUT (SPI read-only)
    localparam ADDR_UPSAMPLE_OUTPUT_4      = 'd31;  // UPSAMPLE_OUTPUT (SPI read-only)

    localparam ADDR_FRAC_OUTPUT_1          = 'd32;  // FRACTIONAL_DECIMATOR_OUTPUT (SPI read-only)
    localparam ADDR_FRAC_OUTPUT_2          = 'd33;  // FRACTIONAL_DECIMATOR_OUTPUT (SPI read-only)
    localparam ADDR_FRAC_OUTPUT_3          = 'd34;  // FRACTIONAL_DECIMATOR_OUTPUT (SPI read-only)
    localparam ADDR_FRAC_OUTPUT_4          = 'd35;  // FRACTIONAL_DECIMATOR_OUTPUT (SPI read-only)

    localparam ADDR_IIR_OUTPUT_1           = 'd36;  // IIR_OUTPUT (SPI read-only)
    localparam ADDR_IIR_OUTPUT_2           = 'd37;  // IIR_OUTPUT (SPI read-only)
    localparam ADDR_IIR_OUTPUT_3           = 'd38;  // IIR_OUTPUT (SPI read-only)
    localparam ADDR_IIR_OUTPUT_4           = 'd39;  // IIR_OUTPUT (SPI read-only)

    localparam ADDR_CIC_OUTPUT_1           = 'd40;  // CIC_OUTPUT (SPI read-only)
    localparam ADDR_CIC_OUTPUT_2           = 'd41;  // CIC_OUTPUT (SPI read-only)
    localparam ADDR_CIC_OUTPUT_3           = 'd42;  // CIC_OUTPUT (SPI read-only)
    localparam ADDR_CIC_OUTPUT_4           = 'd43;  // CIC_OUTPUT (SPI read-only)

    localparam ADDR_CONTROL1        = 'd44;  // Control register 1
    localparam ADDR_CONTROL2        = 'd45;  // Control register 2
    
    
  

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
             for (int i = 0; i < REG_SIZE; i = i + 1) 
            registers[i] = 'h0;
        
        // CIC defaults
        registers[ADDR_CIC_D]           = 'd4;
        registers[ADDR_CIC_N]           = 'd4;
        
        // Fractional decimator defaults
        registers[ADDR_FRAC_L]          = 'd2;
        registers[ADDR_FRAC_M]          = 'd3;

        
        // FIR defaults
      
        registers[ADDR_FIR_TAPS_1]        = 'd250;
        registers[ADDR_FIR_TAPS_2]        = 'd0;

        registers[ADDR_FIR_COEFF_FRAC]  = 'd15;
        
        // IIR defaults (0.95 in S1.30, cos(2π*2.4/6))
        registers[ADDR_IIR_R1_1]          = 'b0011_1100;
        registers[ADDR_IIR_R1_2]          = 'b1100_1100;
        registers[ADDR_IIR_R1_3]          = 'b1100_1100;
        registers[ADDR_IIR_R1_4]          = 'b1100_1100;

        registers[ADDR_IIR_CO_THETA1_1]   = 'b0010_0000;
        registers[ADDR_IIR_CO_THETA1_2]   = 'b0000_0000;
        registers[ADDR_IIR_CO_THETA1_3]   = 'b0000_0000;
        registers[ADDR_IIR_CO_THETA1_4]   = 'b0000_0000;

        registers[ADDR_IIR_R2_1]          = 'b0011_1100;
        registers[ADDR_IIR_R2_2]          = 'b1100_1100;
        registers[ADDR_IIR_R2_3]          = 'b1100_1100;
        registers[ADDR_IIR_R2_4]          = 'b1100_1100;

        registers[ADDR_IIR_CO_THETA2_1]   = 'b1100_1100; // 2'comp
        registers[ADDR_IIR_CO_THETA2_2]   = 'b0011_1001; // 2'comp
        registers[ADDR_IIR_CO_THETA2_3]   = 'b0001_0000; // 2'comp
        registers[ADDR_IIR_CO_THETA2_4]   = 'b1100_1001; // 2'comp
            
        // Control: all blocks enabled, no bypass
        registers[ADDR_CONTROL1]        = 'h0F; // [3:0] = enable bits
        registers[ADDR_CONTROL2]        = 'h00; // [2:0] = bypass bits
        
     registers[ADDR_FIR_OUTPUT_1]           = 'd0;  // FIR_OUTPUT (SPI read-only)
     registers[ADDR_FIR_OUTPUT_2]          = 'd0;  // FIR_OUTPUT (SPI read-only)
     registers[ADDR_FIR_OUTPUT_3]           = 'd0;  // FIR_OUTPUT (SPI read-only)
     registers[ADDR_FIR_OUTPUT_4]           = 'd0;  // FIR_OUTPUT (SPI read-only)

     registers[ADDR_UPSAMPLE_OUTPUT_1]      = 'd0;  // UPSAMPLE_OUTPUT (SPI read-only)
     registers[ADDR_UPSAMPLE_OUTPUT_2]      = 'd0;  // UPSAMPLE_OUTPUT (SPI read-only)
     registers[ADDR_UPSAMPLE_OUTPUT_3]      = 'd0;  // UPSAMPLE_OUTPUT (SPI read-only)
     registers[ADDR_UPSAMPLE_OUTPUT_4]      = 'd0;  // UPSAMPLE_OUTPUT (SPI read-only)

     registers[ADDR_FRAC_OUTPUT_1]          = 'd0;  // FRACTIONAL_DECIMATOR_OUTPUT (SPI read-only)
     registers[ADDR_FRAC_OUTPUT_2]          = 'd0;  // FRACTIONAL_DECIMATOR_OUTPUT (SPI read-only)
     registers[ADDR_FRAC_OUTPUT_3]          = 'd0;  // FRACTIONAL_DECIMATOR_OUTPUT (SPI read-only)
     registers[ADDR_FRAC_OUTPUT_4]          = 'd0;  // FRACTIONAL_DECIMATOR_OUTPUT (SPI read-only)

     registers[ADDR_IIR_OUTPUT_1]           = 'd0;  // IIR_OUTPUT (SPI read-only)
     registers[ADDR_IIR_OUTPUT_2]           = 'd0;  // IIR_OUTPUT (SPI read-only)
     registers[ADDR_IIR_OUTPUT_3]           = 'd0;  // IIR_OUTPUT (SPI read-only)
     registers[ADDR_IIR_OUTPUT_4]           = 'd0;  // IIR_OUTPUT (SPI read-only)

     registers[ADDR_CIC_OUTPUT_1]           = 'd0;  // CIC_OUTPUT (SPI read-only)
     registers[ADDR_CIC_OUTPUT_2]           = 'd0;  // CIC_OUTPUT (SPI read-only)
     registers[ADDR_CIC_OUTPUT_3]           = 'd0;  // CIC_OUTPUT (SPI read-only)
     registers[ADDR_CIC_OUTPUT_4]           = 'd0;  // CIC_OUTPUT (SPI read-only)


        end else  begin

         if(wr_en)begin
              
           
            // SPI_write
             registers[addr]<=wr_data;
         end

         if(wr_sys_en)begin
             
             //SYSTEM_WRITE
             registers[ADDR_FIR_OUTPUT_1]<=FIR_OUTPUT[7:0];
             registers[ADDR_FIR_OUTPUT_2]<=FIR_OUTPUT[15:8];
             registers[ADDR_FIR_OUTPUT_3]<=FIR_OUTPUT[23:16];
             registers[ADDR_FIR_OUTPUT_4]<=FIR_OUTPUT[31:24];

             registers[ADDR_UPSAMPLE_OUTPUT_1]<=UPSAMPLE_OUTPUT[7:0];
             registers[ADDR_UPSAMPLE_OUTPUT_2]<=UPSAMPLE_OUTPUT[15:8];
             registers[ADDR_UPSAMPLE_OUTPUT_3]<=UPSAMPLE_OUTPUT[23:16];
             registers[ADDR_UPSAMPLE_OUTPUT_4]<=UPSAMPLE_OUTPUT[31:24];

             registers[ADDR_FRAC_OUTPUT_1]<=FRAC_OUTPUT[7:0];
             registers[ADDR_FRAC_OUTPUT_2]<=FRAC_OUTPUT[15:8];
             registers[ADDR_FRAC_OUTPUT_3]<=FRAC_OUTPUT[23:16];
             registers[ADDR_FRAC_OUTPUT_4]<=FRAC_OUTPUT[31:24];

             registers[ADDR_IIR_OUTPUT_1]<=IIR_OUTPUT[7:0];
             registers[ADDR_IIR_OUTPUT_2]<=IIR_OUTPUT[15:8];
             registers[ADDR_IIR_OUTPUT_3]<=IIR_OUTPUT[23:16];
             registers[ADDR_IIR_OUTPUT_4]<=IIR_OUTPUT[31:24];

             registers[ADDR_CIC_OUTPUT_1]<=CIC_OUTPUT[7:0];
             registers[ADDR_CIC_OUTPUT_2]<=CIC_OUTPUT[15:8];
             registers[ADDR_CIC_OUTPUT_3]<=CIC_OUTPUT[23:16];
             registers[ADDR_CIC_OUTPUT_4]<=CIC_OUTPUT[31:24];
         end
       
    end
end


    // SPI read
   assign rd_data=(!rst_n)?'d0:registers[addr];

   // SYSTEM read
always@(*)begin
 

L=registers[ADDR_FRAC_L]  ;

M= registers[ADDR_FRAC_M]  ;

TAPS={registers[ADDR_FIR_TAPS_2],registers[ADDR_FIR_TAPS_1]};

N= registers[ADDR_CIC_N];

R1={registers[ADDR_IIR_R1_4],registers[ADDR_IIR_R1_3],registers[ADDR_IIR_R1_2],registers[ADDR_IIR_R1_1]};

CO_THETA1={  registers[ADDR_IIR_CO_THETA1_4],  registers[ADDR_IIR_CO_THETA1_3],  registers[ADDR_IIR_CO_THETA1_2],  registers[ADDR_IIR_CO_THETA1_1]};

R2={registers[ADDR_IIR_R2_4],registers[ADDR_IIR_R2_3],registers[ADDR_IIR_R2_2],registers[ADDR_IIR_R2_1]};

CO_THETA2={  registers[ADDR_IIR_CO_THETA2_4],  registers[ADDR_IIR_CO_THETA2_3],  registers[ADDR_IIR_CO_THETA2_2],  registers[ADDR_IIR_CO_THETA2_1]};

D=  registers[ADDR_CIC_D] ;

enable= registers[ADDR_CONTROL1];

bypass=registers[ADDR_CONTROL2] ;





end

endmodule