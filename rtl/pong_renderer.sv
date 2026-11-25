// pong_renderer.sv -- decides the colour of each pixel as the screen is drawn.
// No frame buffer: every object is a simple "is (x, y) inside it?" test.
// Output is registered, so de/hsync/vsync are delayed one clock to match.
module pong_renderer #(
  parameter int PADDLE_W   = 10,
  parameter int PADDLE_H   = 64,
  parameter int PADDLE_L_X = 24,
  parameter int PADDLE_R_X = 606,
  parameter int BALL_SIZE  = 8
) (
  input  logic        clk,
  input  logic [9:0]  x, y,
  input  logic        de, hsync, vsync,
  input  logic [9:0]  lpad_y, rpad_y, ball_x, ball_y,
  input  logic [3:0]  score_l, score_r,
  output logic [23:0] rgb,
  output logic        de_o, hsync_o, vsync_o
);

  localparam logic [23:0] WHITE = 24'hFFFFFF, GREY = 24'h606060, BLACK = 24'h000000;

  // Is (x, y) on a 3x5-pixel-font digit drawn 8x larger at (ox, oy)?
  function automatic logic digit_on(input logic [3:0] d, input logic [9:0] x, y, input int ox, oy);
    logic [14:0] font;   // 5 rows of 3 pixels, top row in the MSBs
    int col, row;
    if (x < ox || x >= ox + 24 || y < oy || y >= oy + 40) return 1'b0;
    col = (x - ox) / 8;
    row = (y - oy) / 8;
    case (d)
      0: font = 15'b111_101_101_101_111;
      1: font = 15'b010_110_010_010_111;
      2: font = 15'b111_001_111_100_111;
      3: font = 15'b111_001_111_001_111;
      4: font = 15'b101_101_111_001_001;
      5: font = 15'b111_100_111_001_111;
      6: font = 15'b111_100_111_101_111;
      7: font = 15'b111_001_001_001_001;
      8: font = 15'b111_101_111_101_111;
      default: font = 15'b111_101_111_001_111;  // 9
    endcase
    return font[14 - (row * 3 + col)];
  endfunction

  logic ball, paddle, net, score;

  always_comb begin
    ball   = (x >= ball_x) && (x < ball_x + BALL_SIZE) && (y >= ball_y) && (y < ball_y + BALL_SIZE);
    paddle = ((x >= PADDLE_L_X) && (x < PADDLE_L_X + PADDLE_W) && (y >= lpad_y) && (y < lpad_y + PADDLE_H)) ||
             ((x >= PADDLE_R_X) && (x < PADDLE_R_X + PADDLE_W) && (y >= rpad_y) && (y < rpad_y + PADDLE_H));
    net    = (x >= 318) && (x < 322) && y[4];          // dashed centre line
    score  = digit_on(score_l, x, y, 256, 24) || digit_on(score_r, x, y, 360, 24);
  end

  always_ff @(posedge clk) begin
    if (!de)                     rgb <= BLACK;
    else if (ball || paddle || score) rgb <= WHITE;
    else if (net)                rgb <= GREY;
    else                         rgb <= BLACK;
    de_o    <= de;
    hsync_o <= hsync;
    vsync_o <= vsync;
  end

endmodule
