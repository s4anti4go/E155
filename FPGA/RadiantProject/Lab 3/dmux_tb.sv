`timescale 1ns/1ps

module dmux_tb;
  // DUT I/O
  logic        clk;
  logic [3:0]  Sw1, Sw2;
  logic [3:0]  s;
  logic        En1, En2;

  // Instantiate DUT (module DMux from your code)
  DMux dut (
    .Osc (clk),
    .Sw1 (Sw1),
    .Sw2 (Sw2),
    .s   (s),
    .En1 (En1),
    .En2 (En2)
  );

  // 100 MHz TB clock (10 ns period)
  initial clk = 1'b0;
  always  #5 clk = ~clk;

  // Test bookkeeping
  integer errors = 0;
  integer periods_seen = 0;

  // Per-period symmetry counters (reset at each En2 rising edge)
  integer high_cnt = 0;
  integer low_cnt  = 0;
  bit     seen_first_rise = 0;

  // Drive inputs and run
  initial begin
    // Distinct nibbles so mismatches are obvious
    Sw1 = 4'hA;   // expect when En1=1 (En2=0)
    Sw2 = 4'h5;   // expect when En2=1 (En1=0)

    // Run long enough to see several periods
    // Also change inputs mid-run to confirm mux path
    repeat (3) @(posedge clk);

    // Let it run for 2 full En2 periods
    wait_rises(2);

    // Change inputs and observe they take effect immediately
    Sw1 = 4'h3;
    Sw2 = 4'hC;

    // Another 2 periods
    wait_rises(2);

    // Report
    if (errors == 0)
      $display("DMux TB PASS: %0d periods checked, no errors.", periods_seen);
    else
      $display("DMux TB FAIL: %0d total errors.", errors);

    $stop;
  end

  // --- Invariant checks each clock ---
  always @(posedge clk) begin
    // En1 and En2 must be complementary
    if (En1 === En2) begin
      errors += 1;
      $display("[%0t] ERROR: En1(%0b) == En2(%0b) -- not complementary.", $time, En1, En2);
    end

    // Selection must match enables
    if (En1 && !En2 && s !== Sw1) begin
      errors += 1;
      $display("[%0t] ERROR: En1=1 En2=0, expected s=Sw1(%h) got %h", $time, Sw1, s);
    end
    if (En2 && !En1 && s !== Sw2) begin
      errors += 1;
      $display("[%0t] ERROR: En2=1 En1=0, expected s=Sw2(%h) got %h", $time, Sw2, s);
    end

    // Track En2 high/low counts for symmetry within each period
    if (En2) high_cnt++; else low_cnt++;

    // On En2 rising edge, a full period just completed since the previous rise
    if ($rose(En2)) begin
      if (seen_first_rise) begin
        periods_seen++;

        // Expect approximately equal high/low ticks (tolerance ±1)
        if ((high_cnt - low_cnt > 1) || (low_cnt - high_cnt > 1)) begin
          errors += 1;
          $display("[%0t] ERROR: En2 duty not ~50%%: high=%0d low=%0d", $time, high_cnt, low_cnt);
        end else begin
          $display("[%0t] Info: Period %0d OK (En2 high=%0d, low=%0d).",
                   $time, periods_seen, high_cnt, low_cnt);
        end
      end
      // reset counters for next period
      high_cnt = 0;
      low_cnt  = 0;
      seen_first_rise = 1;
    end
  end

  // --- Helper: wait for N En2 rising edges (full periods after first one) ---
  task wait_rises(input int n);
    int got = 0;
    bit primed = 0;
    begin
      // prime on first rise
      @(posedge clk);
      while (!primed) begin
        if ($rose(En2)) primed = 1;
        @(posedge clk);
      end
      // then count n more rises
      while (got < n) begin
        if ($rose(En2)) got++;
        @(posedge clk);
      end
    end
  endtask

endmodule
