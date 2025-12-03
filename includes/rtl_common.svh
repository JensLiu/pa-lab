`define PIPELINE_STAGES 1
`define SINGLE_CYCLE
`define DATAPATH_EXPOSE_INTERNALS
`define REGISTER_FILE_EXPOSE_INTERNALS
`define DEBUG_INST_INFO_EXTENSION
// `define DATA_CACHE_DIVERGENCE_TEST
// `define INSTRUCTION_CACHE_DIVERGENCE_TEST

`define ASSERT(x) assert(x)
// `define ASSERT(x)

// `define SB_DEBUG_PRINT(x) $display({$sformatf x})
`define SB_DEBUG_PRINT(x)

// `define SB_FRONTEND_DEBUG_PRINT(x) $display({$sformatf x})
`define SB_FRONTEND_DEBUG_PRINT(x)

// `define CACHE_DEBUG_PRINT(x) $display({$sformatf x})
`define CACHE_DEBUG_PRINT(x)
