// pong_top.sv -- Pong for the PYNQ-Z2, 640x480 @ 60 Hz over HDMI
//
//   sysclk 125 MHz -> MMCM -> clk_pix (25.2 MHz) + clk_5x (126 MHz, serializer)
//
//   btn -> debounce -> pong_game -> pong_renderer -> hdmi_tx -> HDMI OUT
//                          ^              ^
//                          +- video_sync -+   (frame_tick / x, y, syncs)
//
// Controls: BTN3/BTN2 = left paddle up/down, BTN1/BTN0 = right paddle up/down
module pong_top (
  input  logic       sysclk,
  input  logic [3:0] btn,
  output logic       hdmi_tx_clk_p,
  output logic       hdmi_tx_clk_n,
  output logic [2:0] hdmi_tx_d_p,
  output logic [2:0] hdmi_tx_d_n
);

  // ---------------- Clocks: 125 MHz * 16.125 / 2 = 1007.8 MHz VCO ----------
  logic clk_pix, clk_5x, pix_unbuf, x5_unbuf, clk_fb, locked;

  MMCME2_BASE #(
    .CLKIN1_PERIOD   (8.0),
    .DIVCLK_DIVIDE   (2),
    .CLKFBOUT_MULT_F (16.125),
    .CLKOUT0_DIVIDE_F(40.0),    // 25.2 MHz pixel clock
    .CLKOUT1_DIVIDE  (8)        // 126 MHz = 5x pixel clock (DDR -> 10 bits/pixel)
  ) mmcm (
    .CLKIN1(sysclk), .CLKFBIN(clk_fb), .CLKFBOUT(clk_fb),
    .CLKOUT0(pix_unbuf), .CLKOUT1(x5_unbuf),
    .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0)
  );

  BUFG bufg_pix (.I(pix_unbuf), .O(clk_pix));
  BUFG bufg_5x  (.I(x5_unbuf),  .O(clk_5x));

  // ---------------- Reset: held until the MMCM locks ----------------------
  logic [3:0] rst_sr;
  logic       rst;

  always_ff @(posedge clk_pix or negedge locked)
    if (!locked) rst_sr <= '1;
    else         rst_sr <= {rst_sr[2:0], 1'b0};

  assign rst = rst_sr[3];

  // ---------------- Design ------------------------------------------------
  logic [3:0] btn_db;
  logic [9:0] x, y, lpad_y, rpad_y, ball_x, ball_y;
  logic [3:0] score_l, score_r;
  logic       de, hsync, vsync, frame_tick;
  logic [23:0] rgb;
  logic       rgb_de, rgb_hsync, rgb_vsync;

  debounce #(.N(4)) u_debounce (
    .clk(clk_pix), .in(btn), .out(btn_db)
  );

  video_sync u_sync (
    .clk(clk_pix), .rst, .x, .y, .de, .hsync, .vsync, .frame_tick
  );

  pong_game u_game (
    .clk(clk_pix), .rst, .tick(frame_tick),
    .l_up(btn_db[3]), .l_down(btn_db[2]), .r_up(btn_db[1]), .r_down(btn_db[0]),
    .lpad_y, .rpad_y, .ball_x, .ball_y, .score_l, .score_r
  );

  pong_renderer u_render (
    .clk(clk_pix), .x, .y, .de, .hsync, .vsync,
    .lpad_y, .rpad_y, .ball_x, .ball_y, .score_l, .score_r,
    .rgb, .de_o(rgb_de), .hsync_o(rgb_hsync), .vsync_o(rgb_vsync)
  );

  hdmi_tx u_hdmi (
    .clk_pix, .clk_5x, .rst,
    .rgb, .de(rgb_de), .hsync(rgb_hsync), .vsync(rgb_vsync),
    .clk_p(hdmi_tx_clk_p), .clk_n(hdmi_tx_clk_n),
    .d_p(hdmi_tx_d_p), .d_n(hdmi_tx_d_n)
  );

endmodule
