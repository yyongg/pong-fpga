<<<<<<< HEAD
# Pong on the PYNQ-Z2

This is a two-player Pong game in SystemVerilog. It outputs 640x480 @ 60 Hz video on the
board's HDMI OUT port.

```
             sysclk 125 MHz ──► MMCM ──► clk_pix 25.2 MHz / clk_5x 126 MHz
                                    │
 buttons ──► debounce ──► pong_game ──► pong_renderer ──► hdmi_tx ──► HDMI OUT
                              ▲               ▲
                              └── video_sync ─┘
```

| File | Role |
|------|------|
| `rtl/pong_top.sv`      | Top level: clock (MMCM), reset, wires the modules together |
| `rtl/debounce.sv`      | Synchronizes and debounces the buttons |
| `rtl/video_sync.sv`    | 640x480 timing: x/y counters, hsync/vsync, `frame_tick` |
| `rtl/pong_game.sv`     | Game logic and physics: paddles, ball, collisions, score |
| `rtl/pong_renderer.sv` | Pixel colour for each (x, y): ball, paddles, net, score digits |
| `rtl/hdmi_tx.sv`       | TMDS encoder and 10:1 serializers that drive the HDMI pins |

## How it works

- `video_sync` scans the screen pixel by pixel. `frame_tick` fires once per frame, when
  the visible area ends.
- `pong_game` updates once per `frame_tick`, so speeds are measured in pixels per frame.
  Nothing moves while a frame is being drawn, so there is no tearing.
- `pong_renderer` uses no frame buffer. For each pixel it checks whether (x, y) is inside
  the ball, a paddle, the net or a score digit.
- `hdmi_tx` converts each colour byte to a 10-bit TMDS symbol and sends the symbols serially
  at 10x the pixel rate.

## Controls

The left paddle uses BTN3 (up) and BTN2 (down). The right paddle uses BTN1 (up) and BTN0
(down). First to 9 points wins; after the game ends, press any button to start a new one.

## Build

```
vivado -mode batch -source build.tcl
```

To load the bitstream, set the JP1 jumper to JTAG. Then open Vivado Hardware Manager and
program `build/pong_top.bit`.
=======
# pong-fpga
Implementing Pong purely in hardware
>>>>>>> 516c294f8ea5df66ff59c59d8aa035f64d184563
