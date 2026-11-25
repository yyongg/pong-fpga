`timescale 1ns/1ps
// tb_pong_game.sv -- self-checking test of the game logic and physics.
//
// The game only advances on `tick`, so the bench pulses tick directly (one
// "frame" = two clocks) instead of running real video timing. SERVE_DELAY is
// shortened to keep the test fast.
//
//   1. reset state            5. rally: two computer players, ball never lost,
//   2. serve pause               paddle bounces and angles checked every hit
//   3. paddle movement/limits 6. right player scores
//   4. left player scores     7. game over at 9 points and restart
module tb_pong_game;

  localparam int SERVE   = 3;
  localparam int BALL    = 8,   PAD_W  = 10, PAD_H = 64;
  localparam int L_PAD_X = 24,  R_PAD_X = 606;
  localparam int L_FACE  = 34,  R_FACE  = 606;
  localparam int BALL_X0 = 316, BALL_Y0 = 236;
  localparam int PAD_Y0  = 208, PAD_YMAX = 416, BALL_YMAX = 472;

  logic       clk = 0, rst = 1, tick = 0;
  logic       l_up = 0, l_down = 0, r_up = 0, r_down = 0;
  logic [9:0] lpad_y, rpad_y, ball_x, ball_y;
  logic [3:0] score_l, score_r;

  pong_game #(.SERVE_DELAY(SERVE)) dut (.*);

  always #5 clk = ~clk;

  int errors = 0;
  `define CHECK(cond, msg) if (cond) ; else begin errors++; if (errors <= 20) $error msg; end

  // Game state after every frame of the tests named by trace_tag goes to
  // game.csv, for the animation made by sim/make_media.py
  int    trace_fd;
  string trace_tag = "";
  initial begin
    trace_fd = $fopen("game.csv", "w");
    $fwrite(trace_fd, "test,ball_x,ball_y,lpad_y,rpad_y,score_l,score_r\n");
  end

  // ---------------- Helpers -------------------------------------------------
  task automatic frame(input int n = 1);
    repeat (n) begin
      @(negedge clk) tick = 1;
      @(negedge clk) tick = 0;
      if (trace_tag != "")
        $fwrite(trace_fd, "%s,%0d,%0d,%0d,%0d,%0d,%0d\n", trace_tag,
                ball_x, ball_y, lpad_y, rpad_y, score_l, score_r);
    end
  endtask

  task automatic reset();
    {l_up, l_down, r_up, r_down} = '0;
    @(negedge clk) rst = 1;
    @(negedge clk) rst = 0;
  endtask

  task automatic expect_parked(input int n, input string what);
    repeat (n) begin
      frame();
      `CHECK(ball_x == BALL_X0 && ball_y == BALL_Y0, ("%s: ball at (%0d,%0d), should wait at the centre", what, ball_x, ball_y))
    end
  endtask

  function automatic bit rect_overlap(input int ax, ay, aw, ah, bx, by, bw, bh);
    return (ax < bx + bw) && (bx < ax + aw) && (ay < by + bh) && (by < ay + ah);
  endfunction

  // Always true, whatever the game is doing
  always @(negedge clk) if (!rst) begin
    `CHECK(ball_x <= 640 - BALL,  ("ball_x = %0d is off screen", ball_x))
    `CHECK(ball_y <= BALL_YMAX,   ("ball_y = %0d is off screen", ball_y))
    `CHECK(lpad_y <= PAD_YMAX,    ("lpad_y = %0d is off screen", lpad_y))
    `CHECK(rpad_y <= PAD_YMAX,    ("rpad_y = %0d is off screen", rpad_y))
    `CHECK(score_l <= 9 && score_r <= 9, ("score %0d:%0d is above 9", score_l, score_r))
  end

  // ---------------- Computer players ----------------------------------------
  // A player moves its paddle so the paddle centre follows ball centre + aim.
  int  aim_l = 0, aim_r = 0;
  bit  miss_l = 0;                       // left player aims to miss
  int  bounces_l, bounces_r, wall_hits;
  bit  vy_seen [int];

  function automatic logic [1:0] chase(input int pad_y, input int target);  // {up, down}
    int c = pad_y + PAD_H / 2;
    if (c > target + 3) return 2'b10;
    if (c < target - 3) return 2'b01;
    return 2'b00;
  endfunction

  // One frame of play. Checks every paddle bounce against the rules in
  // pong_game.sv: the ball leaves from the paddle face, and its new vertical
  // speed is (hit offset from paddle centre) / 8, unchanged if that is 0.
  task automatic play(input bit left_ai, input bit right_ai, input bit no_misses);
    int pby, pvx, pvy, plp, prp, ny, pad, d, exp_vy;

    if (left_ai) begin
      int a = miss_l ? ((ball_y < 240) ? 90 : -90) : aim_l;
      {l_up, l_down} = chase(lpad_y, ball_y + BALL / 2 + a);
    end
    if (right_ai) {r_up, r_down} = chase(rpad_y, ball_y + BALL / 2 + aim_r);

    pby = dut.by; pvx = dut.vx; pvy = dut.vy; plp = lpad_y; prp = rpad_y;
    frame();

    if (ball_y == 0 || ball_y == BALL_YMAX) wall_hits++;

    if ((dut.vx < 0) != (pvx < 0)) begin            // direction reversed = paddle hit
      pad    = (pvx < 0) ? plp : prp;
      ny     = pby + pvy;
      if (ny < 0) ny = 0; else if (ny > BALL_YMAX) ny = BALL_YMAX;
      d      = (ny + BALL / 2 - pad - PAD_H / 2) >>> 3;
      exp_vy = (d == 0) ? pvy : d;
      `CHECK(int'(ball_x) == ((pvx < 0) ? L_FACE : R_FACE - BALL),
             ("bounce: ball left the paddle at x = %0d", ball_x))
      `CHECK(int'(dut.vy) == exp_vy, ("bounce: vy = %0d, expected %0d (ball y %0d, paddle y %0d)", dut.vy, exp_vy, ny, pad))
      `CHECK(int'(dut.vx) == -pvx,   ("bounce: vx = %0d, expected %0d", dut.vx, -pvx))
      vy_seen[int'(dut.vy)] = 1;
      if (pvx < 0) begin bounces_l++; aim_r = $urandom_range(0, 56) - 28; end
      else         begin bounces_r++; aim_l = $urandom_range(0, 56) - 28; end
    end

    if (no_misses) begin
      `CHECK(!rect_overlap(ball_x, ball_y, BALL, BALL, L_PAD_X, lpad_y, PAD_W, PAD_H), ("ball inside left paddle"))
      `CHECK(!rect_overlap(ball_x, ball_y, BALL, BALL, R_PAD_X, rpad_y, PAD_W, PAD_H), ("ball inside right paddle"))
    end
  endtask

  // ---------------- Tests ---------------------------------------------------
  initial begin
    int n, prev;

    // 1. Reset state
    reset();
    `CHECK(lpad_y == PAD_Y0 && rpad_y == PAD_Y0, ("paddles after reset: %0d %0d", lpad_y, rpad_y))
    `CHECK(ball_x == BALL_X0 && ball_y == BALL_Y0, ("ball after reset: (%0d,%0d)", ball_x, ball_y))
    `CHECK(score_l == 0 && score_r == 0, ("score after reset: %0d:%0d", score_l, score_r))

    // Nothing happens without a tick
    l_up = 1; r_down = 1;
    repeat (20) @(negedge clk);
    `CHECK(lpad_y == PAD_Y0 && rpad_y == PAD_Y0, ("paddles moved without a tick"))
    l_up = 0; r_down = 0;

    // 2. Serve pause, then the ball moves (+4, +2) per frame
    expect_parked(SERVE, "serve");
    frame();
    `CHECK(ball_x == BALL_X0 + 4 && ball_y == BALL_Y0 + 2, ("first move: ball at (%0d,%0d)", ball_x, ball_y))

    // 3. Paddles
    reset();
    l_up = 1; frame(); l_up = 0;
    `CHECK(lpad_y == PAD_Y0 - 6, ("l_up: lpad_y = %0d, expected %0d", lpad_y, PAD_Y0 - 6))
    `CHECK(rpad_y == PAD_Y0,     ("l_up moved the right paddle"))
    l_up = 1; l_down = 1; frame(); l_up = 0; l_down = 0;
    `CHECK(lpad_y == PAD_Y0 - 6, ("up+down together should not move (lpad_y = %0d)", lpad_y))
    l_up = 1;
    for (int i = 0; i < 50; i++) begin
      prev = lpad_y; frame();
      `CHECK(lpad_y <= prev, ("left paddle moved down while going up (%0d -> %0d)", prev, lpad_y))
    end
    `CHECK(lpad_y == 0, ("left paddle stops at the top (lpad_y = %0d)", lpad_y))
    l_up = 0; l_down = 1; frame(100); l_down = 0;
    `CHECK(lpad_y == PAD_YMAX, ("left paddle stops at the bottom (lpad_y = %0d)", lpad_y))
    reset();
    r_down = 1; frame(); r_down = 0;
    `CHECK(rpad_y == PAD_Y0 + 6, ("r_down: rpad_y = %0d, expected %0d", rpad_y, PAD_Y0 + 6))
    `CHECK(lpad_y == PAD_Y0,     ("r_down moved the left paddle"))
    r_up = 1;   frame(100); r_up = 0;
    `CHECK(rpad_y == 0, ("right paddle stops at the top (rpad_y = %0d)", rpad_y))
    r_down = 1; frame(100); r_down = 0;
    `CHECK(rpad_y == PAD_YMAX, ("right paddle stops at the bottom (rpad_y = %0d)", rpad_y))

    // 4. Nobody plays: the ball goes past the right paddle, left scores,
    //    and the next serve goes to the right (the player who lost the point)
    reset();
    n = 0;
    while (score_l == 0 && score_r == 0 && n < 300) begin frame(); n++; end
    `CHECK(score_l == 1 && score_r == 0, ("right miss: score %0d:%0d after %0d frames, expected 1:0", score_l, score_r, n))
    `CHECK(ball_x == BALL_X0 && ball_y == BALL_Y0, ("after a point the ball returns to the centre"))
    expect_parked(SERVE, "serve after point");
    frame();
    `CHECK(ball_x == BALL_X0 + 4, ("serve after left's point should go right (ball_x = %0d)", ball_x))

    trace_tag = "rally";
    // 5. Rally between two computer players: nobody should ever miss
    reset();
    bounces_l = 0; bounces_r = 0; wall_hits = 0; vy_seen.delete();
    aim_l = 0; aim_r = 0; miss_l = 0;
    repeat (4000) play(1, 1, 1);
    $display("rally: %0d left hits, %0d right hits, %0d wall hits, %0d different vy values",
             bounces_l, bounces_r, wall_hits, vy_seen.num());
    `CHECK(score_l == 0 && score_r == 0, ("rally: someone missed (score %0d:%0d)", score_l, score_r))
    `CHECK(bounces_l >= 10 && bounces_r >= 10, ("rally: too few paddle hits (%0d, %0d)", bounces_l, bounces_r))
    `CHECK(wall_hits >= 1, ("rally: ball never bounced off the top/bottom"))
    `CHECK(vy_seen.num() >= 4, ("rally: paddle angle never changed (%0d vy values)", vy_seen.num()))

    trace_tag = "miss";
    // 6. Left player misses on purpose: right scores, serve goes left
    reset();
    miss_l = 1; aim_r = 0;
    n = 0;
    while (score_l == 0 && score_r == 0 && n < 2000) begin play(1, 1, 0); n++; end
    {l_up, l_down, r_up, r_down} = '0;
    `CHECK(score_l == 0 && score_r == 1, ("left miss: score %0d:%0d after %0d frames, expected 0:1", score_l, score_r, n))
    expect_parked(SERVE, "serve after point");
    frame();
    `CHECK(ball_x == BALL_X0 - 4, ("serve after right's point should go left (ball_x = %0d)", ball_x))
    miss_l = 0;

    trace_tag = "gameover";
    // 7. Game over: left wins 9:0, the game freezes, a button restarts it
    reset();
    n = 0;
    while (score_l < 9 && n < 3000) begin frame(); n++; end
    `CHECK(score_l == 9 && score_r == 0, ("game over: score %0d:%0d, expected 9:0", score_l, score_r))
    r_up = 1; frame(); r_up = 0;                 // pressed during the pause: ignored
    `CHECK(score_l == 9, ("button during the end-of-game pause restarted the game"))
    for (int i = 0; i < 200; i++) begin
      frame();
      `CHECK(score_l == 9 && score_r == 0, ("game over: score changed to %0d:%0d", score_l, score_r))
      `CHECK(ball_x == BALL_X0 && ball_y == BALL_Y0, ("game over: ball moved to (%0d,%0d)", ball_x, ball_y))
    end
    l_down = 1; frame(); l_down = 0;             // any button: new game
    `CHECK(score_l == 0 && score_r == 0, ("restart: score %0d:%0d, expected 0:0", score_l, score_r))
    expect_parked(SERVE, "serve after restart");
    frame();
    `CHECK(ball_x != BALL_X0, ("restart: ball did not get served"))

    trace_tag = "";

    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d error(s)", errors);
    $finish;
  end

endmodule
