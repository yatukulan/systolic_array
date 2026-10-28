`ifndef DEFINE_STATE

// This defines the states for every FSM in the design

// matmul_core: load operands -> clear accumulators -> 3N-2 MAC steps -> done
typedef enum logic [1:0] {
	S_CORE_IDLE,
	S_CORE_CLEAR,
	S_CORE_RUN,
	S_CORE_DONE
} core_state_type;

// UART_receiver: 8N1 serial receive
typedef enum logic [1:0] {
	S_RXC_IDLE,
	S_RXC_START_BIT,
	S_RXC_DATA_BITS,
	S_RXC_STOP_BIT
} RX_controller_state_type;

// UART_transmitter: 8N1 serial transmit
typedef enum logic [1:0] {
	S_TXC_IDLE,
	S_TXC_START_BIT,
	S_TXC_DATA_BITS,
	S_TXC_STOP_BIT
} TX_controller_state_type;

// matmul_uart_top: receive 32 bytes -> compute -> send 64 bytes
typedef enum logic [2:0] {
	S_TOP_RECEIVE,
	S_TOP_START,
	S_TOP_COMPUTE,
	S_TOP_TX_SEND,
	S_TOP_TX_WAIT
} top_state_type;

`define DEFINE_STATE 1
`endif
