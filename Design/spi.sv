//==============================================================================
// SPI Slave Interface
// Mode 0 (CPOL=0, CPHA=0): Sample MOSI on rising edge, shift MISO on falling edge
// 3-byte transaction: Command[7:0] -> Address[7:0] -> Data[7:0]
// Command bit[7]: 0=read, 1=write
//==============================================================================

module spi_slave (
    // SPI Interface
    input  wire       sclk,
    input  wire       cs_n,
    input  wire       mosi,
    output wire       miso,

    // Register File Interface
    output reg        rf_wr_en,
    output reg  [7:0] rf_addr,
    output reg  [7:0] rf_wdata,
    input  wire [7:0] rf_rdata
);

    //--------------------------------------------------------------------------
    // Internal Signals
    //--------------------------------------------------------------------------
    // Command byte parameters
    localparam [7:0] RD_CMD = 8'h00;  // Read command (MSB = 0)
    localparam [7:0] WR_CMD = 8'h80;  // Write command (MSB = 1)

    // RX FSM States
    localparam [2:0] RX_CMD       = 3'd0;
    localparam [2:0] RX_RD_ADDR   = 3'd1;
    localparam [2:0] RX_RD_DATA   = 3'd2;
    localparam [2:0] RX_WR_ADDR   = 3'd3;
    localparam [2:0] RX_WR_DATA   = 3'd4;

    // RX Sequential signals (state registers)
    reg [2:0] rx_state, rx_state_next;    // Current and next FSM state
    reg [2:0] bit_cnt, bit_cnt_next;      // Bit counter within current byte (0-7)
    reg [7:0] mosi_reg, mosi_reg_next;    // Registered MOSI shift register
    reg [7:0] cmd_reg, cmd_reg_next;      // Captured command byte
    reg [7:0] rf_addr_reg, rf_addr_next;  // Next address for register file

    // TX Sequential signals
    reg [7:0] miso_reg;        // Output shift register

    // RX Combinational signals
    wire      byte_complete;
    assign byte_complete = (bit_cnt == 3'd7);

    //--------------------------------------------------------------------------
    // FPGA Power-up Initialization
    //--------------------------------------------------------------------------
    initial begin
        rx_state      = RX_CMD;
        bit_cnt       = 3'd0;
        mosi_reg      = 8'd0;
        cmd_reg       = 8'd0; 
        rf_wr_en      = 1'b0;
        rf_addr       = 8'd0;
        rf_wdata      = 8'd0;
        miso_reg      = 8'd0;
    end

    //--------------------------------------------------------------------------
    // RX FSM - Sequential Logic (Rising Edge of SCLK)
    // Updates state registers from next-state values
    // Asynchronous reset on posedge cs_n (end of transaction)
    //--------------------------------------------------------------------------
    always @(posedge sclk or posedge cs_n) begin
        if (cs_n) begin
            // Transaction ended - async reset to idle state
            rx_state      <= RX_CMD;
            bit_cnt       <= 3'd0;
            mosi_reg      <= 8'd0;
            cmd_reg       <= 8'd0;
            rf_addr_reg   <= 8'd0; 
        end else begin
            // Update state registers from next-state logic
            rx_state      <= rx_state_next;
            bit_cnt       <= bit_cnt_next;
            mosi_reg      <= mosi_reg_next;
            cmd_reg       <= cmd_reg_next;
            rf_addr_reg   <= rf_addr_next; 
        end
    end

    //--------------------------------------------------------------------------
    // RX FSM - Combinational Logic (Next State and Outputs)
    //--------------------------------------------------------------------------
    always @(*) begin
        // Default: hold current state
        rx_state_next      = rx_state; 
        mosi_reg_next      = {mosi_reg[6:0], mosi};  // Always shift in MOSI
        cmd_reg_next       = cmd_reg;
        rf_addr_next       = rf_addr_reg;
        rf_addr            = rf_addr_reg;
        rf_wr_en           = 1'b0;
        rf_wdata           = 8'b0; 
        bit_cnt_next       = bit_cnt + 1'b1;

        // FSM State transitions and next-state logic
        case (rx_state)
            RX_CMD: begin
                // Capture complete command byte
                cmd_reg_next = {mosi_reg[6:0], mosi}; 
                // State transition logic
                if (byte_complete) begin
                    // Decode command and branch to appropriate path
                    if ({mosi_reg[6:0], mosi} == RD_CMD) begin  // MSB=0 indicates READ
                        rx_state_next = RX_RD_ADDR;
                    end else if ({mosi_reg[6:0], mosi} == WR_CMD) begin
                        rx_state_next = RX_WR_ADDR;
                    end else begin
                        // Invalid command - return to CMD state
                        rx_state_next = RX_CMD;
                    end 
                end
            end

            RX_RD_ADDR: begin
                // Read path - address byte
                if (byte_complete) begin
                    // Capture address for read operation
                    rf_addr_next  = {mosi_reg[6:0], mosi};
                    rf_addr       = {mosi_reg[6:0], mosi};
                    rx_state_next = RX_RD_DATA;
                end
            end

            RX_WR_ADDR: begin
                // Write path - address byte
                if (byte_complete) begin
                    // Capture address for write operation
                    rf_addr_next  = {mosi_reg[6:0], mosi};
                    rx_state_next = RX_WR_DATA;
                end
            end

            RX_RD_DATA: begin
                // Read path - data byte (master is clocking out data)
                if (byte_complete) begin
                    // Stay in RD_DATA state (could extend for multi-byte reads)
                    rf_addr_next  = rf_addr_reg + 1'b1; // Increment address for potential multi-byte read
                    rf_addr       = rf_addr_reg + 1'b1;
                end
            end


            RX_WR_DATA: begin
                // Write path - data byte
                if (byte_complete) begin
                    // Capture write data and mark pending   
                    rf_wr_en        = 1'b1;
                    rf_wdata        = {mosi_reg[6:0], mosi};
                    // Stay in WR_DATA state (could extend for multi-byte writes)
                    rf_addr_next    = rf_addr_reg + 1'b1; // Increment address for potential multi-byte write
                end 
            end

            default: begin
                rx_state_next = RX_CMD;
            end
        endcase
    end

 

    //--------------------------------------------------------------------------
    // MISO Output (Falling Edge of SCLK) - SPI Mode 0
    // Timing: MISO changes on falling edge, master samples on next rising edge
    //--------------------------------------------------------------------------
    always @(negedge sclk or posedge cs_n) begin
        if (cs_n) begin
            miso_reg     <= 8'd0;
        end else begin
            // For read operations during data byte phase
            if (rx_state == RX_RD_DATA) begin
                if (bit_cnt == 3'd0) begin
                    // First bit of data byte: output MSB directly, load remaining bits
                    miso_reg <= rf_rdata; 
                end else begin
                    // Subsequent bits: output from shift register, then shift
                    miso_reg <= miso_reg << 1;
                end
            end else begin
                miso_reg <= 8'b0;
            end
        end
    end

    assign miso = miso_reg[7];

endmodule