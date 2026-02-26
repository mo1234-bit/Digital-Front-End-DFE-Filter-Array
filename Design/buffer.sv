module buffer #(
    parameter BUFFER_SIZE = 64,
    parameter ADDR_WIDTH  = $clog2(BUFFER_SIZE)
)(
    input  wire              clk,
    input  wire              rst_n,      
    input  wire signed [31:0] data_in,
    input  wire              wr_en,
    input  wire              rd_en,
    input  wire [7:0]   L,
    output reg signed [31:0]       data_out,
    output reg               full,
    output reg               empty,
    output reg [ADDR_WIDTH:0]   count,count_past
);

reg signed[31:0] BUFFER [0:BUFFER_SIZE-1];
reg [ADDR_WIDTH-1:0] wr_ptr, rd_ptr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr   <= 0;
        rd_ptr   <= 0;
        count    <= 0;
        data_out <= 0;
        full     <= 0;
        empty    <= 1;
        count_past<=0;
    end
    else begin

        // WRITE
        if (wr_en && !full) begin
            BUFFER[wr_ptr] <= data_in;
            wr_ptr <= wr_ptr + 1;
        end

        // READ
        if (rd_en && !empty) begin
            data_out <= BUFFER[rd_ptr];
            rd_ptr <= rd_ptr + 1;
        end

        // COUNT UPDATE
        case ({wr_en && !full, rd_en && !empty})
            2'b10: count <= count + 1;
            2'b01: count <= count - 1;
            default: count <= count;
        endcase
        if(count==L)
        	count<=count-1;
        // STATUS FLAGS
        empty <= (count == 0);
        full  <= (count == BUFFER_SIZE);
        count_past<=count;
    end
end

endmodule
