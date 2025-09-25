`timescale 1ns/1ps

module top_tb();
  logic       clk, reset;
  logic [3:0] Row;                // from DUT
  logic [3:0] Col;                // driven by TB
  logic [6:0] Seg;
  logic       En1, En2;

  logic [7:0] Errors;
  logic [7:0] Cur = 8'b0;

  // expected/observed
  logic [3:0] ExpL, ExpR;
  logic [3:0] ObsL, ObsR;
  bit         SeenL, SeenR;
  logic [3:0] K;

  // press model
  bit         press_active;
  logic [1:0] press_row, press_col;

  // DUT
  top dut(Row, Col, Seg, En1, En2);

  // reset (local use only)
  initial begin
    Errors = 0;
    reset  = 1; #22;
    reset  = 0;
  end

  // TB clock (independent of HSOSC in DUT)
  always begin
    clk=1; #5;
    clk=0; #5;
  end

  // keypad model: pull a column LOW only when its row is active
  always @* begin
    Col = 4'b1111;
    if (press_active) begin
      logic [1:0] act_row;
      case (Row)
        4'b1110: act_row = 2'd0;
        4'b1101: act_row = 2'd1;
        4'b1011: act_row = 2'd2;
        4'b0111: act_row = 2'd3;
        default: act_row = 2'd0;
      endcase
      if (act_row == press_row) Col[press_col] = 1'b0;
    end
  end

  // key sequence and helpers (layout matches DUT map)
  logic [3:0] key_seq [0:15] = '{
    4'h1,4'h2,4'h3,4'hA,
    4'h4,4'h5,4'h6,4'hB,
    4'h7,4'h8,4'h9,4'hC,
    4'hE,4'h0,4'hF,4'hD
  };

  function automatic void hex_to_rc(input logic [3:0] h, output logic [1:0] r, output logic [1:0] c);
    case (h)
      4'h1: begin r=2'd0; c=2'd0; end 4'h2: begin r=2'd0; c=2'd1; end
      4'h3: begin r=2'd0; c=2'd2; end 4'hA: begin r=2'd0; c=2'd3; end
      4'h4: begin r=2'd1; c=2'd0; end 4'h5: begin r=2'd1; c=2'd1; end
      4'h6: begin r=2'd1; c=2'd2; end 4'hB: begin r=2'd1; c=2'd3; end
      4'h7: begin r=2'd2; c=2'd0; end 4'h8: begin r=2'd2; c=2'd1; end
      4'h9: begin r=2'd2; c=2'd2; end 4'hC: begin r=2'd2; c=2'd3; end
      4'hE: begin r=2'd3; c=2'd0; end 4'h0: begin r=2'd3; c=2'd1; end
      4'hF: begin r=2'd3; c=2'd2; end 4'hD: begin r=2'd3; c=2'd3; end
      default: begin r=2'd0; c=2'd0; end
    endcase
  endfunction

  function automatic logic [3:0] seg_to_hex(input logic [6:0] seg);
    case (seg)
      7'b0000001: seg_to_hex = 4'h0;
      7'b1001111: seg_to_hex = 4'h1;
      7'b0010010: seg_to_hex = 4'h2;
      7'b0000110: seg_to_hex = 4'h3;
      7'b1001100: seg_to_hex = 4'h4;
      7'b0100100: seg_to_hex = 4'h5;
      7'b0100000: seg_to_hex = 4'h6;
      7'b0001111: seg_to_hex = 4'h7;
      7'b0000000: seg_to_hex = 4'h8;
      7'b0001100: seg_to_hex = 4'h9;
      7'b0001000: seg_to_hex = 4'hA;
      7'b1100000: seg_to_hex = 4'hB;
      7'b0110001: seg_to_hex = 4'hC;
      7'b1000010: seg_to_hex = 4'hD;
      7'b0110000: seg_to_hex = 4'hE;
      7'b0111000: seg_to_hex = 4'hF;
      default:     seg_to_hex = 4'hX;
    endcase
  endfunction

  // drive next key on posedge
  typedef enum logic [1:0] {IDLE, PRESS, WAITREL, NEXT} phase_t;
  phase_t phase = IDLE;
  integer wait_ctr = 0;
  localparam int MAX_WAIT = 4_000_000;   // ~40 ms at this TB clock
  localparam int REL_WAIT = 500_000;     // ~5 ms release gap

  always @(posedge clk) begin
    #1;
    case (phase)
      IDLE: begin
        if (~reset) begin
          K = key_seq[Cur[3:0]];
          hex_to_rc(K, press_row, press_col);
          ExpL   = ExpR;
          ExpR   = K;
          SeenL  = 0; SeenR = 0;
          wait_ctr = 0;
          press_active = 1;
          phase = PRESS;
        end
      end
      PRESS: begin
        wait_ctr = wait_ctr + 1;
        if ((SeenL && SeenR) && (ObsL==ExpL) && (ObsR==ExpR)) begin
          press_active = 0;
          wait_ctr = 0;
          phase = WAITREL;
        end else if (wait_ctr > MAX_WAIT) begin
          press_active = 0;
          Errors = Errors + 1;
          $display("ERROR: key %h → got L=%h R=%h (exp L=%h R=%h)",
                   ExpR, ObsL, ObsR, ExpL, ExpR);
          wait_ctr = 0;
          phase = WAITREL;
        end
      end
      WAITREL: begin
        wait_ctr = wait_ctr + 1;
        if (wait_ctr > REL_WAIT) phase = NEXT;
      end
      NEXT: begin
        Cur = Cur + 1;
        if (Cur === 8'b00010000) begin
          $display("16 tests completed with %0d errors", Errors);
          $stop;
        end
        phase = IDLE;
      end
    endcase
  end

  // sample display on negedge, like your original checker timing
  always @(negedge clk) begin
    if (~reset) begin
      if (En1) begin ObsL = seg_to_hex(Seg); SeenL = 1; end
      if (En2) begin ObsR = seg_to_hex(Seg); SeenR = 1; end
    end
  end
endmodule
