
////////////////////////////////////////////////////////////////////////////////
// Testbench
////////////////////////////////////////////////////////////////////////////////

module tb_FIR_IIR;

    parameter DATA_WIDTH = 32;
    parameter CLK_PERIOD = 10;
    parameter INPUTWIDTH = 32;
    bit clk,clk_1,clk_spi, rst_n, enable,mosi,cs_n,miso;
    bit signed [DATA_WIDTH-1:0] data_in;
    bit data_in_valid;
    bit signed [DATA_WIDTH-1:0] data_out;
    bit data_out_valid;
  
    integer input_file, output_file;
    integer scan_result;
    real input_value_float;
    integer input_count, output_count;
    wire [7:0]  L=2;
wire [7:0]M=3; 
  reg[7:0] wr_data;
   reg wr_en;
reg [5:0]addr;
wire [7:0]rd_data;
wire ready;
    FIR_IIR #(
     32,     
        32,
    15
    
)dut(
     clk,
     clk_1  ,
     clk_spi,
     mosi,
     cs_n,
     rst_n,   
     data_in,      
     data_in_valid,
     data_out,
     data_out_valid,
     ready,
     miso
);
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    initial begin
        clk_1 = 0;
        forever #(3*CLK_PERIOD/2) clk_1 = ~clk_1;
    end
     initial begin
        clk_spi = 0;
        forever #(CLK_PERIOD/2) clk_spi = ~clk_spi;
    end
    // Output capture
    always @(posedge clk_1) begin
        if (data_out_valid) begin
            $fwrite(output_file, "%f\n", data_out);
            output_count = output_count + 1;
            
            if (output_count <= 20) begin
                $display("[%0t] OUT[%3d] = %f (0x%08h)", 
                         $time, output_count-1, data_out, data_out);
            end
        end
    end
    
    initial begin
        rst_n = 0;
        enable = 0;
        data_in = 0;
        data_in_valid = 0;
        input_count = 0;
        output_count = 0;
         wr_data=0;
        wr_en=0;
       addr=0;
        input_file = $fopen("stimulus_input.txt", "r");
        output_file = $fopen("verilogIIR_output.txt", "w");
        
        if (input_file == 0 || output_file == 0) begin
            $display("ERROR: Cannot open files");
            $finish;
        end
        
        #200;
        rst_n = 1;
         wr_data=8'b00001111;
        wr_en=1;
       addr=6'd44;
        #100;
        enable = 1;
         wr_data=0;
        wr_en=0;
       addr=0;

        #100;
        
        // Feed inputs
        while (!$feof(input_file)) begin
               @(posedge clk);
          
          
            if(ready)begin
            scan_result = $fscanf(input_file, "%f\n", input_value_float);
            
            if (scan_result == 1&& output_count<9000&&input_count<27000) begin
                 data_in = input_value_float;
                  data_in_valid = 1;
                input_count = input_count + 1;
                
                if (input_count <= 10) begin
                    $display("[%0t] IN[%3d] = %f (0x%08h)", 
                             $time, input_count-1, input_value_float, data_in);
                end
                
              end
            end
            else 
                data_in_valid=0;
        end
        
        $fclose(input_file);
      
        
        $fclose(output_file);
        
       
        $display("Inputs:  %0d", input_count);
        $display("Outputs: %0d", output_count);
        $display("Ratio:   %.4f (expected %.4f)", 
                 real'(output_count)/real'(input_count), real'(L)/real'(M));
        $finish;
    end
    
   
  

endmodule