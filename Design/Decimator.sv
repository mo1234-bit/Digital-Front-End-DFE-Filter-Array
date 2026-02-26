module downsampler #(
    parameter DATA_WIDTH = 32
)(
   (* keep = "true" *)  input  wire                          clk,
   (* keep = "true" *)  input  wire                          rst_n,
   (* keep = "true" *)  input  wire                          din_valid,      // Input sample valid
   (* keep = "true" *)  input  wire signed [DATA_WIDTH-1:0]  din,  
   (* keep = "true" *)  input  wire [7:0]M,        
   (* keep = "true" *)  output reg                           dout_valid,     // Output sample valid
   (* keep = "true" *)  output reg  signed [DATA_WIDTH-1:0]  dout           // Output sample
);

    // Counter to track which sample to keep
    reg [7:0] sample_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_count <= 0;
            dout_valid <= 0;
            dout <= 0;
        end else begin
            if (din_valid) begin
                if (sample_count == 0) begin
                    // Keep this sample (every Mth sample)
                    dout <= din;
                    dout_valid <= 1;
                end else begin
                    // Discard this sample
                    dout_valid <= 0;
                end
                
                // Increment counter (wraps at M)
                if (sample_count == M - 1)
                    sample_count <= 0;
                else
                    sample_count <= sample_count + 1;
            end else begin
                dout_valid <= 0;
            end
        end
    end

endmodule