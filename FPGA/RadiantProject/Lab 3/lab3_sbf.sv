/*------------------------------------------------------------------------------
 * Lab 3 4by 4 Keypad Scanner + Dual Seven-Segment Display
 * Source: FPGA modules (SevenSeg, DMux, KeypadScan, Sync2)
 * Author: Santiago Burgos-Fallon  <burgos.fallon@gmail.com>
 * Date:   2025-09-16
 *
 * Description:
 *   Scans a 4by4 matrix keypad, debounces, and registers exactly one code per
 *   press while ignoring additional keys until release. Displays the last two 
 *   hexadecimal digits pressed (most recent on RIGHT) on a dual common-anode
 *   7-seg. seg[6:0] active-LOW; En* select digits.
 *   Uses iCE40 HSOSC @ 6 MHz.
 *----------------------------------------------------------------------------*/

module top(
  output logic [3:0] Row,
  input  logic [3:0] Col,
  output logic [6:0] Seg,
  output logic       En1, En2
);
  logic        Osc;
  logic        key_valid;
  logic [3:0]  key_code;
  logic [3:0]  D_left = 4'h0;
  logic [3:0]  D_right = 4'h0;
  logic [3:0]  s;

  HSOSC #(.CLKHF_DIV(2'b11)) hf_osc (.CLKHFPU(1'b1), .CLKHFEN(1'b1), .CLKHF(Osc));

  KeypadScan scan0 (Osc, Row, Col, key_valid, key_code);

  always_ff @(posedge Osc) begin
    if (key_valid) begin
      D_left  <= D_right;
      D_right <= key_code;
    end
  end

  DMux dm0 (Osc, D_left, D_right, s, En1, En2);
  SevenSeg disp0 (s, Seg);
endmodule


module SevenSeg(
  input  logic [3:0] S,
  output logic [6:0] Seg
);
  always_comb begin
    case (S)
      4'h0: Seg = 7'b0000001; 4'h1: Seg = 7'b1001111;
      4'h2: Seg = 7'b0010010; 4'h3: Seg = 7'b0000110;
      4'h4: Seg = 7'b1001100; 4'h5: Seg = 7'b0100100;
      4'h6: Seg = 7'b0100000; 4'h7: Seg = 7'b0001111;
      4'h8: Seg = 7'b0000000; 4'h9: Seg = 7'b0001100;
      4'hA: Seg = 7'b0001000; 4'hB: Seg = 7'b1100000;
      4'hC: Seg = 7'b0110001; 4'hD: Seg = 7'b1000010;
      4'hE: Seg = 7'b0110000; 4'hF: Seg = 7'b0111000;
      default: Seg = 7'b1111111;
    endcase
  end
endmodule


