/*------------------------------------------------------------------------------
 * Lab 1 – FPGA and MCU Setup and Testing
 * Source: Testbenches (tb_SevenSeg_tv, tb_led_logic_tv, tb_lab1_sbf_tv)
 * Author: Santiago Burgos-Fallon  <burgos.fallon@gmail.com>
 * Date:   2025-09-04
 *
 * Description:
 *   Self-checking testbenches that read .tv vector files to verify DUTs:
 *     - tb_SevenSeg_tv: validates SevenSeg against "sevenseg.tv".
 *     - tb_led_logic_tv: validates led_logic (active-high & active-low) using
 *                        "led_logic.tv".
 *     - tb_lab1_sbf_tv: validates top-level seg and led[1:0] (blink ignored)
 *                        using "lab1_sbf.tv".
 *   Conventions:
 *     - `timescale 1ns/1ps; seg active-LOW (seg[0]=A .. seg[6]=G).
 *     - PIPE_STAGES lets you align expectations if DUT outputs are registered.
 *----------------------------------------------------------------------------*/

`timescale 1ns/1ps
`default_nettype none

// SevenSeg via .tv
module tb_SevenSeg_tv;
  localparam int PIPE_STAGES = 0;  // set to 1 if SevenSeg is registered

  logic clk, reset;
  logic [3:0] s;
  logic [6:0] seg, exp_now, exp_q [0:PIPE_STAGES];

  // {s[3:0], seg[6:0]} with seg[0]=A .. seg[6]=G, active-LOW
  logic [10:0] testvectors [0:10000];
  int vectornum, errors;

  SevenSeg dut (.s(s), .seg(seg));

  // clock
  always begin clk = 1; #5; clk = 0; #5; end

  // init + load vectors
  initial begin
    vectornum = 0; errors = 0;
    reset = 1; #22; reset = 0;
  end
  initial $readmemb("sevenseg.tv", testvectors);

  // drive inputs on posedge (after a smidge)
  always @(posedge clk) if (!reset) begin
    #1;
    {s, exp_now} = testvectors[vectornum];

    // pipeline expected if DUT is registered
    exp_q[0] = exp_now;
    for (int k = 1; k <= PIPE_STAGES; k++) exp_q[k] = exp_q[k-1];
  end

  // check on negedge
  always @(negedge clk) if (!reset) begin
    if (testvectors[vectornum] === 11'bx) begin
      $display("%0d SevenSeg tests, %0d errors", vectornum, errors);
      $finish;
    end
    if (seg !== exp_q[PIPE_STAGES]) begin
      $display("SevenSeg ERR vec=%0d s=%b got=%b exp=%b",
               vectornum, s, seg, exp_q[PIPE_STAGES]);
      errors++;
    end
    vectornum++;
  end
endmodule


// led_logic via .tv 
module tb_led_logic_tv;
  localparam int PIPE_STAGES = 0;  // set to 1 if outputs are registered

  logic clk, reset;
  logic [3:0] s;
  logic       blink;
  logic [2:0] led, led_n, exp_now, exp_q [0:PIPE_STAGES];

  // {s[3:0], blink, led_exp[2:0]} for ACTIVE-HIGH LED DUT
  logic [7:0]  testvectors [0:10000];
  int vectornum, errors;

  // two instances: default (active-high) and active-low (should be ~exp)
  led_logic                 dut   (.s(s), .blink_2p4hz(blink), .led(led));
  led_logic #(.LED_ACTIVE_LOW(1)) dut_n (.s(s), .blink_2p4hz(blink), .led(led_n));

  always begin clk = 1; #5; clk = 0; #5; end

  initial begin
    vectornum = 0; errors = 0;
    reset = 1; #22; reset = 0;
  end
  initial $readmemb("led_logic.tv", testvectors);

  always @(posedge clk) if (!reset) begin
    #1;
    {s, blink, exp_now} = testvectors[vectornum];
    exp_q[0] = exp_now;
    for (int k = 1; k <= PIPE_STAGES; k++) exp_q[k] = exp_q[k-1];
  end

  always @(negedge clk) if (!reset) begin
    if (testvectors[vectornum] === 8'bx) begin
      $display("%0d led_logic tests, %0d errors", vectornum, errors);
      $finish;
    end
    if (led !== exp_q[PIPE_STAGES]) begin
      $display("led_logic ERR vec=%0d s=%b b=%0d got=%b exp=%b",
               vectornum, s, blink, led, exp_q[PIPE_STAGES]);
      errors++;
    end
    if (led_n !== ~exp_q[PIPE_STAGES]) begin
      $display("led_logic(active-low) ERR vec=%0d s=%b b=%0d got=%b exp=%b",
               vectornum, s, blink, led_n, ~exp_q[PIPE_STAGES]);
      errors++;
    end
    vectornum++;
  end
endmodule


// lab1_sbf via .tv (ignore blink bit)
module tb_lab1_sbf_tv;
  localparam int PIPE_STAGES = 0;  // set to 1 if outputs are registered

  logic clk, reset;
  logic [3:0] s;
  logic [6:0] seg, seg_exp_now, seg_exp_q [0:PIPE_STAGES];
  logic [2:0] led;
  logic [1:0] led01_exp_now, led01_exp_q [0:PIPE_STAGES];

  // {s[3:0], seg_exp[6:0], led01_exp[1:0]} ; seg active-LOW, seg[0]=A..[6]=G
  // led01_exp is {s3&s2, s1^s0}. We intentionally IGNORE led[2] (blink).
  logic [12:0] testvectors [0:10000];
  int vectornum, errors;

  sbf_lab1 dut (.s(s), .led(led), .seg(seg));

  always begin clk = 1; #5; clk = 0; #5; end

  initial begin
    vectornum = 0; errors = 0;
    reset = 1; #22; reset = 0;
  end
  initial $readmemb("lab1_sbf.tv", testvectors);

  always @(posedge clk) if (!reset) begin
    #1;
    {s, seg_exp_now, led01_exp_now} = testvectors[vectornum];

    seg_exp_q[0]   = seg_exp_now;
    led01_exp_q[0] = led01_exp_now;
    for (int k = 1; k <= PIPE_STAGES; k++) begin
      seg_exp_q[k]   = seg_exp_q[k-1];
      led01_exp_q[k] = led01_exp_q[k-1];
    end
  end

  always @(negedge clk) if (!reset) begin
    if (testvectors[vectornum] === 13'bx) begin
      $display("%0d lab1_sbf tests, %0d errors", vectornum, errors);
      $finish;
    end

    if (seg !== seg_exp_q[PIPE_STAGES]) begin
      $display("lab1_sbf SEG ERR vec=%0d s=%b got=%b exp=%b",
               vectornum, s, seg, seg_exp_q[PIPE_STAGES]);
      errors++;
    end
    if (led[1:0] !== led01_exp_q[PIPE_STAGES]) begin
      $display("lab1_sbf LED01 ERR vec=%0d s=%b got=%b%b exp=%b",
               vectornum, s, led[1], led[0], led01_exp_q[PIPE_STAGES]);
      errors++;
    end
    vectornum++;
  end
endmodule

`default_nettype wire
