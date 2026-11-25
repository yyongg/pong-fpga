`timescale 1ns/1ps
// tb_pong_renderer.sv -- checks the pixel colours and the 1-clock pipeline.
//
// Probes the edges of the ball, both paddles, the net and every score digit,
// then renders one whole frame to frame.ppm so you can look at it.
module tb_pong_renderer;

  logic        clk = 0;
  logic [9:0]  x = '0, y = '0;
  logic        de = 0, hsync = 1, vsync = 1;
  logic [9:0]  lpad_y = 100, rpad_y = 300, ball_x = 200, ball_y = 150;
  logic [3:0]  score_l = 3, score_r = 7;
  logic [23:0] rgb;
  logic        de_o, hsync_o, vsync_o;

  pong_renderer dut (.*);

  always #5 clk = ~clk;

  int errors = 0;
  `define CHECK(cond, msg) if (cond) ; else begin errors++; if (errors <= 20) $error msg; end

  localparam logic [23:0] W = 24'hFFFFFF, G = 24'h606060, B = 24'h000000;

  // 3x5 font, '#' = lit. Each cell is drawn 8x8 pixels.
  string FONT [10][5] = '{
    '{"###", "#.#", "#.#", "#.#", "###"},   // 0
    '{".#.", "##.", ".#.", ".#.", "###"},   // 1
    '{"###", "..#", "###", "#..", "###"},   // 2
    '{"###", "..#", "###", "..#", "###"},   // 3
    '{"#.#", "#.#", "###", "..#", "..#"},   // 4
    '{"###", "#..", "###", "..#", "###"},   // 5
    '{"###", "#..", "###", "#.#", "###"},   // 6
    '{"###", "..#", "..#", "..#", "..#"},   // 7
    '{"###", "#.#", "###", "#.#", "###"},   // 8
    '{"###", "#.#", "###", "..#", "###"}    // 9
  };

  // Show pixel (px, py) to the renderer and return its colour one clock later
  task automatic probe(input int px, input int py, input logic pde, output logic [23:0] c);
    @(negedge clk);
    x = px; y = py; de = pde;
    @(posedge clk); #1;
    c = rgb;
  endtask

  task automatic expect_px(input int px, input int py, input logic [23:0] want, input string what);
    logic [23:0] c;
    probe(px, py, 1, c);
    `CHECK(c == want, ("%s: pixel (%0d,%0d) is %h, expected %h", what, px, py, c, want))
  endtask

  // Check all 15 cells of a digit at (ox, oy), at two opposite corners of each cell
  task automatic expect_digit(input int d, input int ox, input int oy);
    for (int r = 0; r < 5; r++)
      for (int c = 0; c < 3; c++) begin
        logic [23:0] want = (FONT[d][r][c] == "#") ? W : B;
        expect_px(ox + 8 * c,     oy + 8 * r,     want, $sformatf("digit %0d", d));
        expect_px(ox + 8 * c + 7, oy + 8 * r + 7, want, $sformatf("digit %0d", d));
      end
  endtask

  initial begin
    logic [23:0] c;
    int fd;

    // Ball: 8x8 at (200,150)
    expect_px(200, 150, W, "ball top-left");
    expect_px(207, 157, W, "ball bottom-right");
    expect_px(199, 150, B, "left of ball");
    expect_px(208, 150, B, "right of ball");
    expect_px(200, 149, B, "above ball");
    expect_px(200, 158, B, "below ball");

    // Paddles: 10x64 at x = 24 and x = 606
    expect_px( 24, 100, W, "left paddle top-left");
    expect_px( 33, 163, W, "left paddle bottom-right");
    expect_px( 23, 120, B, "left of left paddle");
    expect_px( 34, 120, B, "right of left paddle");
    expect_px( 24,  99, B, "above left paddle");
    expect_px( 24, 164, B, "below left paddle");
    expect_px(606, 300, W, "right paddle top-left");
    expect_px(615, 363, W, "right paddle bottom-right");
    expect_px(605, 320, B, "left of right paddle");
    expect_px(616, 320, B, "right of right paddle");
    expect_px(606, 299, B, "above right paddle");
    expect_px(606, 364, B, "below right paddle");

    // Net: x = 318..321, 16-pixel dashes (on where y bit 4 is set)
    expect_px(318,  16, G, "net dash");
    expect_px(321,  31, G, "net dash");
    expect_px(320, 464, G, "net dash");
    expect_px(318,  15, B, "net gap");
    expect_px(318,  32, B, "net gap");
    expect_px(317,  20, B, "left of net");
    expect_px(322,  20, B, "right of net");

    // Score digits: left at (256,24), right at (360,24), 24x40 pixels
    for (int d = 0; d < 10; d++) begin
      score_l = d; score_r = 9 - d;
      expect_digit(d,     256, 24);
      expect_digit(9 - d, 360, 24);
    end
    score_l = 8; score_r = 8;                   // all edge cells lit
    expect_px(255, 30, B, "left of left digit");
    expect_px(280, 30, B, "right of left digit");
    expect_px(256, 23, B, "above left digit");
    expect_px(256, 64, B, "below left digit");
    expect_px(359, 30, B, "left of right digit");
    expect_px(384, 30, B, "right of right digit");

    // White objects are drawn over the grey net
    ball_x = 316; ball_y = 16;
    expect_px(318, 16, W, "ball over net");
    ball_x = 200; ball_y = 150;

    // Blanking is always black, even where an object is
    probe(200, 150, 0, c);
    `CHECK(c == B, ("pixel during blanking is %h, expected black", c))

    // de/hsync/vsync come out one clock later, lined up with rgb
    for (int i = 0; i < 200; i++) begin
      logic [2:0] s, held;
      @(negedge clk);
      held = {de_o, hsync_o, vsync_o};
      s    = $urandom;
      {de, hsync, vsync} = s;
      #1;
      `CHECK({de_o, hsync_o, vsync_o} == held, ("sync outputs changed before the clock edge"))
      @(posedge clk); #1;
      `CHECK({de_o, hsync_o, vsync_o} == s, ("sync outputs not delayed by exactly one clock"))
    end

    // Render a whole frame to frame.ppm (open it with GIMP, IrfanView, etc.)
    lpad_y = 120; rpad_y = 260; ball_x = 420; ball_y = 300; score_l = 3; score_r = 7;
    fd = $fopen("frame.ppm", "w");
    $fwrite(fd, "P3\n640 480\n255\n");
    for (int py = 0; py < 480; py++)
      for (int px = 0; px < 640; px++) begin
        probe(px, py, 1, c);
        $fwrite(fd, "%0d %0d %0d\n", c[23:16], c[15:8], c[7:0]);
      end
    $fclose(fd);
    $display("wrote frame.ppm");

    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d error(s)", errors);
    $finish;
  end

endmodule
