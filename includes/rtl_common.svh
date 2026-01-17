`define PIPELINE_STAGES 1
`define SINGLE_CYCLE
`define DATAPATH_EXPOSE_INTERNALS
`define REGISTER_FILE_EXPOSE_INTERNALS
`define DEBUG_INST_INFO_EXTENSION

`define DATA_CACHE_DIVERGENCE_TEST
`define INSTRUCTION_CACHE_DIVERGENCE_TEST

`define DATAPATH_USE_STORE_BUFFER

// `define ASSERT(x) assert(x)
`define ASSERT(x)

// `define REGISTER_FILE_DEBUG_PRINT(x) $display({$sformatf x})
`define REGISTER_FILE_DEBUG_PRINT(x)

// `define SB_DEBUG_PRINT(x) $display({$sformatf x})
`define SB_DEBUG_PRINT(x)

// `define SB_FRONTEND_DEBUG_PRINT(x) $display({$sformatf x})
`define SB_FRONTEND_DEBUG_PRINT(x)

// `define CACHE_DEBUG_PRINT(x) $display({$sformatf x})
`define CACHE_DEBUG_PRINT(x)

// `define ROB_DEBUG_PRINT(x) $display({$sformatf x})
`define ROB_DEBUG_PRINT(x)


// `define IF_STAGE_DEBUG_PRINT(x) $display({$sformatf x})
// `define ID_STAGE_DEBUG_PRINT(x) $display({$sformatf x})
// `define EX_STAGE_DEBUG_PRINT(x) $display({$sformatf x})
// `define MEM_STAGE_DEBUG_PRINT(x) $display({$sformatf x})
// `define IMU_STAGE_DEBUG_PRINT(x) $display({$sformatf x})
// `define WB_STAGE_DEBUG_PRINT(x) $display({$sformatf x})
// `define DATAPATH_DEBUG_PRINT(x) $display({$sformatf x})

`define IF_STAGE_DEBUG_PRINT(x)
`define ID_STAGE_DEBUG_PRINT(x)
`define EX_STAGE_DEBUG_PRINT(x)
`define MEM_STAGE_DEBUG_PRINT(x)
`define IMU_STAGE_DEBUG_PRINT(x)
`define WB_STAGE_DEBUG_PRINT(x)
`define DATAPATH_DEBUG_PRINT(x)
