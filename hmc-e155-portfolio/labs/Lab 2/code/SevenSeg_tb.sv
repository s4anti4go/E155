module SevenSeg_tb();
	logic	     clk, reset;
	logic [3:0]  S;
	logic [6:0]  Seg, ExSeg;
	logic [31:0] vectornum, errors;
	logic [10:0] testvectors[15:0];
	
	// Initialize Device under Test
	SegDisp dut(S, Seg);
	
	// Generate Clock
	always

		begin
		
			clk=1; #5;
			clk=0; #5;
			
		end
	
	// Start By reading testvectors
	initial
		
		begin
			
			$readmemb("SevenSeg.tv", testvectors);
			
			vectornum=0;
			errors=0;
			
			reset=1; #22;
			reset=0;
			
		end
	
	// Assign test vectors on positive edge
	always @(posedge clk)
		
		begin
			
			#1;
			
			{S, ExSeg} = testvectors[vectornum];
		
		end
		
	// Check if DUT output matches expected output at the end of the clock	
	always @(negedge clk)
		
		if (~reset) begin
		
			if (Seg !== ExSeg) begin
			
					$display("Error: inputs = %b", S);
					
					$display(" outputs = %b (%b expected)", Seg, ExSeg);
						
					errors = errors + 1;
			end
			
			vectornum = vectornum + 1;
			
			
			if (testvectors[vectornum] === 11'bx) begin
			
				$display("%d tests completed with %d errors", vectornum, 
					errors);
					
				$stop;
				
			end
			
		end

endmodule