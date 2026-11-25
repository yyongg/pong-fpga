// debounce.sv -- 2-FF synchronizer + counter debounce for N buttons.
// An output only changes after its input has been stable for CYCLES clocks.
module debounce #(
  parameter int N      = 4,
  parameter int CYCLES = 250_000      // 10 ms at 25 MHz
) (
  input  logic         clk,
  input  logic [N-1:0] in,
  output logic [N-1:0] out
);

  for (genvar i = 0; i < N; i++) begin : g_btn
    (* ASYNC_REG = "TRUE" *) logic [1:0] sync = '0;
    logic [$clog2(CYCLES)-1:0] cnt = '0;
    logic                      state = 1'b0;

    always_ff @(posedge clk) begin
      sync <= {sync[0], in[i]};
      if (sync[1] == state)       cnt <= '0;
      else if (cnt == CYCLES - 1) begin state <= sync[1]; cnt <= '0; end
      else                        cnt <= cnt + 1'b1;
    end

    assign out[i] = state;
  end

endmodule
