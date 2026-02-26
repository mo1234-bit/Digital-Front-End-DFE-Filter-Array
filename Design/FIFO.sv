module fifo #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 4 
)(
   (* keep = "true" *)  input  wire                     wr_clk,
   (* keep = "true" *)  input  wire                     rst_n,
    (* keep = "true" *) input  wire signed[DATA_WIDTH-1:0]    wr_data,
   (* keep = "true" *)  input  wire                     wr_en,
   (* keep = "true" *)  output reg signed [DATA_WIDTH-1:0]    rd_data,
   (* keep = "true" *)  input                 rd_clk,
   (* keep = "true" *)  output reg en
);

    reg rd_en;
  
    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr;
   
    reg signed [DATA_WIDTH-1:0] fifo_mem [(1<<ADDR_WIDTH)-1:0];
    
reg empty;
reg [ADDR_WIDTH:0] wr_ptr_bin, rd_ptr_bin;
reg [ADDR_WIDTH:0] wr_ptr_gray, rd_ptr_gray;
reg [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;
reg [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;


always @(posedge wr_clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr_bin  <= 0;
        wr_ptr_gray <= 0;
    end else if (wr_en) begin
        wr_ptr_bin  <= wr_ptr_bin + 1;
        wr_ptr_gray <= (wr_ptr_bin + 1) ^ ((wr_ptr_bin + 1) >> 1);
    end
end


always @(posedge rd_clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_ptr_bin  <= 0;
        rd_ptr_gray <= 0;
    end else if (rd_en) begin
        rd_ptr_bin  <= rd_ptr_bin + 1;
        rd_ptr_gray <= (rd_ptr_bin + 1) ^ ((rd_ptr_bin + 1) >> 1);
    end
end


always @(posedge wr_clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_ptr_gray_sync1 <= 0;
        rd_ptr_gray_sync2 <= 0;
    end else begin
        rd_ptr_gray_sync1 <= rd_ptr_gray;
        rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
    end
end


always @(posedge rd_clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr_gray_sync1 <= 0;
        wr_ptr_gray_sync2 <= 0;
    end else begin
        wr_ptr_gray_sync1 <= wr_ptr_gray;
        wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
    end
end


always @(posedge wr_clk) begin
    if (wr_en)
        fifo_mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
end
reg empty_past;
    always @(posedge rd_clk) begin
        if(!rst_n)begin
            en<=0;
            rd_en<=0;
            rd_data<=0;
            empty_past<=1;
        end else begin
            empty_past<=empty;
        if(!empty_past)
            en<=1;
        
        if(!empty)
            rd_en<=1;

        if (rd_en)
            rd_data <= fifo_mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
    end
    end



assign empty = (rd_ptr_gray == wr_ptr_gray_sync2)?1:0;

endmodule