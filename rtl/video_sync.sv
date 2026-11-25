// video_sync.sv -- 640x480 @ 60 Hz timing generator (800 x 525 total).
// frame_tick pulses at the start of vertical blanking; the game updates then,
// so nothing moves while a frame is being drawn.
module video_sync (
  input  logic       clk,
  input  logic       rst,
  output logic [9:0] x,
  output logic [9:0] y,
  output logic       de,          // inside the visible 640x480 area
  output logic       hsync,       // active low
  output logic       vsync,       // active low
  output logic       frame_tick
);

  localparam int H_ACTIVE = 640, H_FP = 16, H_SYNC = 96, H_TOTAL = 800;
  localparam int V_ACTIVE = 480, V_FP = 10, V_SYNC = 2,  V_TOTAL = 525;

  always_ff @(posedge clk) begin
    if (rst) begin
      x <= '0;
      y <= '0;
    end else if (x == H_TOTAL - 1) begin
      x <= '0;
      y <= (y == V_TOTAL - 1) ? '0 : y + 1'b1;
    end else begin
      x <= x + 1'b1;
    end
  end

  assign de         = (x < H_ACTIVE) && (y < V_ACTIVE);
  assign hsync      = !((x >= H_ACTIVE + H_FP) && (x < H_ACTIVE + H_FP + H_SYNC));
  assign vsync      = !((y >= V_ACTIVE + V_FP) && (y < V_ACTIVE + V_FP + V_SYNC));
  assign frame_tick = (x == 0) && (y == V_ACTIVE);

endmodule
