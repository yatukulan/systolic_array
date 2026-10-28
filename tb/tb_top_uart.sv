/*
4x4 INT8 Systolic Array
Yatukulan Vivekanandan
Department of Electrical and Computer Engineering
McMaster University
Ontario, Canada
*/

// This is the system-level testbench for the DE2-115 top level
//
// Plays the role of the PC: sends A and B over the UART RX pin, decodes
// the 64-byte reply on the UART TX pin, and checks it against the same
// behavioural reference model used in the core testbench. This exercises
// the whole path the board uses: UART RX -> byte packing -> systolic core
// -> result serialization -> UART TX.
//
// The UART runs at CLKS_PER_BIT = 16 and the push buttons are sampled every
// 4 clocks in simulation (instead of 434 and 50,000) so the test finishes
// quickly; the logic is identical.
//
// Plusargs: +SEED=<n> +NUM_MATRICES=<n>

`timescale 1ns/100ps
`ifndef DISABLE_DEFAULT_NET
`default_nettype none
`endif

module TB_TOP;

	parameter N = 4;
	parameter CLKS_PER_BIT = 16;
	parameter CLKS_PER_SAMPLE = 4;        // PB_controller sample period in sim
	parameter MAX_BYTES = 64 * 64;    // room for 63 matrices per run

	logic        clock_50 = 1'b0;
	logic [3:0]  push_button_n;
	logic [17:0] switches;
	wire  [6:0]  seven_seg_n [7:0];   // wire: Icarus does not drive a logic array from an output port
	logic [8:0]  led_green;
	logic        uart_rx;          // PC -> FPGA
	logic        uart_tx;          // FPGA -> PC

	always begin
		#10;
		clock_50 = ~clock_50;
	end

		matmul_uart_top #(
		.UART_CLOCKS_PER_BIT(CLKS_PER_BIT),
		.PB_CLOCKS_PER_SAMPLE(CLKS_PER_SAMPLE)
	) UUT (
		.CLOCK_50_I(clock_50),
		.PUSH_BUTTON_N_I(push_button_n),
		.SWITCH_I(switches),
		.SEVEN_SEGMENT_N_O(seven_seg_n),
		.LED_GREEN_O(led_green),
		.UART_RX_I(uart_rx),
		.UART_TX_O(uart_tx)
	);

	int A [0:N*N-1];
	int B [0:N*N-1];
	int C_ref [0:N*N-1];

	int seed, num_matrices, mismatches, framing_errors;
	logic [31:0] rng_state;

	// ---------------- PC-side UART monitor (decodes FPGA TX) ----------------
	logic [7:0] rx_buf [0:MAX_BYTES-1];
	int         rx_count = 0;

	initial begin
		forever begin
			logic [7:0] b;
			@(negedge uart_tx);                         // start bit
			repeat (CLKS_PER_BIT/2) @(posedge clock_50);     // middle of start bit
			for (int i = 0; i < 8; i++) begin
				repeat (CLKS_PER_BIT) @(posedge clock_50);
				b[i] = uart_tx;
			end
			repeat (CLKS_PER_BIT) @(posedge clock_50);       // middle of stop bit
			if (uart_tx !== 1'b1) framing_errors++;
			if (rx_count < MAX_BYTES) rx_buf[rx_count] = b;
			rx_count++;
		end
	end

	// ---------------- PC-side UART driver (to FPGA RX) ----------------
	task send_byte(input logic [7:0] b);
		uart_rx = 1'b0;                                  // start bit
		repeat (CLKS_PER_BIT) @(posedge clock_50);
		for (int i = 0; i < 8; i++) begin
			uart_rx = b[i];
			repeat (CLKS_PER_BIT) @(posedge clock_50);
		end
		uart_rx = 1'b1;                                  // stop bit
		repeat (CLKS_PER_BIT) @(posedge clock_50);
	endtask

	function logic [31:0] rng_next();
		logic [31:0] x;
		x = rng_state;
		x = x ^ (x << 13);
		x = x ^ (x >> 17);
		x = x ^ (x << 5);
		rng_state = x;
		return x;
	endfunction

	function int rand_int8();
		logic [31:0] r;
		r = rng_next();
		return $signed(r[7:0]);
	endfunction

	task compute_reference();
		for (int i = 0; i < N; i++)
			for (int j = 0; j < N; j++) begin
				int sum;
				sum = 0;
				for (int k = 0; k < N; k++) sum += A[i*N+k] * B[k*N+j];
				C_ref[i*N+j] = sum;
			end
	endtask

	// Send one A/B pair, wait for 64 reply bytes, check every result
	task run_matrix(input int test_id);
		int base, timeout;
		compute_reference();
		base = rx_count;
		for (int idx = 0; idx < N*N; idx++) send_byte(A[idx][7:0]);
		for (int idx = 0; idx < N*N; idx++) send_byte(B[idx][7:0]);
		timeout = 0;
		while (rx_count < base + 64 && timeout < 64 * 12 * CLKS_PER_BIT + 1000) begin
			@(posedge clock_50);
			timeout++;
		end
		if (rx_count < base + 64) begin
			$display("  ERROR matrix %0d: only %0d of 64 reply bytes", test_id, rx_count - base);
			mismatches++;
		end
		else for (int idx = 0; idx < N*N; idx++) begin
			logic [31:0] word;
			word = {rx_buf[base + idx*4 + 3], rx_buf[base + idx*4 + 2],
					rx_buf[base + idx*4 + 1], rx_buf[base + idx*4 + 0]};
			if ($signed(word) !== C_ref[idx]) begin
				mismatches++;
				if (mismatches <= 10)
					$display("  MISMATCH matrix %0d C[%0d][%0d]: expected %0d, got %0d",
							 test_id, idx / N, idx % N, C_ref[idx], $signed(word));
			end
		end
	endtask

	initial begin
		$timeformat(-6, 2, "us", 10);
		if (!$value$plusargs("SEED=%d", seed))                 seed = 1;
		if (!$value$plusargs("NUM_MATRICES=%d", num_matrices)) num_matrices = 20;
		rng_state      = (seed == 0) ? 32'h1 : seed;
		mismatches     = 0;
		framing_errors = 0;

		$display("=== system (UART) testbench: SEED=%0d NUM_MATRICES=%0d ===", seed, num_matrices);
		uart_rx       = 1'b1;
		push_button_n = 4'b1111;            // buttons released
		$display("\n*** Asserting the asynchronous reset ***");
		switches      = 18'h20000;          // SW17 up: hold reset
		repeat (3) @(negedge clock_50);
		switches      = '0;                 // SW17 down: run
		$display("*** Deasserting the asynchronous reset ***\n");
		repeat (5) @(negedge clock_50);

		// Directed: extremes through the whole serial path
		for (int idx = 0; idx < N*N; idx++) begin
			A[idx] = (idx % 2 == 1) ? 127 : -128;
			B[idx] = -128;
		end
		run_matrix(0);

		// Random
		for (int t = 1; t <= num_matrices; t++) begin
			for (int idx = 0; idx < N*N; idx++) begin
				A[idx] = rand_int8();
				B[idx] = rand_int8();
			end
			run_matrix(t);
		end

		$display("Matrices sent    : %0d", num_matrices + 1);
		$display("Reply bytes      : %0d", rx_count);
		$display("Mismatches       : %0d", mismatches);
		$display("Framing errors   : %0d", framing_errors);
		if (mismatches == 0 && framing_errors == 0 && rx_count == 64 * (num_matrices + 1))
			$display("TEST PASSED");
		else
			$display("TEST FAILED");
		$stop;
	end

endmodule
