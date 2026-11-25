`timescale 1ns/1ps
// tb_pong_top.sv -- whole design, Xilinx primitives included (MMCM, OSERDES).
//
// The bench acts as an HDMI receiver: it samples the serial TMDS pins, finds
// the 10-bit word boundary from the blanking control tokens, decodes each
// pixel, and checks
//   - the MMCM locks and the HDMI clock lane runs at 25.2 MHz
//   - every line is 640 data + 16 front porch + 96 hsync + 48 back porch
//   - the decoded pixels of the first LINES lines (score digits, net) are right
//
// Needs the UNISIM library and glbl (sim/run_sim.tcl handles that).
module tb_pong_top;

  localparam int LINES = 48;     // visible lines checked (1..LINES)

  logic       sysclk = 0;
  logic [3:0] btn    = '0;
  logic       hdmi_tx_clk_p, hdmi_tx_clk_n;
  logic [2:0] hdmi_tx_d_p, hdmi_tx_d_n;

  pong_top dut (.*);

  always #4 sysclk = ~sysclk;    // 125 MHz

  int errors = 0;
  `define CHECK(cond, msg) if (cond) ; else begin errors++; if (errors <= 20) $error msg; end

  // ---------------- TMDS helpers --------------------------------------------
  function automatic int ctrl_of(input logic [9:0] s);   // -1 = not a control token
    case (s)
      10'b1101010100: return 0;
      10'b0010101011: return 1;
      10'b0101010100: return 2;
      10'b1010101011: return 3;
      default:        return -1;
    endcase
  endfunction

  function automatic logic [7:0] tmds_decode(input logic [9:0] s);
    logic [7:0] d, o;
    d    = s[9] ? ~s[7:0] : s[7:0];
    o[0] = d[0];
    for (int i = 1; i < 8; i++) o[i] = s[8] ? (d[i] ^ d[i-1]) : ~(d[i] ^ d[i-1]);
    return o;
  endfunction

  // What the screen should show at power-up: score 0:0 and the net. (The
  // paddles start at y = 208 and the ball at y = 236, below the checked lines.)
  function automatic logic [23:0] expected_px(input int x, input int y);
    int ox, col, row;
    if (x >= 318 && x < 322 && y[4]) return 24'h606060;
    if (y < 24 || y >= 64)           return 24'h000000;
    if (x >= 256 && x < 280)         ox = 256;           // left score
    else if (x >= 360 && x < 384)    ox = 360;           // right score
    else                             return 24'h000000;
    col = (x - ox) / 8;
    row = (y - 24) / 8;
    return (col != 1 || row == 0 || row == 4) ? 24'hFFFFFF : 24'h000000;   // a "0"
  endfunction

  // ---------------- Serial receiver -----------------------------------------
  // One bit per clk_5x edge (DDR). Sample mid-bit, shift in LSB first.
  logic [9:0] sr   [3] = '{default: '0};
  logic [9:0] word [3];
  int         nbits = 0, phase = -1;
  int         run [10] = '{default: 0};
  event       word_ev;

  always @(dut.clk_5x) if (dut.rst === 1'b0) begin
    #2;
    for (int i = 0; i < 3; i++) begin
      sr[i] = {hdmi_tx_d_p[i], sr[i][9:1]};
      `CHECK(hdmi_tx_d_n[i] === ~hdmi_tx_d_p[i], ("lane %0d: d_n is not the inverse of d_p", i))
    end
    nbits++;
    if (phase < 0) begin                // word boundary = 8 control tokens in a row
      automatic int p = nbits % 10;
      run[p] = (ctrl_of(sr[0]) >= 0) ? run[p] + 1 : 0;
      if (run[p] == 8) phase = p;
    end else if (nbits % 10 == phase) begin
      word = sr;
      -> word_ev;
    end
  end

  // ---------------- Line decoder and checks ---------------------------------
  typedef enum {DATA, IDLE, SYNC, NONE} kind_t;

  initial begin : rx
    static kind_t kind, prev = NONE;
    static int    len = 0, xpos = 0, ln = 0, bad_px = 0;
    static bit    started = 0;                 // seen the start of an hsync pulse
    static kind_t before_idle = NONE;

    forever begin
      @(word_ev);
      if (ctrl_of(word[0]) >= 0) begin
        automatic int c = ctrl_of(word[0]);
        kind = c[0] ? IDLE : SYNC;      // blue lane carries {vsync, hsync}
        `CHECK(c[1] == 1'b1, ("vsync active on line %0d", ln))
        `CHECK(ctrl_of(word[1]) == 0 && ctrl_of(word[2]) == 0,
               ("line %0d: green/red lanes not sending control token 00 during blanking", ln))
      end else begin
        kind = DATA;
        `CHECK(ctrl_of(word[1]) < 0 && ctrl_of(word[2]) < 0, ("line %0d: lanes out of step", ln))
      end

      if (kind != prev) begin           // a run just ended: check its length
        if (started) case (prev)
          DATA: `CHECK(len == 640, ("line %0d: %0d visible pixels, expected 640", ln, len))
          SYNC: `CHECK(len == 96,  ("line %0d: hsync %0d pixels, expected 96", ln, len))
          IDLE: if (before_idle == DATA) `CHECK(len == 16, ("line %0d: front porch %0d, expected 16", ln, len))
                else                     `CHECK(len == 48, ("line %0d: back porch %0d, expected 48", ln, len))
          default: ;
        endcase
        if (kind == IDLE) before_idle = prev;
        if (kind == SYNC) begin
          if (started) ln++; else ln = 1;     // the first pulse seen follows line 0
          started = 1;
          if (ln > LINES) break;
        end
        if (kind == DATA) xpos = 0;
        prev = kind;
        len  = 0;
      end
      len++;

      if (kind == DATA && started) begin
        automatic logic [23:0] px = {tmds_decode(word[2]), tmds_decode(word[1]), tmds_decode(word[0])};
        automatic logic [23:0] want = expected_px(xpos, ln);
        if (px != want) begin
          bad_px++;
          `CHECK(0, ("pixel (%0d,%0d) decoded as %h, expected %h", xpos, ln, px, want))
        end
        xpos++;
      end
    end

    `CHECK(started, ("never saw an hsync pulse"))
    $display("checked lines 1..%0d: %0d wrong pixels", LINES, bad_px);
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d error(s)", errors);
    $finish;
  end

  // ---------------- Clocking checks -----------------------------------------
  initial begin : clocks
    realtime t0, period;
    fork
      wait (dut.locked === 1'b1);
      #200us;
    join_any
    disable fork;
    `CHECK(dut.locked === 1'b1, ("MMCM did not lock within 200 us"))
    $display("MMCM locked at %t", $realtime);

    wait (dut.rst === 1'b0);
    repeat (10) @(posedge hdmi_tx_clk_p);
    t0 = $realtime;
    repeat (100) @(posedge hdmi_tx_clk_p);
    period = ($realtime - t0) / 100;
    $display("HDMI clock lane period: %.3f ns", period);
    `CHECK(period > 39.6 && period < 39.8, ("HDMI clock period %.3f ns, expected ~39.69 ns (25.2 MHz)", period))
  end

  initial begin : watchdog
    #5ms;
    $error("timeout: only reached line %0d", rx.ln);
    $display("TEST FAILED: timeout");
    $finish;
  end

endmodule
