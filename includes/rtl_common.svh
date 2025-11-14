`define PIPELINE_STAGES 1
`define SINGLE_CYCLE
`define REGISTER_FILE_EXPOSE_INTERNALS
`define DATAPATH_EXPOSE_INTERNALS
`define DEBUG_INST_INFO_EXTENSION

`define PIPELINE_EMIT

`ifdef PIPELINE_EMIT
`define EMIT_INST_3(INST_NAME, ARG0, ARG1, ARG2) \
    $display("%s %0d, %0d, %0d", INST_NAME, ARG0, ARG1, ARG2)
`define EMIT_INST_2(INST_NAME, ARG0, ARG1) \
        $display("%s %0d, %0d", INST_NAME, ARG0, ARG1)
`define EMIT_INST_1(INST_NAME, ARG0) \
        $display("%s %0d", INST_NAME, ARG0)
`define EMIT_INST_0(INST_NAME) \
        $display("%s", INST_NAME)
`define EMIT_MSG(MSG) $display("%s", MSG)
`else
`define EMIT_INST_3(INST_NAME, ARG0, ARG1, ARG2)
`define EMIT_INST_2(INST_NAME, ARG0, ARG1)
`define EMIT_INST_1(INST_NAME, ARG0)
`define EMIT_INST_0(INST_NAME)
`define EMIT_MSG(MSG)
`endif

`define INST_INFO_MAKE_NOP(inst)  \
        // make sure no state is changed        \
        (inst).isLoad = FALSE;            \
        (inst).isStore = FALSE;           \
        (inst).isWriteback = FALSE;       \
        // make sure no ALU exceptions          \
        (inst).aluOp = ALU_INVALID;       \
        // (inst).rs1 = REG_NR_INVALID_FALLBACK;      \
        // (inst).rs2 = REG_NR_INVALID_FALLBACK;      \
        // (inst).rd = REG_NR_INVALID_FALLBACK;       \
