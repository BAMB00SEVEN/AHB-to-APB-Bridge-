//=============================================================================
// File        : ahb_apb_bridge.v
// Module      : ahb_apb_bridge
// Description : AHB-Lite (slave side) to APB (master side) protocol bridge.
//               Accepts a single AHB-Lite NONSEQ transfer, stalls the AHB
//               bus via HREADYOUT while it drives the equivalent two/three
//               phase APB SETUP -> ACCESS transaction (with PREADY wait
//               state support), then returns the read/write result to the
//               AHB master.
//
//               This bridge targets a single downstream APB peripheral.
//               For multiple peripherals, instantiate an address decoder
//               ahead of PSEL (see docs/architecture.md, "Future Work").
//
// Author      : Parth Batra
//=============================================================================

module ahb_apb_bridge #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    // ------------------------------------------------------------
    // AHB-Lite slave interface (bridge acts as an AHB slave)
    // ------------------------------------------------------------
    input  wire                    HCLK,
    input  wire                    HRESETn,
    input  wire                    HSEL,
    input  wire [ADDR_WIDTH-1:0]   HADDR,
    input  wire [1:0]              HTRANS,     // 00=IDLE 01=BUSY 10=NONSEQ 11=SEQ
    input  wire                    HWRITE,
    input  wire [2:0]              HSIZE,
    input  wire [DATA_WIDTH-1:0]   HWDATA,
    input  wire                    HREADY,     // HREADY from previous slave (mux)
    output reg                     HREADYOUT,  // this slave's ready output
    output reg  [DATA_WIDTH-1:0]   HRDATA,
    output reg                     HRESP,      // 0 = OKAY, 1 = ERROR (unused, tied 0)

    // ------------------------------------------------------------
    // APB master interface (bridge acts as the single APB master)
    // ------------------------------------------------------------
    output reg                     PSEL,
    output reg                     PENABLE,
    output reg  [ADDR_WIDTH-1:0]   PADDR,
    output reg                     PWRITE,
    output reg  [DATA_WIDTH-1:0]   PWDATA,
    input  wire [DATA_WIDTH-1:0]   PRDATA,
    input  wire                    PREADY
);

    // ------------------------------------------------------------
    // FSM state encoding
    // ------------------------------------------------------------
    localparam ST_IDLE   = 2'b00;
    localparam ST_SETUP  = 2'b01;
    localparam ST_ACCESS = 2'b10;

    reg [1:0] state, next_state;

    // Latched AHB address-phase info, held stable for the APB transfer
    reg [ADDR_WIDTH-1:0] addr_latched;
    reg                  write_latched;

    // A valid AHB address-phase transfer selecting this bridge
    wire ahb_addr_phase = HSEL & HREADY & HTRANS[1]; // NONSEQ(10) or SEQ(11)

    // ------------------------------------------------------------
    // State register
    // ------------------------------------------------------------
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            state <= ST_IDLE;
        else
            state <= next_state;
    end

    // ------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            ST_IDLE: begin
                if (ahb_addr_phase)
                    next_state = ST_SETUP;
            end

            ST_SETUP: begin
                // One cycle in SETUP, then always move to ACCESS
                next_state = ST_ACCESS;
            end

            ST_ACCESS: begin
                if (PREADY)
                    next_state = ST_IDLE;
                else
                    next_state = ST_ACCESS; // insert wait state(s)
            end

            default: next_state = ST_IDLE;
        endcase
    end

    // ------------------------------------------------------------
    // Address-phase capture (address, write, and later write-data)
    // ------------------------------------------------------------
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            addr_latched  <= {ADDR_WIDTH{1'b0}};
            write_latched <= 1'b0;
        end else if (ahb_addr_phase) begin
            addr_latched  <= HADDR;
            write_latched <= HWRITE;
        end
    end

    // Write data becomes valid on the AHB data phase, i.e. the cycle
    // the bridge enters ST_SETUP (HWDATA is valid in that same cycle for
    // an AHB-Lite single transfer). Capture it there for the APB write.
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            PWDATA <= {DATA_WIDTH{1'b0}};
        else if (state == ST_SETUP && write_latched)
            PWDATA <= HWDATA;
    end

    // ------------------------------------------------------------
    // APB output logic (Moore-style, driven from current state)
    // ------------------------------------------------------------
    always @(*) begin
        PSEL    = (state == ST_SETUP) || (state == ST_ACCESS);
        PENABLE = (state == ST_ACCESS);
        PADDR   = addr_latched;
        PWRITE  = write_latched;
    end

    // ------------------------------------------------------------
    // AHB response logic
    // ------------------------------------------------------------
    // HREADYOUT must be visible within the *current* cycle so the
    // AHB master/mux can react without an extra cycle of latency ->
    // combinational, driven off the registered state + live PREADY.
    always @(*) begin
        HRESP = 1'b0; // OKAY always; extend here to add PSLVERR support
        case (state)
            ST_IDLE:   HREADYOUT = 1'b1;
            ST_SETUP:  HREADYOUT = 1'b0;
            ST_ACCESS: HREADYOUT = PREADY;
            default:   HREADYOUT = 1'b1;
        endcase
    end

    // HRDATA must be valid in the *same* cycle HREADYOUT signals
    // completion, so it is a direct combinational pass-through of the
    // APB read data (the AHB master only samples it when HREADYOUT=1).
    always @(*) HRDATA = PRDATA;

endmodule
