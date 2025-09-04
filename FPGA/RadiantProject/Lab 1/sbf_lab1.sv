/*------------------------------------------------------------------------------
 * Lab 1 – FPGA and MCU Setup and Testing
 * Source: FPGA modules (SevenSeg, BlinkDiv, led_logic, sbf_lab1)
 * Author: Santiago Burgos-Fallon  <burgos.fallon@gmail.com>
 * Date:   2025-09-04
 *
 * Description:
 *   FPGA-side design for Lab 1. Includes:
 *     - SevenSeg: combinational hex→7-segment decoder for common-anode display
 *                 (seg[6:0] active-LOW; seg[0]=A .. seg[6]=G).
 *     - BlinkDiv: parameterized clock divider producing ~2.4 Hz tick from 48 MHz.
 *     - led_logic: LED patterns per lab truth tables; supports active-low polarity.
 *     - sbf_lab1: top-level tying HSOSC, POR, BlinkDiv, led_logic, SevenSeg.
 *   Notes:
 *     - Uses Lattice iCE40 HSOSC primitive (enabled and powered up).
 *     - Common-anode display: logic 0 turns a segment ON.
 *----------------------------------------------------------------------------*/
`timescale 1ns/1ps


module SevenSeg(
	input  logic [3:0] s,
	output logic [6:0] seg
	);
	//start all off then set selected segments on
		function automatic logic [6:0] ca_set(
			input bit a, b, c, d, e , f, g
		);
			logic [6:0] r = 7'h7F; // all off (111_1111)
			if (a) r[0] = 1'b0;
			if (b) r[1] = 1'b0;
			if (c) r[2] = 1'b0;
			if (d) r[3] = 1'b0;
			if (e) r[4] = 1'b0;
			if (f) r[5] = 1'b0;
			if (g) r[6] = 1'b0;
			return r;
		endfunction
		
	    always_comb begin
			unique case (s)
				4'h0: seg = ca_set(1,1,1,1,1,1,0);         // 0
				4'h1: seg = ca_set(0,1,1,0,0,0,0);         // 1 (b,c)
				4'h2: seg = ca_set(1,1,0,1,1,0,1);         // 2 (a,b,d,e,g)
				4'h3: seg = ca_set(1,1,1,1,0,0,1);         // 3 (a,b,c,d,g)
				4'h4: seg = ca_set(0,1,1,0,0,1,1);         // 4 (b,c,f,g)
				4'h5: seg = ca_set(1,0,1,1,0,1,1);         // 5 (a,c,d,f,g)
				4'h6: seg = ca_set(1,0,1,1,1,1,1);         // 6 (a,c,d,e,f,g)
				4'h7: seg = ca_set(1,1,1,0,0,0,0);         // 7 (a,b,c)
				4'h8: seg = ca_set(1,1,1,1,1,1,1);         // 8 (all)
				4'h9: seg = ca_set(1,1,1,1,0,1,1);         // 9 (a,b,c,d,f,g)
				4'hA: seg = ca_set(1,1,1,0,1,1,1);         // A (a,b,c,e,f,g)
				4'hB: seg = ca_set(0,0,1,1,1,1,1);         // b (c,d,e,f,g) 
				4'hC: seg = ca_set(1,0,0,1,1,1,0);         // C (a,d,e,f)
				4'hD: seg = ca_set(0,1,1,1,1,0,1);         // d (b,c,d,e,g)
				4'hE: seg = ca_set(1,0,0,1,1,1,1);         // E (a,d,e,f,g)
				4'hF: seg = ca_set(1,0,0,0,1,1,1);         // F (a,e,f,g)
            default: seg = 7'h7F;                      	   // blank
        endcase
    end
endmodule
			
module BlinkDiv #(
    parameter int unsigned TOGGLE_COUNT = 10_000_000 - 1  // 48e6 / (2*2.4) - 1
) (
    input  logic clk,
	input  logic rst_n,
    output logic tick   // 2.4 Hz square wave
);
    logic [23:0] cnt = '0;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cnt  <= '0;
            tick <= 1'b0;
        end else if (cnt == TOGGLE_COUNT) begin
            cnt  <= '0;
            tick <= ~tick;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end
endmodule

module led_logic #(
    parameter bit LED_ACTIVE_LOW = 0
) (
    input  logic [3:0] s,
    input  logic       blink_2p4hz,
    output logic [2:0] led
);
logic led0_raw, led1_raw;
    logic [2:0] raw;

    always_comb begin
        // truth tables
        led0_raw = s[1] ^ s[0];   // led[0]: ON when S1 != S0
        led1_raw = s[3] & s[2];   // led[1]: ON when S3 & S2
        raw      = {blink_2p4hz, led1_raw, led0_raw};

        // polarity control
        led = (LED_ACTIVE_LOW) ? ~raw : raw;
    end
endmodule


module sbf_lab1(
    input  logic [3:0] s,          // DIP switches
    output logic [2:0] led,        // set LED_ACTIVE_LOW=1 inside led_logic if needed
    output logic [6:0] seg         // common-anode, seg[0]=A..seg[6]=G (active-low)
);
	logic clk;
  
   // Internal high-speed oscillator
   HSOSC #(.CLKHF_DIV(2'b00)) 
         hf_osc (.CLKHFPU(1'b1), .CLKHFEN(1'b1), .CLKHF(clk));
		 
    // power on reset
    logic [15:0] por_cnt = '0;
    logic        rst_n   = 1'b0;
    always_ff @(posedge clk) begin
        if (por_cnt != 16'hFFFF) begin
            por_cnt <= por_cnt + 16'd1;
            rst_n   <= 1'b0;
        end else begin
            rst_n   <= 1'b1;
        end
    end

    // 2.4 Hz blink from 48 MHz clk 
    logic blink_2p4;
    // 48e6 / (2 * 2.4) = 10,000,000 -> toggle every 10,000,000 cycles
    BlinkDiv #(.TOGGLE_COUNT(10_000_000 - 1)) u_div (
        .clk   (clk),
        .rst_n (rst_n),
        .tick  (blink_2p4)
    );

    // LEDs 
    led_logic #(.LED_ACTIVE_LOW(0)) u_leds (
        .s           (s),
        .blink_2p4hz (blink_2p4),
        .led         (led)
    );

    // --- 7-seg hex (common-anode, active-low) ---
    SevenSeg u_7seg (
        .s   (s),
        .seg (seg)
    );
endmodule