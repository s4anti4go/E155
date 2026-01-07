/////////////////////////////////////////////
// aes
//   Top level module with SPI interface and SPI core
/////////////////////////////////////////////

module aes(input  logic clk,
           input  logic sck, 
           input  logic sdi,
           output logic sdo,
           input  logic load,
           output logic done);
                    
    logic [127:0] key, plaintext, cyphertext;
            
    aes_spi spi(sck, sdi, sdo, done, key, plaintext, cyphertext);   
    aes_core core(clk, load, key, plaintext, done, cyphertext);
endmodule

/////////////////////////////////////////////
// aes_spi
//   SPI interface.  Shifts in key and plaintext
//   Captures ciphertext when done, then shifts it out
//   Tricky cases to properly change sdo on negedge clk
/////////////////////////////////////////////

module aes_spi(input  logic sck, 
               input  logic sdi,
               output logic sdo,
               input  logic done,
               output logic [127:0] key, plaintext,
               input  logic [127:0] cyphertext);

    logic         sdodelayed, wasdone;
    logic [127:0] cyphertextcaptured;
               
    // assert load
    // apply 256 sclks to shift in key and plaintext, starting with plaintext[127]
    // then deassert load, wait until done
    // then apply 128 sclks to shift out cyphertext, starting with cyphertext[127]
    // SPI mode is equivalent to cpol = 0, cpha = 0 since data is sampled on first edge and the first
    // edge is a rising edge (clock going from low in the idle state to high).
    always_ff @(posedge sck)
        if (!wasdone)  {cyphertextcaptured, plaintext, key} = {cyphertext, plaintext[126:0], key, sdi};
        else           {cyphertextcaptured, plaintext, key} = {cyphertextcaptured[126:0], plaintext, key, sdi}; 
    
    // sdo should change on the negative edge of sck
    always_ff @(negedge sck) begin
        wasdone = done;
        sdodelayed = cyphertextcaptured[126];
    end
    
    // when done is first asserted, shift out msb before clock edge
    assign sdo = (done & !wasdone) ? cyphertext[127] : sdodelayed;
endmodule

/////////////////////////////////////////////
// aes_core
//   top level AES encryption module
//   when load is asserted, takes the current key and plaintext
//   generates cyphertext and asserts done when complete 11 cycles later
// 
//   See FIPS-197 with Nk = 4, Nb = 4, Nr = 10
//
//   The key and message are 128-bit values packed into an array of 16 bytes as
//   shown below
//        [127:120] [95:88] [63:56] [31:24]     S0,0    S0,1    S0,2    S0,3
//        [119:112] [87:80] [55:48] [23:16]     S1,0    S1,1    S1,2    S1,3
//        [111:104] [79:72] [47:40] [15:8]      S2,0    S2,1    S2,2    S2,3
//        [103:96]  [71:64] [39:32] [7:0]       S3,0    S3,1    S3,2    S3,3
//
//   Equivalently, the values are packed into four words as given
//        [127:96]  [95:64] [63:32] [31:0]      w[0]    w[1]    w[2]    w[3]
/////////////////////////////////////////////

