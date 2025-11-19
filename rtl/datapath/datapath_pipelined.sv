`include "rtl_common.svh"

module datapath_pipelined
    import pkg_global_defs::*;
    import pkg_riscv_instructions::*;
(
`ifdef DATAPATH_EXPOSE_INTERNALS
`ifdef REGISTER_FILE_EXPOSE_INTERNALS
    output reg_t DEBUG_regs[32],
`endif  // REGISTER_FILE_EXPOSE_INTERNALS
`endif  // DATAPATH_EXPOSE_INTERNALS
    input  clk_t clk
);

    // pipeline registers
    if_id_regs_t ifIdRegsQ;
    id_ex_regs_t idExRegsQ;
    ex_mem_regs_t exMemRegsQ;
    mem_wb_regs_t memWbRegsQ;

    // control signals
    if_control_t ifControl;
    id_control_t idControl;
    ex_control_t exControl;
    mem_control_t memControl;
    wb_control_t wbControl;

    // stage signals/hints
    if_hints_t ifHints;
    id_hints_t idHints;
    ex_hints_t exHints;
    mem_hints_t memHints;
    wb_hints_t wbHints;

    cache_request_if instCacheCpuRequest ();
    cache_request_if dataCacheCpuRequest ();

    if_id_regs_t ifIdRegsP;
    if_stage ifStage (
`ifdef INSTRUCTION_MEMORY_EXPOSE_INTERNALS
        .DEBUG_mem(DEBUG_inst_mem),
`endif
        .clk(clk),  // drives PC and memory
        .ifControl(ifControl),
        .ifIdRegs(ifIdRegsP),
        .ifHints(ifHints),
        .cacheRequest(instCacheCpuRequest.master)
    );

    id_ex_regs_t idExRegsP;
    id_stage idStage (
        .clk(clk),  // drives register files
`ifdef REGISTER_FILE_EXPOSE_INTERNALS
        .DEBUG_regs(DEBUG_regs),
`endif
        .ifIdRegs(ifIdRegsQ),
        .idControl(idControl),
        .idExRegs(idExRegsP),
        .idHints(idHints)
    );

    ex_mem_regs_t exMemRegsP;
    ex_stage exStage (
        .idExRegs (idExRegsQ),
        .exControl(exControl),
        .exMemRegs(exMemRegsP),
        .exHints  (exHints)
    );

    mem_wb_regs_t memWbRegsP;
    mem_stage memStage (
        .clk(clk),  // drives memory
        .exMemRegs(exMemRegsQ),
        .memControl(memControl),
        .memWbRegs(memWbRegsP),
        .memHints(memHints),
        .cacheRequest(dataCacheCpuRequest.master)
`ifdef DATA_CACHE_DIVERGENCE_TEST,
        .DEBUG_dataMemRequest(DEBUG_dataMemoryCpuRequest.master)  // Divergence test
`endif
    );

    wb_hints_t wbHintsP;
    wb_stage wbStage (
        .memWbRegs(memWbRegsQ),
        .wbControl(wbControl),
        .wbHints  (wbHints)
    );

    // mem_request_if instCacheMemRequest ();
    mem_request_if dataCacheMemRequest ();
    memory_inst instructionMemory (.cpuRequest(instCacheCpuRequest.slave));
    // cache_fast instructionCache (
    //     .clk(clk),
    //     .cpuRequest(instCacheCpuRequest.slave),
    //     .memRequest(memRequest.master)
    // );

    cache_fast dataCache (
        .clk(clk),
        .cpuRequest(dataCacheCpuRequest.slave),
        .memRequest(memRequest.master)
    );

`ifdef DATA_CACHE_DIVERGENCE_TEST
    cache_request_if DEBUG_dataMemoryCpuRequest ();
    memory_data dataMemory (
        .clk(clk),
        .cpuRequest(DEBUG_dataMemoryCpuRequest.slave)
    );
`endif

    // always_comb begin : MockDataAlwaysHit
    //     dataCacheCpuRequest.slave.ready = 1'b1;
    //     dataCacheCpuRequest.slave.failed = 1'b0;
    //     dataCacheCpuRequest.slave.dataFromCache = '0;
    // end

    mem_request_if memRequest ();
    // memory_request_sequencer memRequestSequencer (
    //     .instCacheRequest(instCacheMemRequest.slave),
    //     .dataCacheRequest(dataCacheMemRequest.slave),
    //     .memoryRequest(memRequest.master)
    // );


    byte_t DEBUG_mem[DATA_MEM_SIZE];
    unified_memory memory (
        .clk(clk),
        .request(memRequest.slave)
`ifdef UNIFIED_MEMORY_EXPOSE_INTERNALS,
        .DEBUG_mem(DEBUG_mem)
