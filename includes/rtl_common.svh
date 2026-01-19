`define PIPELINE_STAGES 1
`define SINGLE_CYCLE
`define DATAPATH_EXPOSE_INTERNALS
`define REGISTER_FILE_EXPOSE_INTERNALS
`define DEBUG_INST_INFO_EXTENSION

`define DATA_CACHE_DIVERGENCE_TEST
`define INSTRUCTION_CACHE_DIVERGENCE_TEST

`define DATAPATH_USE_STORE_BUFFER


`define DEBUG_DATAPATH
// `define DEBUG_PRINT

`ifdef DEBUG_PRINT
`define DEBUG_PRINT_IF_STAGE
`define DEBUG_PRINT_ID_STAGE
`define DEBUG_PRINT_EX_STAGE
`define DEBUG_PRINT_MEM_STAGE
`define DEBUG_PRINT_WB_STAGE
`define DEBUG_PRINT_REGISTER_FILE
`define DEBUG_PRINT_STORE_BUFFER
`define DEBUG_DATAPATH
`define DEBUG_PRINT_CACHE
`define DEBUG_PRINT_ROB
`define ROB_REG_QUERY_DEBUG_PRINT_EN
`define DEBUG_IMUL_PIPELINE
`endif

// `define ASSERT(x) assert(x)
`define ASSERT(x)

`ifdef DEBUG_PRINT_IF_STAGE
`define IF_STAGE_DEBUG_PRINT(x) $display({$sformatf x})
`else
`define IF_STAGE_DEBUG_PRINT(x)
`endif
`ifdef DEBUG_PRINT_ID_STAGE
`define ID_STAGE_DEBUG_PRINT(x) $display({$sformatf x})
`else
`define ID_STAGE_DEBUG_PRINT(x)
`endif
`ifdef DEBUG_PRINT_EX_STAGE
`define EX_STAGE_DEBUG_PRINT(x) $display({$sformatf x})
`else
`define EX_STAGE_DEBUG_PRINT(x)
`endif
`ifdef DEBUG_PRINT_MEM_STAGE
`define MEM_STAGE_DEBUG_PRINT(x) $display({$sformatf x})
`else
`define MEM_STAGE_DEBUG_PRINT(x)
`endif
`ifdef DEBUG_PRINT_WB_STAGE
`define WB_STAGE_DEBUG_PRINT(x) $display({$sformatf x})
`else
`define WB_STAGE_DEBUG_PRINT(x)
`endif
`ifdef DEBUG_IMUL_PIPELINE
`define IMUL_PIPELINE_DEBUG_PRINT(x) $display({$sformatf x})
`else
`define IMUL_PIPELINE_DEBUG_PRINT(x)
`endif
`ifdef DEBUG_IMUL_STAGE
`define DEBUG_IMUL_STAGE_PRINT(x) $display({$sformatf x})
`else
`define DEBUG_IMUL_STAGE_PRINT(x)
`endif
`ifdef DEBUG_DATAPATH
`define DATAPATH_DEBUG_PRINT(x) $display({$sformatf x})
`else
`define DATAPATH_DEBUG_PRINT(x)
`endif
`ifdef DEBUG_PRINT_REGISTER_FILE
`define REGISTER_FILE_DEBUG_PRINT(x) $display({$sformatf x})
`else
`define REGISTER_FILE_DEBUG_PRINT(x)
`endif
`ifdef DEBUG_PRINT_STORE_BUFFER
`define SB_DEBUG_PRINT(x) $display({$sformatf x})
`else
`define SB_DEBUG_PRINT(x)
`endif
`ifdef DEBUG_PRINT_SB_FRONTEND
`define SB_FRONTEND_DEBUG_PRINT(x) $display({$sformatf x})
`else
`define SB_FRONTEND_DEBUG_PRINT(x)
`endif
`ifdef DEBUG_PRINT_CACHE
`define CACHE_DEBUG_PRINT(x) $display({$sformatf x})
`else
`define CACHE_DEBUG_PRINT(x)
`endif
`ifdef DEBUG_PRINT_ROB
`define ROB_DEBUG_PRINT(x) $display({$sformatf x})
`else
`define ROB_DEBUG_PRINT(x)
`endif
