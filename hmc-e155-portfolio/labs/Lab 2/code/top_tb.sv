module top_tb();
	logic	    clk, reset;
	logic [3:0] Sw1, Sw2;
	logic [6:0] Seg;
	logic       En1, En2;
	logic [4:0] Sum, ExSum;
	logic [7:0] Errors;
	logic [7:0] Cur = 8'b0;
	
	// Initialize Device under Test
	top dut(Sw1, Sw2, Seg, En1, En2, Sum);
	
	// Start By reading testvectors
	initial
		
		begin
			Errors=0;
			
			reset=1; #22;
			reset=0;
			
		end
	
	// Generate Clock
	always

		begin
		
			clk=1; #5;
			clk=0; #5;
			
		end
		
	// Assign inputs on positive edge
	
	always @(posedge clk)
		
		begin
			
			#1;
			
			// Assign switch values
			Sw1 = Cur[3:0];
			Sw2 = Cur[7:4];
			
			ExSum = ~(Cur[3:0] + Cur[7:4]);
		
		end
		
	// Check if output mathes on the negative edge
	always @(negedge clk)
		
		if (~reset) begin
			
			
			if (Sum !== ExSum) begin
			
					$display("Error: Sw1=%b, Sw2=%b", Sw1, Sw2);
					
					$display(" outputs = %b (%b expected)", Sum, ExSum);
						
					Errors = Errors + 1;
			end
			
			Cur = Cur+1;
			
			
			if (Cur === 8'b1111111) begin
			
				$display("256 tests completed with %d errors", 
					Errors);
					
				$stop;
				
			end
			
		end
endmodule