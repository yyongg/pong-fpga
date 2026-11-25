`timescale 1ns/1ps
// tb_video_sync.sv -- checks the 640x480 @ 60 Hz timing over two full frames.
//
// Every clock, x/y/de/hsync/vsync/frame_tick are compared with the VESA
// numbers (800 x 525 total, hsync 656..751, vsync lines 490..491). Per-frame
// totals (visible pixels, sync pulse widths, ticks) are counted as well.
module tb_video_sync;

  logic       clk = 0, rst = 1;
  logic [9:0] x, y;
  logic       de, hsync, vsync, frame_tick;

  video_sync dut (.*);

  always #5 clk = ~clk;

  int errors = 0;
  `define CHECK(cond, msg) if (cond) ; else begin errors++; if (errors <= 20) $error msg; end

  initial begin
    int de_cnt, hs_cnt, vs_cnt, tick_cnt;
    int line_fd, frame_fd;               // traces for the timing plot (sim/make_media.py)

    line_fd  = $fopen("video_line.csv", "w");     // every pixel of line 0
    frame_fd = $fopen("video_frame.csv", "w");    // every line of frame 0, sampled at x = 0
    $fwrite(line_fd,  "x,de,hsync\n");
    $fwrite(frame_fd, "y,de,vsync,frame_tick\n");

    repeat (3) @(negedge clk);
    rst = 0;                             // x = y = 0 now; counting starts next edge

    for (int f = 0; f < 2; f++) begin
      de_cnt = 0; hs_cnt = 0; vs_cnt = 0; tick_cnt = 0;
      for (int l = 0; l < 525; l++) begin
        for (int p = 0; p < 800; p++) begin
          `CHECK(x == p && y == l, ("frame %0d: position is (%0d,%0d), expected (%0d,%0d)", f, x, y, p, l))
          `CHECK(de         == (p < 640 && l < 480),           ("de wrong at (%0d,%0d)", p, l))
          `CHECK(hsync      == !(p >= 656 && p < 752),         ("hsync wrong at (%0d,%0d)", p, l))
          `CHECK(vsync      == !(l >= 490 && l < 492),         ("vsync wrong at (%0d,%0d)", p, l))
          `CHECK(frame_tick == (p == 0 && l == 480),           ("frame_tick wrong at (%0d,%0d)", p, l))
          de_cnt   += de;
          hs_cnt   += !hsync;
          vs_cnt   += !vsync;
          tick_cnt += frame_tick;
          if (f == 0 && l == 0) $fwrite(line_fd, "%0d,%0d,%0d\n", x, de, hsync);
          if (f == 0 && p == 0) $fwrite(frame_fd, "%0d,%0d,%0d,%0d\n", y, de, vsync, frame_tick);
          @(negedge clk);
        end
      end
      `CHECK(de_cnt   == 640 * 480, ("frame %0d: %0d visible pixels, expected %0d", f, de_cnt, 640 * 480))
      `CHECK(hs_cnt   == 96 * 525,  ("frame %0d: %0d hsync-low clocks, expected %0d", f, hs_cnt, 96 * 525))
      `CHECK(vs_cnt   == 2 * 800,   ("frame %0d: %0d vsync-low clocks, expected %0d", f, vs_cnt, 2 * 800))
      `CHECK(tick_cnt == 1,         ("frame %0d: %0d frame_ticks, expected 1", f, tick_cnt))
    end

    // Reset puts the counters back to the top-left corner
    repeat (1234) @(negedge clk);
    rst = 1;
    @(negedge clk);
    `CHECK(x == 0 && y == 0, ("reset did not clear x/y (%0d,%0d)", x, y))

    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d error(s)", errors);
    $finish;
  end

endmodule
