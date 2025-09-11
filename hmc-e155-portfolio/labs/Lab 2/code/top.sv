/*------------------------------------------------------------------------------
 * Lab 2 – Double Seven Segment LED
 * Source: FPGA modules (SevenSeg,Dmux,Top)
 * Author: Santiago Burgos-Fallon  <burgos.fallon@gmail.com>
 * Date:   2025-09-11
 *
 * Description:
 *   FPGA-side design for Lab 1. Includes:
 *     - SevenSeg: combinational hex→7-segment decoder for common-anode display
 *                 (seg[6:0] active-LOW; seg[0]=A .. seg[6]=a).
 *     - Dmux: Selects enable and clock counting
 *     - top: top-level tying HSOSC, Dmux, SevenSeg.
 *   Notes:
 *     - Uses Lattice iCE40 HSOSC primitive (enabled and powered up).
 *     - Common-anode display: logic 0 turns a segment ON.
 *----------------------------------------------------------------------------*/

module top(
	input  logic [3:0] Sw1, Sw2,
	output logic [6:0] Seg,
	output logic       En1, En2,
	output logic [4:0] Sum
	);

	logic [3:0]  s;
	logic        Osc;
	
	// Initialize clock at 6MHz
	HSOSC #(.CLKHF_DIV(2'b11)) 
	 hf_osc (.CLKHFPU(1'b1), .CLKHFEN(1'b1), .CLKHF(Osc));
	
	DMux DM(Osc, Sw1, Sw2, s, En1, En2);
	
	SevenSeg DispDecoder(s, Seg);
	
	//Assign Sum LEDs (active low so invert)
	assign Sum = ~(Sw1+Sw2);
	
endmodule
	
