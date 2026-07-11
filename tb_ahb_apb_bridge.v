//=============================================================================
// File        : tb_ahb_apb_bridge.v
// Description : Self-checking testbench for ahb_apb_bridge.
//               Drives AHB-Lite single-transfer writes/reads, checks
//               read-back data, and reports a PASS/FAIL summary.
//               Simulator target: Icarus Verilog (iverilog + vvp).
// Author      : Parth Batra
//=============================================================================
`timescale 1ns/1ps

module tb_ahb_apb_bridge;

    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;

    // ---------------- AHB-side signals (driven by this testbench) --------
    reg                    HCLK;
    reg                    HRESETn;
    reg                    HSEL;
    reg  [ADDR_WIDTH-1:0]  HADDR;
    reg  [1:0]             HTRANS;
    reg                    HWRITE;
    reg  [2:0]             HSIZE;
    reg  [DATA_WIDTH-1:0]  HWDATA;
    wire                   HREADYOUT;
    wire [DATA_WIDTH-1:0]  HRDATA;
    wire                   HRESP;

    // Single-slave system: global HREADY is this slave's own HREADYOUT
    wire HREADY = HREADYOUT;

    // ---------------- APB-side signals (bridge <-> peripheral) -----------
    wire                   PSEL;
    wire                   PENABLE;
    wire [ADDR_WIDTH-1:0]  PADDR;
    wire                   PWRITE;
    wire [DATA_WIDTH-1:0]  PWDATA;
    wire [DATA_WIDTH-1:0]  PRDATA;
    wire                   PREADY;

    integer pass_count = 0;
    integer fail_count = 0;

    // ---------------- DUT ---------------------------------------------
    ahb_apb_bridge #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_bridge (
        .HCLK      (HCLK),
        .HRESETn   (HRESETn),
        .HSEL      (HSEL),
        .HADDR     (HADDR),
        .HTRANS    (HTRANS),
        .HWRITE    (HWRITE),
        .HSIZE     (HSIZE),
        .HWDATA    (HWDATA),
        .HREADY    (HREADY),
        .HREADYOUT (HREADYOUT),
        .HRDATA    (HRDATA),
        .HRESP     (HRESP),

        .PSEL      (PSEL),
        .PENABLE   (PENABLE),
        .PADDR     (PADDR),
        .PWRITE    (PWRITE),
        .PWDATA    (PWDATA),
        .PRDATA    (PRDATA),
        .PREADY    (PREADY)
    );

    // Bump WAIT_CYCLES to exercise the bridge's PREADY-stall handling
    apb_slave_mem #(
        .ADDR_WIDTH  (8),
        .DATA_WIDTH  (DATA_WIDTH),
        .WAIT_CYCLES (2)
    ) u_apb_slave (
        .PCLK    (HCLK),
        .PRESETn (HRESETn),
        .PSEL    (PSEL),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PADDR   (PADDR[7:0]),
        .PWDATA  (PWDATA),
        .PRDATA  (PRDATA),
        .PREADY  (PREADY)
    );

    // ---------------- Clock: 100 MHz -----------------------------------
    initial HCLK = 1'b0;
    always #5 HCLK = ~HCLK;

    // ---------------- AHB-Lite single-transfer driver tasks -------------
    task ahb_write(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        begin
            @(negedge HCLK);
            wait (HREADYOUT == 1'b1);
            HSEL   = 1'b1;
            HTRANS = 2'b10;  // NONSEQ
            HWRITE = 1'b1;
            HADDR  = addr;
            HWDATA = data;

            @(negedge HCLK);
            HTRANS = 2'b00;  // IDLE, transfer already latched by bridge
            HSEL   = 1'b0;

            wait (HREADYOUT == 1'b1);
            @(negedge HCLK);
        end
    endtask

    task ahb_read(input [ADDR_WIDTH-1:0] addr, output [DATA_WIDTH-1:0] rdata);
        begin
            @(negedge HCLK);
            wait (HREADYOUT == 1'b1);
            HSEL   = 1'b1;
            HTRANS = 2'b10;  // NONSEQ
            HWRITE = 1'b0;
            HADDR  = addr;

            @(negedge HCLK);
            HTRANS = 2'b00;
            HSEL   = 1'b0;

            wait (HREADYOUT == 1'b1);
            rdata = HRDATA;
            @(negedge HCLK);
        end
    endtask

    task check_read(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] expected);
        reg [DATA_WIDTH-1:0] got;
        begin
            ahb_read(addr, got);
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] t=%0t addr=0x%08h expected=0x%08h got=0x%08h",
                          $time, addr, expected, got);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] t=%0t addr=0x%08h expected=0x%08h got=0x%08h",
                          $time, addr, expected, got);
            end
        end
    endtask

    // ---------------- Stimulus ------------------------------------------
    initial begin
        $dumpfile("ahb_apb_bridge.vcd");
        $dumpvars(0, tb_ahb_apb_bridge);

        HRESETn = 1'b0;
        HSEL    = 1'b0;
        HADDR   = {ADDR_WIDTH{1'b0}};
        HTRANS  = 2'b00;
        HWRITE  = 1'b0;
        HSIZE   = 3'b010; // word
        HWDATA  = {DATA_WIDTH{1'b0}};

        repeat (4) @(negedge HCLK);
        HRESETn = 1'b1;
        @(negedge HCLK);

        // Test 1: single write then read-back
        ahb_write(32'h0000_0000, 32'hDEAD_BEEF);
        check_read(32'h0000_0000, 32'hDEAD_BEEF);

        // Test 2: multiple addresses, distinct data
        ahb_write(32'h0000_0004, 32'hCAFE_F00D);
        ahb_write(32'h0000_0008, 32'h1234_5678);
        ahb_write(32'h0000_000C, 32'hA5A5_5A5A);

        check_read(32'h0000_0004, 32'hCAFE_F00D);
        check_read(32'h0000_0008, 32'h1234_5678);
        check_read(32'h0000_000C, 32'hA5A5_5A5A);

        // Test 3: overwrite an existing address
        ahb_write(32'h0000_0000, 32'h0000_0001);
        check_read(32'h0000_0000, 32'h0000_0001);

        // Test 4: back-to-back writes immediately followed by reads
        ahb_write(32'h0000_0010, 32'h1111_1111);
        ahb_write(32'h0000_0014, 32'h2222_2222);
        check_read(32'h0000_0014, 32'h2222_2222);
        check_read(32'h0000_0010, 32'h1111_1111);

        // ---------------- Summary ----------------
        $display("--------------------------------------------------");
        $display(" AHB-APB Bridge Testbench Summary");
        $display("   PASS : %0d", pass_count);
        $display("   FAIL : %0d", fail_count);
        if (fail_count == 0)
            $display(" RESULT: ALL TESTS PASSED");
        else
            $display(" RESULT: %0d TEST(S) FAILED", fail_count);
        $display("--------------------------------------------------");

        #20;
        $finish;
    end

    // Safety timeout in case of a hang
    initial begin
        #10000;
        $display("[TIMEOUT] Simulation did not finish in time - possible hang.");
        $finish;
    end

endmodule
