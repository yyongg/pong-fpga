// pong_game.sv -- game logic and physics. Everything updates once per frame.
//
// - Paddles move PADDLE_SPEED px/frame and stop at the screen edges.
// - The ball bounces off the top/bottom edges and off paddles. Where it hits
//   the paddle sets its new vertical speed (edge hits = steeper angle).
// - Missing the ball gives the other player a point; the ball re-serves from
//   the centre after a short pause, towards the player who lost the point.
// - First to WIN_SCORE wins; after a pause any button starts a new game.
module pong_game #(
  parameter int SCREEN_W     = 640,
  parameter int SCREEN_H     = 480,
  parameter int PADDLE_W     = 10,
  parameter int PADDLE_H     = 64,
  parameter int PADDLE_L_X   = 24,
  parameter int PADDLE_R_X   = 606,
  parameter int PADDLE_SPEED = 6,
  parameter int BALL_SIZE    = 8,
  parameter int BALL_SPEED   = 4,
  parameter int WIN_SCORE    = 9,
  parameter int SERVE_DELAY  = 60     // frames
) (
  input  logic       clk,
  input  logic       rst,
  input  logic       tick,            // once per frame
  input  logic       l_up, l_down, r_up, r_down,
  output logic [9:0] lpad_y,          // top edge of each paddle
  output logic [9:0] rpad_y,
  output logic [9:0] ball_x,          // top-left corner of the ball
  output logic [9:0] ball_y,
  output logic [3:0] score_l,
  output logic [3:0] score_r
);

  localparam int L_FACE   = PADDLE_L_X + PADDLE_W;   // surface the ball hits
  localparam int R_FACE   = PADDLE_R_X;
  localparam int BALL_X0  = (SCREEN_W - BALL_SIZE) / 2;
  localparam int BALL_Y0  = (SCREEN_H - BALL_SIZE) / 2;
  localparam int PAD_Y0   = (SCREEN_H - PADDLE_H) / 2;
  localparam int PAD_YMAX = SCREEN_H - PADDLE_H;

  // Ball state in signed 12-bit so positions can go "off screen" for one step
  logic signed [11:0] bx, by, vx, vy;
  logic signed [11:0] nx, ny, nvx, nvy, lp, rp;
  logic        [5:0]  wait_cnt;       // serve / game-over pause
  logic               point_l, point_r, game_over, any_btn;

  assign ball_x    = bx[9:0];
  assign ball_y    = by[9:0];
  assign lp        = {2'b00, lpad_y};
  assign rp        = {2'b00, rpad_y};
  assign game_over = (score_l == WIN_SCORE) || (score_r == WIN_SCORE);
  assign any_btn   = l_up || l_down || r_up || r_down;

  function automatic logic [9:0] move_paddle(input logic [9:0] y, input logic up, down);
    if (up && !down)   return (y < PADDLE_SPEED)            ? 10'd0            : y - PADDLE_SPEED;
    if (down && !up)   return (y > PAD_YMAX - PADDLE_SPEED) ? 10'(PAD_YMAX)    : y + PADDLE_SPEED;
    return y;
  endfunction

  // Does a ball at row ball_y overlap a paddle whose top is pad_y?
  function automatic logic overlaps(input logic signed [11:0] ball_y, pad_y);
    return (ball_y + BALL_SIZE > pad_y) && (ball_y < pad_y + PADDLE_H);
  endfunction

  // New vertical speed from where the ball struck the paddle (-5..+4)
  function automatic logic signed [11:0] bounce_vy(input logic signed [11:0] ball_y, pad_y, old_vy);
    logic signed [11:0] d;
    d = (ball_y + BALL_SIZE / 2 - pad_y - PADDLE_H / 2) >>> 3;
    return (d == 0) ? old_vy : d;
  endfunction

  // ---------------- Next ball position -------------------------------------
  always_comb begin
    nx = bx + vx;   nvx = vx;
    ny = by + vy;   nvy = vy;
    point_l = 1'b0; point_r = 1'b0;

    // top / bottom edges
    if (ny < 0)                         begin ny = 0;                   nvy = -vy; end
    else if (ny > SCREEN_H - BALL_SIZE) begin ny = SCREEN_H - BALL_SIZE; nvy = -vy; end

    // Paddles: the ball crosses the paddle face this frame while overlapping
    // it. Checking the crossing (not just the position) means a fast ball can
    // never skip through a paddle.
    if (vx < 0 && bx >= L_FACE && nx < L_FACE && overlaps(ny, lp)) begin
      nx = L_FACE;                 nvx = -vx; nvy = bounce_vy(ny, lp, vy);
    end else if (vx > 0 && bx + BALL_SIZE <= R_FACE && nx + BALL_SIZE > R_FACE && overlaps(ny, rp)) begin
      nx = R_FACE - BALL_SIZE;     nvx = -vx; nvy = bounce_vy(ny, rp, vy);
    end else if (nx < 0) begin
      point_r = 1'b1;              // left player missed
    end else if (nx > SCREEN_W - BALL_SIZE) begin
      point_l = 1'b1;              // right player missed
    end
  end

  // ---------------- State update (once per frame) --------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      lpad_y   <= PAD_Y0;
      rpad_y   <= PAD_Y0;
      bx       <= BALL_X0;
      by       <= BALL_Y0;
      vx       <= BALL_SPEED;
      vy       <= 2;
      score_l  <= '0;
      score_r  <= '0;
      wait_cnt <= SERVE_DELAY;
    end else if (tick) begin
      lpad_y <= move_paddle(lpad_y, l_up, l_down);
      rpad_y <= move_paddle(rpad_y, r_up, r_down);

      if (wait_cnt != 0) begin
        wait_cnt <= wait_cnt - 1'b1;                    // ball parked
      end else if (game_over) begin
        if (any_btn) begin                              // new game
          score_l  <= '0;
          score_r  <= '0;
          wait_cnt <= SERVE_DELAY;
        end
      end else if (point_l || point_r) begin
        if (point_l) score_l <= score_l + 1'b1;
        else         score_r <= score_r + 1'b1;
        bx       <= BALL_X0;
        by       <= BALL_Y0;
        vx       <= point_l ? BALL_SPEED : -BALL_SPEED; // serve to the loser
        vy       <= (vy > 0) ? -2 : 2;
        wait_cnt <= SERVE_DELAY;
      end else begin
        bx <= nx;  by <= ny;  vx <= nvx;  vy <= nvy;
      end
    end
  end

endmodule
