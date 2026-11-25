`timescale 1ns/1ps
// tb_debounce.sv -- checks the button synchronizer/debouncer.
// Uses CYCLES = 16 instead of 250k so the test runs in microseconds.
module tb_debounce;

  localparam int CYCLES = 16;

  logic       clk = 0;
  logic [1:0] in  = '0;
  logic [1:0] out;

  debounce #(.N(2), .CYCLES(CYCLES)) dut (.*);

  always #5 clk = ~clk;

  int errors = 0;
  `define CHECK(cond, msg) if (cond) ; else begin errors++; if (errors <= 20) $error msg; end

  // Clocks until out[ch] follows in[ch] (gives up after `limit`, returns -1)
  task automatic clocks_to_follow(input int ch, input int limit, output int n);
    n = -1;
    for (int i = 1; i <= limit; i++) begin
      @(posedge clk); #1;
      if (out[ch] == in[ch]) begin n = i; return; end
    end
  endtask

  // Run for n clocks; out must stay at `val` the whole time
  task automatic hold_out(input int n, input logic [1:0] val, input string what);
    repeat (n) begin
      @(posedge clk); #1;
      `CHECK(out == val, ("%s: out = %b, expected %b", what, out, val))
    end
  endtask

  initial begin
    int n;

    hold_out(5, 2'b00, "idle");

    // 1. Contact bounce: in[0] toggles every 3 clocks. Never stable long enough.
    for (int i = 0; i < 20; i++) begin
      @(posedge clk); #1 in[0] = ~in[0];
      hold_out(2, 2'b00, "bouncing");
    end
    in[0] = 0;
    hold_out(CYCLES + 5, 2'b00, "after bounce");

    // 2. Clean press: output follows after CYCLES clocks (+2 for the synchronizer)
    @(posedge clk); #1 in[0] = 1;
    clocks_to_follow(0, 3 * CYCLES, n);
    `CHECK(n >= CYCLES && n <= CYCLES + 3, ("press: out followed after %0d clocks, expected %0d..%0d", n, CYCLES, CYCLES + 3))
    `CHECK(out[1] == 0, ("press on btn0 leaked into btn1"))

    // 3. A short dropout while held is ignored
    hold_out(5, 2'b01, "held");
    in[0] = 0;
    hold_out(CYCLES - 4, 2'b01, "dropout");
    in[0] = 1;
    hold_out(CYCLES + 5, 2'b01, "after dropout");

    // 4. Release: same delay
    in[0] = 0;
    clocks_to_follow(0, 3 * CYCLES, n);
    `CHECK(n >= CYCLES && n <= CYCLES + 3, ("release: out followed after %0d clocks, expected %0d..%0d", n, CYCLES, CYCLES + 3))

    // 5. The second channel works on its own
    hold_out(5, 2'b00, "idle again");
    in[1] = 1;
    clocks_to_follow(1, 3 * CYCLES, n);
    `CHECK(n >= CYCLES && n <= CYCLES + 3, ("btn1 press: out followed after %0d clocks", n))
    `CHECK(out[0] == 0, ("press on btn1 leaked into btn0"))

    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d error(s)", errors);
    $finish;
  end

endmodule
