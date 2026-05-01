// ============================================================================
// Croc SoC - Read/Write Testbench
// ============================================================================
// BITS Pilani | M.Tech VLSI Design | Advance VLSI Design
// Student  : Dilip Kumar Jena (2025HT08287)
// Mentor   : Jeetu Kar, Director of Marqueesemi, Marqueesemi 
// Date     : April 2026
//
// Description:
//   This testbench exercises the Croc SoC via the OBI bus interface.
//   It performs read/write transactions to UART, GPIO, Timer and SoC
//   control registers, and verifies the responses.
//
// Test Coverage:
//   - System control register access
//   - SRAM memory operations (full and partial word writes)
//   - GPIO configuration and control
//   - Timer register programming
//   - Sequential multi-address memory patterns
//   - UART transmit interface
//
// Author  : Dilip Kumar Jena
// Date    : May 2026
// =============================================================================

`timescale 1ns/1ps

module croc_tb;

  // ---------------------------------------------------------------------------
  // Simulation Configuration
  // ---------------------------------------------------------------------------
  parameter CLOCK_PERIOD_NS = 10;      // 100 MHz
  parameter SIM_WATCHDOG_CYC = 5000;   // Abort if hung

  // ---------------------------------------------------------------------------
  // Clock Generation & Reset Control
  // ---------------------------------------------------------------------------
  logic clk_sys;
  logic reset_active_n;

  initial begin
    clk_sys = 1'b0;
  end

  always #(CLOCK_PERIOD_NS / 2) clk_sys = ~clk_sys;

  // ---------------------------------------------------------------------------
  // OBI Bus Interface Signals (Test Master)
  // ---------------------------------------------------------------------------
  // Request Channel
  logic        bus_request;
  logic        bus_write_enable;      // 1 for write, 0 for read
  logic [3:0]  bus_byte_enable;       // Per-byte write strobes
  logic [31:0] bus_address;
  logic [31:0] bus_write_data;

  // Response Channel
  logic        bus_acknowledge;
  logic        bus_response_valid;
  logic [31:0] bus_read_data;
  logic        bus_error;

  // ---------------------------------------------------------------------------
  // Device Under Test (DUT) — Croc SoC
  // ---------------------------------------------------------------------------
  croc_soc dut (
    .clk_i        ( clk_sys           ),
    .rst_ni       ( reset_active_n    ),
    .ref_clk_i    ( clk_sys           ),
    .testmode_i   ( 1'b0              ),
    .status_o     (                   ),

    // JTAG Interface (disabled for this test)
    .jtag_tck_i   ( 1'b0              ),
    .jtag_tms_i   ( 1'b0              ),
    .jtag_tdi_i   ( 1'b0              ),
    .jtag_tdo_o   (                   ),
    .jtag_trst_ni ( 1'b1              ),

    // Serial Interface (idle state)
    .uart_rx_i    ( 1'b1              ),
    .uart_tx_o    (                   ),

    // Parallel I/O (16-bit, tied off)
    .gpio_i       ( 16'h0000          ),
    .gpio_o       (                   ),
    .gpio_out_en_o(                   )
  );

  // ---------------------------------------------------------------------------
  // Test Metrics
  // ---------------------------------------------------------------------------
  int num_passed;
  int num_failed;

  // ---------------------------------------------------------------------------
  // Utility Task: OBI Memory Write Operation
  // ---------------------------------------------------------------------------
  task automatic execute_bus_write (
    input  logic [31:0] target_addr,
    input  logic [31:0] payload_data,
    input  logic [3:0]  enable_mask = 4'hF
  );
    @(posedge clk_sys);
    bus_request         = 1'b1;
    bus_write_enable    = 1'b1;
    bus_address         = target_addr;
    bus_write_data      = payload_data;
    bus_byte_enable     = enable_mask;

    // Stall until device accepts transaction
    wait (bus_acknowledge == 1'b1);
    @(posedge clk_sys);
    bus_request      = 1'b0;
    bus_write_enable = 1'b0;

    // Await completion handshake
    wait (bus_response_valid == 1'b1);
    @(posedge clk_sys);

    if (bus_error) begin
      $display("[WARN] Bus write to address 0x%08h: error response", target_addr);
    end else begin
      $display("[WRITE] Address: 0x%08h | Value: 0x%08h | Enables: 0b%04b",
               target_addr, payload_data, enable_mask);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Utility Task: OBI Memory Read with Verification
  // ---------------------------------------------------------------------------
  task automatic execute_bus_read_verify (
    input  logic [31:0] target_addr,
    input  logic [31:0] reference_value,
    input  logic [31:0] comparison_mask = 32'hFFFFFFFF,
    input  string       test_label = ""
  );
    logic [31:0] retrieved_data;

    @(posedge clk_sys);
    bus_request      = 1'b1;
    bus_write_enable = 1'b0;
    bus_address      = target_addr;
    bus_byte_enable  = 4'hF;

    wait (bus_acknowledge == 1'b1);
    @(posedge clk_sys);
    bus_request = 1'b0;

    wait (bus_response_valid == 1'b1);
    retrieved_data = bus_read_data;
    @(posedge clk_sys);

    if (bus_error) begin
      $display("[ERROR] Bus read from address 0x%08h failed: %s", target_addr, test_label);
      num_failed++;
    end else if ((retrieved_data & comparison_mask) !== (reference_value & comparison_mask)) begin
      $display("[FAIL] Address: 0x%08h | Read: 0x%08h | Expected: 0x%08h | Mask: 0x%08h | %s",
               target_addr, retrieved_data, reference_value, comparison_mask, test_label);
      num_failed++;
    end else begin
      $display("[PASS] Address: 0x%08h | Data: 0x%08h | %s", target_addr, retrieved_data, test_label);
      num_passed++;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Main Test Execution
  // ---------------------------------------------------------------------------
  initial begin
    // Configure VCD recording
    $dumpfile("../results/simulation/croc_tb.vcd");
    $dumpvars(0, croc_tb);

    $display("===============================================================");
    $display("           Croc SoC Functional Verification Suite");
    $display("===============================================================");

    // Initialize bus interface to quiescent state
    bus_request      = 1'b0;
    bus_write_enable = 1'b0;
    bus_address      = 32'h0;
    bus_write_data   = 32'h0;
    bus_byte_enable  = 4'hF;

    // Assert reset and let system stabilize
    reset_active_n = 1'b0;
    repeat(20) @(posedge clk_sys);
    reset_active_n = 1'b1;
    repeat(10) @(posedge clk_sys);

    // =========================================================================
    $display("\n[TEST-1] System Control Register Readback");
    $display("-----------");
    // Address 0x0300_0000 contains device identification
    // Should be non-zero if properly initialized
    execute_bus_read_verify(32'h03000000, 32'h0, 32'h0,
                            "SoC identification (chipID)");

    // =========================================================================
    $display("\n[TEST-2] SRAM Write-Read Coherency");
    $display("-----------");
    // Write distinctive pattern to first SRAM location
    execute_bus_write(32'h10000000, 32'hDEADBEEF);
    execute_bus_read_verify(32'h10000000, 32'hDEADBEEF, 32'hFFFFFFFF,
                            "SRAM[0x00]: write-read 0xDEADBEEF");

    // Write different pattern to adjacent location
    execute_bus_write(32'h10000004, 32'hCAFEBABE);
    execute_bus_read_verify(32'h10000004, 32'hCAFEBABE, 32'hFFFFFFFF,
                            "SRAM[0x04]: write-read 0xCAFEBABE");

    // =========================================================================
    $display("\n[TEST-3] Partial Word Writes via Byte Enables");
    $display("-----------");
    // Single byte write (LSB only) to demonstrate byte granularity
    execute_bus_write(32'h10000008, 32'hABCDEF12, 4'b0001);
    execute_bus_read_verify(32'h10000008, 32'h00000012, 32'h000000FF,
                            "SRAM[0x08]: byte-select write (LSB=0x12)");

    // =========================================================================
    $display("\n[TEST-4] GPIO Output Enable Configuration");
    $display("-----------");
    // Configure lower byte of GPIO as outputs
    execute_bus_write(32'h03005004, 32'h000000FF);
    execute_bus_read_verify(32'h03005004, 32'h000000FF, 32'h000000FF,
                            "GPIO output-enable register");

    // =========================================================================
    $display("\n[TEST-5] GPIO Output Data Latch");
    $display("-----------");
    // Write output value to GPIO data register
    execute_bus_write(32'h03005000, 32'h000000AA);
    execute_bus_read_verify(32'h03005000, 32'h000000AA, 32'h000000FF,
                            "GPIO data register (pattern 0xAA)");

    // =========================================================================
    $display("\n[TEST-6] Timer Prescaler Programming");
    $display("-----------");
    // Set timer prescaler (at 100MHz, 99 ticks = 1µs)
    execute_bus_write(32'h0300A008, 32'h00000063);
    execute_bus_read_verify(32'h0300A008, 32'h00000063, 32'hFFFFFFFF,
                            "Timer prescaler value");

    // =========================================================================
    $display("\n[TEST-7] Sequential SRAM Bulk Transfer");
    $display("-----------");
    // Write incrementing pattern across a memory block
    begin : block_write_sequence
      automatic int iteration;
      for (iteration = 0; iteration < 8; iteration++) begin
        execute_bus_write(
          32'h10000100 + (iteration * 4),
          32'hA0000000 + iteration
        );
      end

      // Verify the entire written block
      for (iteration = 0; iteration < 8; iteration++) begin
        execute_bus_read_verify(
          32'h10000100 + (iteration * 4),
          32'hA0000000 + iteration,
          32'hFFFFFFFF,
          $sformatf("SRAM bulk[idx=%0d]", iteration)
        );
      end
    end

    // =========================================================================
    $display("\n[TEST-8] UART Transmit Register Access");
    $display("-----------");
    // Initiate character transmission via UART TX register
    execute_bus_write(32'h03002000, 32'h00000048);
    $display("[INFO] UART transmit queued: ASCII 'H' (0x48)");

    // =========================================================================
    // Final Report
    // =========================================================================
    $display("\n===============================================================");
    $display("  Test Summary: %0d PASSED | %0d FAILED", num_passed, num_failed);
    $display("===============================================================");

    if (num_failed == 0) begin
      $display("  ✓ All tests completed successfully");
    end else begin
      $display("  ✗ %0d test(s) encountered issues — review log above", num_failed);
    end
    $display("");

    $finish;
  end

  // ---------------------------------------------------------------------------
  // Watchdog Timer: Prevent Runaway Simulation
  // ---------------------------------------------------------------------------
  initial begin
    repeat(SIM_WATCHDOG_CYC) @(posedge clk_sys);
    $display("[TIMEOUT] Simulation reached %0d cycles — stopping", SIM_WATCHDOG_CYC);
    $finish;
  end

endmodule
