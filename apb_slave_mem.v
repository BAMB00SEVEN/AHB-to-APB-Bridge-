//=============================================================================
// File        : apb_slave_mem.v
// Module      : apb_slave_mem
// Description : Minimal APB slave: a byte-addressable register file used
//               as the downstream peripheral for bridge verification.
//               Zero-wait-state (PREADY tied high) by default; the
//               WAIT_CYCLES parameter can inject extra wait states to
//               exercise the bridge's PREADY-stall handling.
//=============================================================================

module apb_slave_mem #(
    parameter ADDR_WIDTH  = 8,     // 2^8 words
    parameter DATA_WIDTH  = 32,
    parameter WAIT_CYCLES = 0      // 0 = always-ready slave
) (
    input  wire                   PCLK,
    input  wire                   PRESETn,
    input  wire                   PSEL,
    input  wire                   PENABLE,
    input  wire                   PWRITE,
    input  wire [ADDR_WIDTH-1:0]  PADDR,
    input  wire [DATA_WIDTH-1:0]  PWDATA,
    output wire [DATA_WIDTH-1:0]  PRDATA,
    output wire                   PREADY
);

    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    generate
        if (WAIT_CYCLES == 0) begin : g_zero_wait
            assign PREADY = 1'b1;
        end else begin : g_wait_states
            reg [7:0] wait_cnt;
            reg       ready_r;
            assign PREADY = ready_r;

            always @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    wait_cnt <= 0;
                    ready_r  <= 1'b0;
                end else if (PSEL && !PENABLE) begin
                    // SETUP phase: arm the wait counter
                    wait_cnt <= WAIT_CYCLES[7:0];
                    ready_r  <= (WAIT_CYCLES == 0);
                end else if (PSEL && PENABLE) begin
                    if (wait_cnt == 0) begin
                        ready_r <= 1'b1;
                    end else begin
                        wait_cnt <= wait_cnt - 1'b1;
                        ready_r  <= (wait_cnt == 1);
                    end
                end else begin
                    ready_r <= 1'b0;
                end
            end
        end
    endgenerate

    // Async read: PRDATA must be valid combinationally *during* the
    // ACCESS phase (before/at the edge the bridge samples PREADY), not
    // one cycle later - otherwise the bridge would capture stale data.
    assign PRDATA = mem[PADDR];

    // Sync write: committed on the edge that completes the transfer.
    always @(posedge PCLK) begin
        if (PSEL && PENABLE && PREADY && PWRITE)
            mem[PADDR] <= PWDATA;
    end

endmodule
