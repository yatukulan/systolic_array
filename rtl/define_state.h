`ifndef DEFINE_STATE

// This defines the states for every FSM in the design

// matmul_core: load operands -> clear accumulators -> 3N-2 MAC steps -> done
typedef enum logic [1:0] {
	S_CORE_IDLE,
	S_CORE_CLEAR,
	S_CORE_RUN,
	S_CORE_DONE
} core_state_type;

`define DEFINE_STATE 1
`endif
