`timescale 1ns/1ps
// tb_tmds_encoder.sv -- checks the TMDS 8b/10b encoder against the DVI 1.0 rules.
//
//  - blanking (de = 0) sends the four control tokens
//  - every data symbol decodes back to the input byte (reference decoder below)
//  - the running DC balance (#1s - #0s sent) stays within +/-10
module tb_tmds_encoder;

  logic       clk = 0;
  logic [7:0] data = '0;
  logic [1:0] ctrl = '0;
  logic       de   = 0;
  logic [9:0] q;

  tmds_encoder dut (.*);

  always #5 clk = ~clk;

  int errors = 0;
  `define CHECK(cond, msg) if (cond) ; else begin errors++; if (errors <= 20) $error msg; end

  localparam logic [9:0] CTRL_TOKEN [4] = '{10'b1101010100, 10'b0010101011,
                                            10'b0101010100, 10'b1010101011};

  // Reference TMDS decoder (what a monitor does)
  function automatic logic [7:0] tmds_decode(input logic [9:0] s);
    logic [7:0] d, o;
    d    = s[9] ? ~s[7:0] : s[7:0];
    o[0] = d[0];
    for (int i = 1; i < 8; i++) o[i] = s[8] ? (d[i] ^ d[i-1]) : ~(d[i] ^ d[i-1]);
    return o;
  endfunction

  int disparity = 0;     // running (#1s - #0s) of all symbols since blanking
  int max_disp  = 0;

  // Send one symbol and check what comes out one clock later
  task automatic send(input logic de_i, input logic [7:0] d, input logic [1:0] c);
    @(negedge clk);
    de = de_i; data = d; ctrl = c;
    @(posedge clk); #1;
    if (!de_i) begin
      `CHECK(q == CTRL_TOKEN[c], ("ctrl %b: got %b, expected %b", c, q, CTRL_TOKEN[c]))
      disparity = 0;
    end else begin
      `CHECK(tmds_decode(q) == d, ("data %h: encoded %b decodes to %h", d, q, tmds_decode(q)))
      disparity += 2 * $countones(q) - 10;
      if (disparity > max_disp)  max_disp = disparity;
      if (-disparity > max_disp) max_disp = -disparity;
      `CHECK(disparity >= -10 && disparity <= 10, ("DC balance drifted to %0d after data %h", disparity, d))
    end
  endtask

  initial begin
    // Control tokens
    for (int c = 0; c < 4; c++) repeat (3) send(0, $urandom, c);

    // Every byte value, twice (different starting disparity the second time)
    for (int rep = 0; rep < 2; rep++)
      for (int d = 0; d < 256; d++) send(1, d, 0);

    // Long runs of worst-case bytes
    repeat (500) send(1, 8'h00, 0);
    repeat (500) send(1, 8'hFF, 0);
    repeat (500) send(1, 8'h55, 0);
    repeat (500) send(1, 8'h10, 0);

    // Random data with random blanking gaps, like a real video line
    for (int i = 0; i < 20000; i++) begin
      if ($urandom_range(0, 99) == 0) repeat ($urandom_range(1, 20)) send(0, $urandom, $urandom);
      send(1, $urandom, 0);
    end

    $display("largest DC imbalance seen: %0d", max_disp);
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d error(s)", errors);
    $finish;
  end

endmodule