module aes_core(
    input  logic         clk,
    input  logic         load,
    input  logic [127:0] key,
    input  logic [127:0] plaintext,
    output logic         done,
    output logic [127:0] cyphertext
);

    // round/key/state
    logic [3:0]   round;            // 1..10
    logic [127:0] state_r;          // state after last ARK
    logic [127:0] rk_r;             // current round key
    logic [127:0] rk_next;          // next round key

    // pipeline regs around round datapath
    logic [127:0] y0_r, y1_r, y2_r, y3_r;

    // combinational wires
    logic [127:0] sb_out, sr_out, mc_out;
    logic [127:0] ark0_out, ark_in, ark_out;

    // helpers 
    sbx_bytes  u_sbx   (.a(y0_r), .clk(clk), .y(sb_out));          // 1-cycle via sbox_sync
    row_shift  u_rows  (.a(y1_r),           .y(sr_out));
    mixcolumns u_mix   (.a(y2_r),           .y(mc_out));
    rk_sched   u_sched (.key(rk_r), .round(round), .clk(clk), .roundKey(rk_next));
    ark_xor    u_ark0  (.a(y3_r),     .roundKey(rk_r),   .y(ark0_out));   // initial ARK
    ark_xor    u_ark1  (.a(ark_in),   .roundKey(rk_next), .y(ark_out));   // per-round ARK

    typedef enum logic [3:0] {
        IDLE,        // not used for reset; we just park here if needed
        INIT_ARK,    // state = plaintext ^ key
        R_PREP,      // feed state to SB; key schedule starts
        R_SB_WAIT,   // burn 1 cycle for sbox_sync
        R_SB_CAP,    // capture SB
        R_SR,        // capture SR
        R_MC,        // capture MC (rounds 1..9)
        R_ARK,       // ARK with rk_next; round++
        R_FINAL,     // final ARK (no MC) → ciphertext
        FINISH       // hold done until next load
    } st_t;

    st_t st, st_n;

    // next-state (purely from st)
    always_comb begin
        st_n = st;
        unique case (st)
            INIT_ARK:   st_n = R_PREP;
            R_PREP:     st_n = R_SB_WAIT;
            R_SB_WAIT:  st_n = R_SB_CAP;               // 1-cycle for sbox_sync
            R_SB_CAP:   st_n = R_SR;
            R_SR:       st_n = (round < 4'd10) ? R_MC : R_FINAL;
            R_MC:       st_n = R_ARK;
            R_ARK:      st_n = R_PREP;
            R_FINAL:    st_n = FINISH;
            FINISH:     st_n = FINISH;                 // new txn comes from load
            default:    st_n = INIT_ARK;
        endcase
    end

    // single driver for all regs; reset/init when load==1
    always_ff @(posedge clk) begin
        if (load) begin
            // synchronous "reset/start"
            done       <= 1'b0;
            cyphertext <= '0;
            // stage for initial ARK
            y3_r       <= plaintext;
            rk_r       <= key;
            round      <= 4'd1;
            state_r    <= '0;
            y0_r       <= '0;
            y1_r       <= '0;
            y2_r       <= '0;
            st         <= INIT_ARK;
        end else begin
            unique case (st)
            INIT_ARK: begin
                state_r <= ark0_out;                   // plaintext ^ key
            end
            R_PREP: begin
                y0_r <= state_r;                       // to SubBytes
            end
            R_SB_WAIT: begin
                // bubble for sbox_sync
            end
            R_SB_CAP: begin
                y1_r <= sb_out;                        // capture SB
            end
            R_SR: begin
                y2_r <= sr_out;                        // capture SR
            end
            R_MC: begin
                y3_r <= mc_out;                        // capture MC (1..9)
            end
            R_ARK: begin
                state_r <= ark_out;                    // ARK with rk_next
                rk_r    <= rk_next;
                round   <= round + 4'd1;               // becomes 2..10
            end
            R_FINAL: begin
                cyphertext <= ark_out;                 // final cipher
                rk_r       <= rk_next;
                done       <= 1'b1;
            end
            FINISH: begin
                // hold outputs until next load
            end
            endcase
            st <= st_n;
        end
    end

    // ARK input mux: MC path rounds 1..9, SR path in final
    assign ark_in = (st==R_FINAL) ? sr_out : y3_r;

endmodule

// ============================================================================
// sbx_bytes — SubBytes over 128b state 
// ============================================================================
module sbx_bytes(
    input  logic [127:0] a,
    input  logic         clk,
    output logic [127:0] y
);
  // row 0
  sbox_sync s00(a[127:120], clk, y[127:120]);
  sbox_sync s01(a[95:88]  , clk, y[95:88]);
  sbox_sync s02(a[63:56]  , clk, y[63:56]);
  sbox_sync s03(a[31:24]  , clk, y[31:24]);

  // row 1
  sbox_sync s10(a[119:112], clk, y[119:112]);
  sbox_sync s11(a[87:80]  , clk, y[87:80]);
  sbox_sync s12(a[55:48]  , clk, y[55:48]);
  sbox_sync s13(a[23:16]  , clk, y[23:16]);

  // row 2
  sbox_sync s20(a[111:104], clk, y[111:104]);
  sbox_sync s21(a[79:72]  , clk, y[79:72]);
  sbox_sync s22(a[47:40]  , clk, y[47:40]);
  sbox_sync s23(a[15:8]   , clk, y[15:8]);

  // row 3
  sbox_sync s30(a[103:96] , clk, y[103:96]);
  sbox_sync s31(a[71:64]  , clk, y[71:64]);
  sbox_sync s32(a[39:32]  , clk, y[39:32]);
  sbox_sync s33(a[7:0]    , clk, y[7:0]);
endmodule

// ============================================================================
// row_shift — ShiftRows
// ============================================================================
module row_shift(
    input  logic [127:0] a,
    output logic [127:0] y
);
  // row 0 (no shift)
  assign y[127:120] = a[127:120];
  assign y[95:88]   = a[95:88];
  assign y[63:56]   = a[63:56];
  assign y[31:24]   = a[31:24];

  // row 1 (left by 1)
  assign y[119:112] = a[87:80];
  assign y[87:80]   = a[55:48];
  assign y[55:48]   = a[23:16];
  assign y[23:16]   = a[119:112];

  // row 2 (left by 2)
  assign y[111:104] = a[47:40];
  assign y[79:72]   = a[15:8];
  assign y[47:40]   = a[111:104];
  assign y[15:8]    = a[79:72];

  // row 3 (left by 3)
  assign y[103:96]  = a[7:0];
  assign y[71:64]   = a[103:96];
  assign y[39:32]   = a[71:64];
  assign y[7:0]     = a[39:32];
endmodule

// ============================================================================
// rotw — rotate 32-bit word {b0,b1,b2,b3}->{b1,b2,b3,b0}
// ============================================================================
module rotw(
    input  logic [31:0] a,
    output logic [31:0] y
);
  assign y = {a[23:16], a[15:8], a[7:0], a[31:24]};
endmodule

// ============================================================================
// subw — SubWord using sbox_sync (1-cycle), 
// ============================================================================
module subw(
    input  logic [31:0] a,
    input  logic        clk,
    output logic [31:0] y
);
  logic [7:0] y0, y1, y2, y3;
  sbox_sync s0(a[31:24], clk, y0);
  sbox_sync s1(a[23:16], clk, y1);
  sbox_sync s2(a[15:8] , clk, y2);
  sbox_sync s3(a[7:0]  , clk, y3);
  assign y = {y0, y1, y2, y3};
endmodule

// ============================================================================
// rk_sched — AES-128 next round key (Nk=4).
// subw is 1-cycle; aes_core leaves a bubble so rk_next is ready in time.
// ============================================================================
module rk_sched(
    input  logic [127:0] key,      // current round key
    input  logic [3:0]   round,    // 1..10
    input  logic         clk,
    output logic [127:0] roundKey  // next round key
);
  logic [31:0] w0, w1, w2, w3;
  logic [31:0] t_rot, t_sub;
  logic [31:0] rcon_w;
  logic [7:0]  rc;

  assign {w0, w1, w2, w3} = key;

  always_comb begin
    unique case (round)
      4'd1:  rc = 8'h01;
      4'd2:  rc = 8'h02;
      4'd3:  rc = 8'h04;
      4'd4:  rc = 8'h08;
      4'd5:  rc = 8'h10;
      4'd6:  rc = 8'h20;
      4'd7:  rc = 8'h40;
      4'd8:  rc = 8'h80;
      4'd9:  rc = 8'h1B;
      4'd10: rc = 8'h36;
      default: rc = 8'h00;
    endcase
  end
  assign rcon_w = {rc, 24'h0};

  rotw  u_rot (.a(w3),         .y(t_rot));
  subw  u_sub (.a(t_rot), .clk(clk), .y(t_sub));

  logic [31:0] wn0, wn1, wn2, wn3;
  assign wn0 = w0 ^ t_sub ^ rcon_w;
  assign wn1 = w1 ^ wn0;
  assign wn2 = w2 ^ wn1;
  assign wn3 = w3 ^ wn2;

  assign roundKey = {wn0, wn1, wn2, wn3};
endmodule

// ============================================================================
// ark_xor — AddRoundKey
// ============================================================================
module ark_xor(
    input  logic [127:0] a,
    input  logic [127:0] roundKey,
    output logic [127:0] y
);
  assign y = a ^ roundKey;
endmodule

/////////////////////////////////////////////
// sbox
//   Infamous AES byte substitutions with magic numbers
//   Combinational version which is mapped to LUTs (logic cells)
//   Section 5.1.1, Figure 7
/////////////////////////////////////////////

module sbox(input  logic [7:0] a,
            output logic [7:0] y);
            
  // sbox implemented as a ROM
  // This module is combinational and will be inferred using LUTs (logic cells)
  logic [7:0] sbox[0:255];

  initial   $readmemh("sbox.txt", sbox);
  assign y = sbox[a];
endmodule

/////////////////////////////////////////////
// sbox
//   Infamous AES byte substitutions with magic numbers
//   Synchronous version which is mapped to embedded block RAMs (EBR)
//   Section 5.1.1, Figure 7
/////////////////////////////////////////////
module sbox_sync(
	input		logic [7:0] a,
	input	 	logic 			clk,
	output 	logic [7:0] y);
            
  // sbox implemented as a ROM
  // This module is synchronous and will be inferred using BRAMs (Block RAMs)
  logic [7:0] sbox [0:255];

  initial   $readmemh("sbox.txt", sbox);
	
	// Synchronous version
	always_ff @(posedge clk) begin
		y <= sbox[a];
	end
endmodule

/////////////////////////////////////////////
// mixcolumns
//   Even funkier action on columns
//   Section 5.1.3, Figure 9
//   Same operation performed on each of four columns
/////////////////////////////////////////////

module mixcolumns(input  logic [127:0] a,
                  output logic [127:0] y);

  mixcolumn mc0(a[127:96], y[127:96]);
  mixcolumn mc1(a[95:64],  y[95:64]);
  mixcolumn mc2(a[63:32],  y[63:32]);
  mixcolumn mc3(a[31:0],   y[31:0]);
endmodule

/////////////////////////////////////////////
// mixcolumn
//   Perform Galois field operations on bytes in a column
//   See EQ(4) from E. Ahmed et al, Lightweight Mix Columns Implementation for AES, AIC09
//   for this hardware implementation
/////////////////////////////////////////////

module mixcolumn(input  logic [31:0] a,
                 output logic [31:0] y);
                      
        logic [7:0] a0, a1, a2, a3, y0, y1, y2, y3, t0, t1, t2, t3, tmp;
        
        assign {a0, a1, a2, a3} = a;
        assign tmp = a0 ^ a1 ^ a2 ^ a3;
    
        galoismult gm0(a0^a1, t0);
        galoismult gm1(a1^a2, t1);
        galoismult gm2(a2^a3, t2);
        galoismult gm3(a3^a0, t3);
        
        assign y0 = a0 ^ tmp ^ t0;
        assign y1 = a1 ^ tmp ^ t1;
        assign y2 = a2 ^ tmp ^ t2;
        assign y3 = a3 ^ tmp ^ t3;
        assign y = {y0, y1, y2, y3};    
endmodule

/////////////////////////////////////////////
// galoismult
//   Multiply by x in GF(2^8) is a left shift
//   followed by an XOR if the result overflows
//   Uses irreducible polynomial x^8+x^4+x^3+x+1 = 00011011
/////////////////////////////////////////////

module galoismult(input  logic [7:0] a,
                  output logic [7:0] y);

    logic [7:0] ashift;
    
    assign ashift = {a[6:0], 1'b0};
    assign y = a[7] ? (ashift ^ 8'b00011011) : ashift;
endmodule