`endif
    );

    // Pipeline State Registers Propogation
    bool_t IfIdRegs_writeEnable, IdExRegs_writeEnable, ExMemRegs_writeEnable, MemWbRegs_writeEnable;
    bool_t IF_injectNop, ID_injectNop, EX_injectNop, MEM_injectNop;
    always_ff @(posedge clk) begin : PipelinePropogation
        // IF -> ID
        if (IfIdRegs_writeEnable) begin
            if (IF_injectNop) begin
                // ifIdRegsQ.pc <= ifIdRegsP.pc;
                ifIdRegsQ.pc <= 32'h0;
                ifIdRegsQ.inst <= inst_make_nop();
                ifIdRegsQ.exceptions <= exception_make_none();
            end else begin
                ifIdRegsQ <= ifIdRegsP;
            end
        end
        // ID -> EX
        if (IdExRegs_writeEnable) begin
            if (ID_injectNop) begin
                // idExRegsQ.pc <= idExRegsP.pc;
                idExRegsQ.pc <= 32'h0;

`ifdef DEBUG_INST_INFO_EXTENSION
                idExRegsQ.instInfo <=
                    inst_info_make_nop_with_inst_id(idExRegsP.instInfo.DEBUG_instID);
`else
                idExRegsQ.instInfo <= inst_info_make_nop();
`endif

                idExRegsQ.exceptions <= exception_make_none();
                idExRegsQ.rs1Data <= IMM_32_WHATEVER;
                idExRegsQ.rs2Data <= IMM_32_WHATEVER;
            end else begin
                idExRegsQ <= idExRegsP;
            end
        end

        // EX -> MEM
        if (ExMemRegs_writeEnable) begin
            if (EX_injectNop) begin
                // exMemRegsQ.pc <= exMemRegsP.pc;
                exMemRegsQ.pc <= 32'h0;
`ifdef DEBUG_INST_INFO_EXTENSION
                exMemRegsQ.instInfo <=
                    inst_info_make_nop_with_inst_id(exMemRegsP.instInfo.DEBUG_instID);
`else
                exMemRegsQ.instInfo <= inst_info_make_nop();
`endif
                exMemRegsQ.exceptions <= exception_make_none();
                exMemRegsQ.aluResult <= IMM_32_WHATEVER;
                exMemRegsQ.stData <= IMM_32_WHATEVER;
            end else begin
                exMemRegsQ <= exMemRegsP;
            end
        end
        // MEM -> WB
        if (MemWbRegs_writeEnable) begin
            if (MEM_injectNop) begin
                // memWbRegsQ.pc <= memWbRegsP.pc;
                memWbRegsQ.pc <= 32'h0;
`ifdef DEBUG_INST_INFO_EXTENSION
                memWbRegsQ.instInfo <=
                    inst_info_make_nop_with_inst_id(memWbRegsP.instInfo.DEBUG_instID);
`else
                memWbRegsQ.instInfo <= inst_info_make_nop();
`endif
                memWbRegsQ.exceptions <= exception_make_none();
                memWbRegsQ.memResult  <= IMM_32_WHATEVER;
            end else begin
                memWbRegsQ <= memWbRegsP;
            end
        end
    end

    // Stage Control Assignment
    always_comb begin : StageControl
        // IF Control
        ifControl.halt = ifHints.shouldHalt || idHints.shouldHalt || memHints.shouldHalt;
        ifControl.branchTaken = exHints.EX_branchTaken;
        ifControl.pcBr = exHints.EX_pcBr;

        // ID Control
        idControl.WB_isWriteback = wbHints.WB_isWriteback;
        idControl.WB_rd = wbHints.WB_rd;
        idControl.WB_hasException = wbHints.WB_hasException;
        idControl.WB_rdData = wbHints.WB_rdData;
        idControl.EX_rd = exHints.EX_rd;
        idControl.EX_isWriteback = exHints.EX_isWriteback;
        idControl.EX_isLoad = exHints.EX_isLoad;
        idControl.EX_aluResult = exHints.EX_aluResult;
        idControl.MEM_rd = memHints.MEM_rd;
        idControl.MEM_isWriteback = memHints.MEM_isWriteback;
        idControl.MEM_memResult = memHints.MEM_memResult;

        // EX Control
        exControl.placeholder = TRUE;

        // MEM Control
        memControl.placeholder = TRUE;

        // WB Control
        wbControl.placeholder = TRUE;

    end


    // Pipeline Control Assignment
    always_comb begin : PipelineControl
        IfIdRegs_writeEnable = TRUE;
        IdExRegs_writeEnable = TRUE;
        ExMemRegs_writeEnable = TRUE;
        MemWbRegs_writeEnable = TRUE;
        IF_injectNop = FALSE;
        ID_injectNop = FALSE;
        EX_injectNop = FALSE;
        MEM_injectNop = FALSE;

        if (ifHints.shouldHalt) begin
            IF_injectNop = TRUE;
        end

        if (idHints.shouldHalt) begin
            ID_injectNop = TRUE;
            IfIdRegs_writeEnable = FALSE;
        end

        if (memHints.shouldHalt) begin
            MEM_injectNop = TRUE;
            IfIdRegs_writeEnable = FALSE;
            IdExRegs_writeEnable = FALSE;
            ExMemRegs_writeEnable = FALSE;
        end

        if (exHints.EX_branchTaken) begin
            // kill previous instructions
            IF_injectNop = TRUE;
            ID_injectNop = TRUE;
        end

        if (wbHints.WB_hasException) begin
            IF_injectNop  = TRUE;
            ID_injectNop  = TRUE;
            EX_injectNop  = TRUE;
            MEM_injectNop = TRUE;
        end
    end

endmodule