module DMux(
  input  logic       Osc,
  input  logic [3:0] Sw1, Sw2,
  output logic [3:0] s,
  output logic       En1, En2
);
  logic        DivClk = 1'b0;
  logic [15:0] counter = 16'd0;

  assign s   = DivClk ? Sw2 : Sw1;
  assign En1 = ~DivClk;
  assign En2 =  DivClk;

  always_ff @(posedge Osc) begin
    if (counter >= 16'd60000) begin
      counter <= 16'd0;
      DivClk  <= ~DivClk;
    end else begin
      counter <= counter + 16'd1;
    end
  end
endmodule


module KeypadScan(
  input  logic       clk,
  output logic [3:0] Row,
  input  logic [3:0] Col,
  output logic       key_valid,
  output logic [3:0] key_code
);
  // sync & scan/timebase
  logic [3:0]  col_s1   = 4'hF, col_sync = 4'hF;
  logic [12:0] scan_div = 13'd0;       // 6e6/2000 - 1 = 2999
  logic        scan_tick = 1'b0;
  logic [1:0]  row_idx   = 2'd0;

  // detect (current inputs)
  logic        col_hit;
  logic [1:0]  col_idx;
  logic [1:0]  act_row;                 // decode of Row pattern

  // debounce/hold
  logic [1:0]  state = 2'b00;           // 00 IDLE, 01 DEB, 10 HELD
  logic [1:0]  cand_row, cand_col;
  logic [2:0]  deb_cnt = 3'd0;

  // synchronizer
  always_ff @(posedge clk) begin
    col_s1   <= Col;
    col_sync <= col_s1;
  end

  // scan tick + row pointer
  always_ff @(posedge clk) begin
    if (scan_div == 13'd2999) begin
      scan_div  <= 13'd0;
      scan_tick <= 1'b1;
      row_idx   <= row_idx + 2'd1;
    end else begin
      scan_div  <= scan_div + 13'd1;
      scan_tick <= 1'b0;
    end
  end

  // Row drive: round-robin in IDLE, freeze candidate row in DEB/HELD
  always_comb begin
    case (state)
      2'b01, 2'b10: begin
        Row = 4'b1111; Row[cand_row] = 1'b0;
      end
      default: begin
        case (row_idx)
          2'd0: Row = 4'b1110;
          2'd1: Row = 4'b1101;
          2'd2: Row = 4'b1011;
          2'd3: Row = 4'b0111;
          default: Row = 4'b1111;
        endcase
      end
    endcase
  end

  // Decode which row is currently driven LOW (matches your testbench model)
  always_comb begin
    case (Row)
      4'b1110: act_row = 2'd0;
      4'b1101: act_row = 2'd1;
      4'b1011: act_row = 2'd2;
      4'b0111: act_row = 2'd3;
      default: act_row = row_idx; // safe fallback
    endcase
  end

  // First LOW column (priority)
  always_comb begin
    col_hit = 1'b0;
    col_idx = 2'd0;
    if (!col_sync[0]) begin col_hit = 1'b1; col_idx = 2'd0; end
    else if (!col_sync[1]) begin col_hit = 1'b1; col_idx = 2'd1; end
    else if (!col_sync[2]) begin col_hit = 1'b1; col_idx = 2'd2; end
    else if (!col_sync[3]) begin col_hit = 1'b1; col_idx = 2'd3; end
  end

  // Row/col hex map (same as before)
  function logic [3:0] map_hex(input logic [1:0] r, input logic [1:0] c);
    case ({r,c})
      4'b00_00: map_hex = 4'h1;  4'b00_01: map_hex = 4'h2;
      4'b00_10: map_hex = 4'h3;  4'b00_11: map_hex = 4'hA;
      4'b01_00: map_hex = 4'h4;  4'b01_01: map_hex = 4'h5;
      4'b01_10: map_hex = 4'h6;  4'b01_11: map_hex = 4'hB;
      4'b10_00: map_hex = 4'h7;  4'b10_01: map_hex = 4'h8;
      4'b10_10: map_hex = 4'h9;  4'b10_11: map_hex = 4'hC;
      4'b11_00: map_hex = 4'hE;  4'b11_01: map_hex = 4'h0;
      4'b11_10: map_hex = 4'hF;  4'b11_11: map_hex = 4'hD;
      default:  map_hex = 4'h0;
    endcase
  endfunction

  // SINGLE driver for key_valid + FSM
  always_ff @(posedge clk) begin
    key_valid <= 1'b0;

    case (state)
      2'b00: begin // IDLE: capture immediately when a column is low
        deb_cnt <= 3'd0;
        if (col_hit) begin
          cand_row <= act_row;           // align with actual driven row
          cand_col <= col_idx;
          key_code <= map_hex(act_row, col_idx);
          state    <= 2'b01;             // DEB
        end
      end

      2'b01: begin // DEB: row frozen, count stability on candidate column
        if (scan_tick) begin
          if (!col_sync[cand_col]) deb_cnt <= deb_cnt + 3'd1;
          else                      deb_cnt <= 3'd0;
          if (deb_cnt >= 3'd2) begin
            key_valid <= 1'b1;           // one pulse
            state     <= 2'b10;          // HELD
          end
        end
        // optional fast abort if fully released
        if (col_sync == 4'b1111) begin
          state   <= 2'b00;
          deb_cnt <= 3'd0;
        end
      end

      2'b10: begin // HELD: ignore others until ALL released
        if (col_sync == 4'b1111) state <= 2'b00;
      end
    endcase
  end
endmodule
