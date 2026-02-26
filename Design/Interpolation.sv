module upsampler #(
    parameter DATA_WIDTH = 32
)(
    (* keep = "true" *) input  wire                          clk,
   (* keep = "true" *)  input  wire                          rst,
  (* keep = "true" *)   input  wire                          din_valid,      // Input sample valid
   (* keep = "true" *)  input  wire signed [DATA_WIDTH-1:0]  din,           // Input sample
   (* keep = "true" *)  input  wire [7:0]L, 
   (* keep = "true" *)  output reg                           dout_valid,     // Output sample valid
   (* keep = "true" *)  output reg  signed [DATA_WIDTH-1:0]  dout           // Output sample
);

    // Counter to track zero insertions
    reg [7:0] zero_count;

    always @(posedge clk) begin
        if (!rst) begin
            zero_count <= 0;
            dout_valid <= 0;
            dout <= 0;
        end else begin
            if (din_valid) begin
                // New input sample arrives - output it immediately
                dout <= din;
                dout_valid <= 1;
                zero_count <= 1;  // Start counting zeros
            end else if (zero_count > 0 && zero_count < L) begin
                // Insert zeros between samples
                dout <= 0;
                dout_valid <= 1;
                zero_count <= zero_count + 1;
            end else begin
                // Waiting for next input or finished zero insertion
                dout_valid <= 0;
                if (zero_count == L)
                    zero_count <= 0;
            end
        end
    end

endmodule