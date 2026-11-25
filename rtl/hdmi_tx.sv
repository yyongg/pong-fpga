// hdmi_tx.sv -- DVI/HDMI video output (no audio).
//
// Each 8-bit colour is TMDS-encoded into a 10-bit symbol, then shifted out
// serially at 10x the pixel rate (clk_5x, both edges). Blue also carries
// hsync/vsync during blanking. A fourth lane sends the pixel clock.
module hdmi_tx (
  input  logic        clk_pix,
  input  logic        clk_5x,
  input  logic        rst,
  input  logic [23:0] rgb,
  input  logic        de, hsync, vsync,
  output logic        clk_p, clk_n,
  output logic [2:0]  d_p, d_n
);

  logic [9:0] lane [4];   // 0 = blue, 1 = green, 2 = red, 3 = clock
  logic [3:0] p, n;

  tmds_encoder enc_b (.clk(clk_pix), .data(rgb[7:0]),   .ctrl({vsync, hsync}), .de, .q(lane[0]));
  tmds_encoder enc_g (.clk(clk_pix), .data(rgb[15:8]),  .ctrl(2'b00),          .de, .q(lane[1]));
  tmds_encoder enc_r (.clk(clk_pix), .data(rgb[23:16]), .ctrl(2'b00),          .de, .q(lane[2]));
  assign lane[3] = 10'b00000_11111;

  // 10:1 serializer per lane: two OSERDESE2 in master/slave (one does 8 bits max)
  for (genvar i = 0; i < 4; i++) begin : g_lane
    logic serial, shift1, shift2;

    OSERDESE2 #(.DATA_RATE_OQ("DDR"), .DATA_RATE_TQ("SDR"), .DATA_WIDTH(10),
                .SERDES_MODE("MASTER"), .TRISTATE_WIDTH(1)) master (
      .OQ(serial), .CLK(clk_5x), .CLKDIV(clk_pix), .RST(rst), .OCE(1'b1),
      .D1(lane[i][0]), .D2(lane[i][1]), .D3(lane[i][2]), .D4(lane[i][3]),
      .D5(lane[i][4]), .D6(lane[i][5]), .D7(lane[i][6]), .D8(lane[i][7]),
      .SHIFTIN1(shift1), .SHIFTIN2(shift2),
      .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0), .TCE(1'b0), .TBYTEIN(1'b0));

    OSERDESE2 #(.DATA_RATE_OQ("DDR"), .DATA_RATE_TQ("SDR"), .DATA_WIDTH(10),
                .SERDES_MODE("SLAVE"), .TRISTATE_WIDTH(1)) slave (
      .SHIFTOUT1(shift1), .SHIFTOUT2(shift2),
      .CLK(clk_5x), .CLKDIV(clk_pix), .RST(rst), .OCE(1'b1),
      .D1(1'b0), .D2(1'b0), .D3(lane[i][8]), .D4(lane[i][9]),
      .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0),
      .SHIFTIN1(1'b0), .SHIFTIN2(1'b0),
      .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0), .TCE(1'b0), .TBYTEIN(1'b0));

    OBUFDS obuf (.I(serial), .O(p[i]), .OB(n[i]));
  end

  assign d_p   = p[2:0];
  assign d_n   = n[2:0];
  assign clk_p = p[3];
  assign clk_n = n[3];

endmodule


// tmds_encoder -- DVI 1.0 8b/10b TMDS encoding for one colour channel.
//   1. XOR/XNOR the bits together to minimise transitions (9 bits, qm)
//   2. Optionally invert to keep the count of 1s and 0s balanced over time
module tmds_encoder (
  input  logic       clk,
  input  logic [7:0] data,
  input  logic [1:0] ctrl,      // sent during blanking (de = 0)
  input  logic       de,
  output logic [9:0] q
);

  logic [8:0]        qm;
  logic [3:0]        ones_d, ones_qm;
  logic signed [5:0] disp;              // (#1s - #0s) in qm[7:0]
  logic signed [5:0] bias = '0;         // running (#1s - #0s) sent so far

  always_comb begin
    ones_d = $countones(data);
    qm[0]  = data[0];
    if (ones_d > 4 || (ones_d == 4 && !data[0])) begin
      for (int i = 1; i < 8; i++) qm[i] = qm[i-1] ~^ data[i];
      qm[8] = 1'b0;
    end else begin
      for (int i = 1; i < 8; i++) qm[i] = qm[i-1] ^ data[i];
      qm[8] = 1'b1;
    end
    ones_qm = $countones(qm[7:0]);
    disp    = $signed({1'b0, ones_qm, 1'b0}) - 6'sd8;
  end

  always_ff @(posedge clk) begin
    if (!de) begin
      bias <= '0;
      case (ctrl)
        2'b00: q <= 10'b1101010100;
        2'b01: q <= 10'b0010101011;
        2'b10: q <= 10'b0101010100;
        2'b11: q <= 10'b1010101011;
      endcase
    end else if (bias == 0 || disp == 0) begin
      q    <= {~qm[8], qm[8], qm[8] ? qm[7:0] : ~qm[7:0]};
      bias <= qm[8] ? bias + disp : bias - disp;
    end else if ((bias > 0) == (disp > 0)) begin     // would grow the bias: invert
      q    <= {1'b1, qm[8], ~qm[7:0]};
      bias <= bias - disp + (qm[8] ? 6'sd2 : 6'sd0);
    end else begin
      q    <= {1'b0, qm[8], qm[7:0]};
      bias <= bias + disp - (qm[8] ? 6'sd0 : 6'sd2);
    end
  end

endmodule
