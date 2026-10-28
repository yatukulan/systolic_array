/*
4x4 INT8 Systolic Array
Yatukulan Vivekanandan
Department of Electrical and Computer Engineering
McMaster University
Ontario, Canada
*/

// This is the self-checking testbench for matmul_core
//
//   * Directed tests: zeros, identity, extreme values, sign mixes
//   * Reference model: plain nested-loop matrix multiply (behavioural)
//   * Scoreboard: compares all 16 outputs of every test, counts mismatches
//
// Prints "TEST PASSED" or "TEST FAILED" (parsed by scripts/regress.py).
//
// Written in plain procedural SystemVerilog so it runs unchanged in
// ModelSim/Questa, Verilator and Icarus Verilog.

`timescale 1ns/100ps
`ifndef DISABLE_DEFAULT_NET
`default_nettype none
`endif

module TB;

	parameter N = 4;
	parameter DW = 8;
	parameter AW = 32;
	parameter TIMEOUT_CYCLES = 1000;

	// ---------------- DUT signals ----------------
	logic              clock_50 = 1'b0;
	logic              resetn;
	logic              start;
	logic [N*N*DW-1:0] a_flat, b_flat;
	logic              busy, done;
	logic [N*N*AW-1:0] c_flat;

	always begin
		#10;
		clock_50 = ~clock_50;
	end

		matmul_core #(
		.N(N)
	) UUT (
		.Clock(clock_50),
		.Resetn(resetn),
		.Start(start),
		.A_flat(a_flat),
		.B_flat(b_flat),
		.Busy(busy),
		.Done(done),
		.C_flat(c_flat)
	);

	// ---------------- Test state ----------------
	int A [0:N*N-1];          // A[i*N+k]
	int B [0:N*N-1];          // B[k*N+j]
	int C_ref [0:N*N-1];      // expected result

	int tests_run, checks_run, mismatches;

	// ---------------- Reference model ----------------
	task compute_reference();
		for (int i = 0; i < N; i++)
			for (int j = 0; j < N; j++) begin
				int sum;
				sum = 0;
				for (int k = 0; k < N; k++) sum += A[i*N+k] * B[k*N+j];
				C_ref[i*N+j] = sum;
			end
	endtask

	// Pack the test matrices onto the DUT inputs
	task drive_operands();
		for (int idx = 0; idx < N*N; idx++) begin
			a_flat[idx*DW +: DW] = A[idx][DW-1:0];
			b_flat[idx*DW +: DW] = B[idx][DW-1:0];
		end
	endtask

	// ---------------- Scoreboard ----------------
	task check_results(input int test_id);
		for (int idx = 0; idx < N*N; idx++) begin
			int got;
			got = $signed(c_flat[idx*AW +: AW]);
			checks_run++;
			if (got !== C_ref[idx]) begin
				mismatches++;
				if (mismatches <= 10)
					$display("  MISMATCH test %0d C[%0d][%0d]: expected %0d, got %0d",
							 test_id, idx / N, idx % N, C_ref[idx], got);
			end
		end
	endtask

	// ---------------- One complete matrix multiply ----------------
	task run_one(input int test_id);
		int cycles;
		compute_reference();
		drive_operands();

		@(negedge clock_50) start = 1'b1;
		@(negedge clock_50) start = 1'b0;
		cycles = 1;
		while (!done && cycles < TIMEOUT_CYCLES) begin
			@(negedge clock_50);
			cycles++;
		end

		if (!done) begin
			$display("  ERROR test %0d: timeout waiting for done", test_id);
			mismatches++;
		end else check_results(test_id);
		@(negedge clock_50);
		tests_run++;
	endtask

	task fill(input int a_val, input int b_val);
		for (int idx = 0; idx < N*N; idx++) begin
			A[idx] = a_val;
			B[idx] = b_val;
		end
	endtask

	// Deterministic operands with every value distinct and mixed signs
	task fill_ramp(input int a0, input int b0);
		for (int idx = 0; idx < N*N; idx++) begin
			A[idx] = a0 + 13 * idx;
			B[idx] = b0 - 11 * idx;
		end
	endtask

	task apply_reset();
		$display("\n*** Asserting the asynchronous reset ***");
		resetn = 1'b0;
		repeat (3) @(negedge clock_50);
		resetn = 1'b1;
		@(negedge clock_50);
	endtask

	// ---------------- Main sequence ----------------
	initial begin
		tests_run = 0; checks_run = 0; mismatches = 0;

		$timeformat(-6, 2, "us", 10);
		$display("=== matmul_core testbench: directed tests ===");
		start  = 1'b0;
		a_flat = '0;
		b_flat = '0;
		apply_reset();

		// ---- Directed tests ----
		$display("[directed] zeros");                 fill(0, 0);       run_one(0);
		$display("[directed] all max (127 x 127)");   fill(127, 127);   run_one(1);
		$display("[directed] all min (-128 x -128)"); fill(-128, -128); run_one(2);
		$display("[directed] max x min");             fill(127, -128);  run_one(3);

		$display("[directed] identity x random");
		fill_ramp(-100, 90);
		for (int i = 0; i < N; i++)
			for (int k = 0; k < N; k++) A[i*N+k] = (i == k) ? 1 : 0;
		run_one(4);

		$display("[directed] distinct values 1..16 (catches index/skew bugs)");
		for (int idx = 0; idx < N*N; idx++) begin
			A[idx] = idx + 1;
			B[idx] = -(idx + 1);
		end
		run_one(5);

		// ---- Report ----
		$display("--------------------------------------------------");
		$display("Tests run        : %0d", tests_run);
		$display("Outputs checked  : %0d", checks_run);
		$display("Mismatches       : %0d", mismatches);
		if (mismatches == 0) $display("TEST PASSED");
		else                 $display("TEST FAILED");
		$display("--------------------------------------------------");
		$stop;
	end

	// Global watchdog
	initial begin
		#(64'd20 * 64'd100000);
		$display("TEST FAILED (global timeout)");
		$stop;
	end

endmodule
