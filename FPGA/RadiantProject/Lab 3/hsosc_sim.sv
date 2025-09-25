// hsosc_sim.sv — bit-param version that matches 2'bxx usage in RTL
`timescale 1ns/1ps
module HSOSC #(
  parameter logic [1:0] CLKHF_DIV = 2'b00  // 00=48MHz, 01=24, 10=12, 11=6
)(
  input  wire CLKHFEN,
  input  wire CLKHFPU,
  output reg  CLKHF
);
  real half_ns;
  function void set_half();
    case (CLKHF_DIV)
      2'b00: half_ns = 10.4167; // 48 MHz
      2'b01: half_ns = 20.8333; // 24 MHz
      2'b10: half_ns = 41.6667; // 12 MHz
      2'b11: half_ns = 83.3333; //  6 MHz
      default: half_ns = 10.4167;
    endcase
  endfunction

  initial begin CLKHF = 1'b0; set_half(); end
  always begin
    if (CLKHFEN && CLKHFPU) #(half_ns) CLKHF = ~CLKHF;
    else begin CLKHF = 1'b0; #1; end
  end
endmodule
