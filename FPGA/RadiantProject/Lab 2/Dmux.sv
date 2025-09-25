/*------------------------------------------------------------------------------
 * Lab 2 – Double Seven Segment LED
 * Source: FPGA modules (SevenSeg,Dmux,Top)
 * Author: Santiago Burgos-Fallon  <burgos.fallon@gmail.com>
 * Date:   2025-09-11
 *
 * Description:
 *   FPGA-side design for Lab 2. Includes:
 *     - SevenSeg: combinational hex→7-segment decoder for common-anode display
 *                 (seg[6:0] active-LOW; seg[0]=A .. seg[6]=a).
 *     - Dmux: Selects enable and clock counting
 *     - top: top-level tying HSOSC, Dmux, SevenSeg.
 *   Notes:
 *     - Uses Lattice iCE40 HSOSC primitive (enabled and powered up).
 *     - Common-anode display: logic 0 turns a segment ON.
 *----------------------------------------------------------------------------*/

module DMux(
	input  logic       Osc,
	input  logic [3:0] Sw1, Sw2,
	output logic [3:0] s,
	output logic       En1, En2
);
	logic DivClk;
	logic [22:0] counter = 0;

	// Choose input to SegDisp decoder
	assign s = DivClk ? Sw1 : Sw2;
	
	// Assign Enable bits
	assign En1 = ~DivClk;
	assign En2 =  DivClk;
	
   // Clock Divider 6MHz to 50Hz	
	always_ff @(posedge Osc) begin
		counter <= counter + 1;
		
		if (counter >= 23'd60000) begin
			DivClk  = ~DivClk;
			counter  <= 23'b0;
		end
	end
	
endmodule