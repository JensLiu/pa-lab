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

    // Debug Metrics
    word_t DEBUG_executedInstCount;
    word_t DEBUG_cycles;
    always_ff @(posedge clk) begin
        DEBUG_cycles <= DEBUG_cycles + 1;
        if (wbHints.WB_commitFinished) begin
            DEBUG_executedInstCount <= DEBUG_executedInstCount + 1;
        end
    end

    // pipeline registers
    if_id_regs_t   ifIdRegsQ;
    id_ex_regs_t   idExRegsQ;
    ex_mem_regs_t  exMemRegsQ;
    id_imul_regs_t idImulRegsQ;
    initial begin
        idExRegsQ.ticket   = ROB_TICKET_INVALID;
        exMemRegsQ.ticket  = ROB_TICKET_INVALID;
        idImulRegsQ.ticket = ROB_TICKET_INVALID;
        idImulRegsQ.ticket = ROB_TICKET_INVALID;
    end

    // pipeline register wires
    if_id_regs_t ifIdRegsP;
    id_ex_regs_t idExRegsP;
    ex_mem_regs_t exMemRegsP;
    id_imul_regs_t idImulRegsP;


    // control signals
    if_control_t ifControl;
    id_control_t idControl;
    ex_control_t exControl;
    mem_control_t memControl;
    imul_control_t imulControl;
    wb_control_t wbControl;
    /* verilator lint_off UNOPTFLAT */
    rob_control_t robControl;
    /* verilator lint_on UNOPTFLAT */

    // stage signals/hints
    if_hints_t ifHints;
    id_hints_t idHints;
    ex_hints_t exHints;
    mem_hints_t memHints;
    imul_hints_t imulHints;
    wb_hints_t wbHints;
    rob_hints_t robHints;

    cache_request_if instCacheCpuRequest ();
    cache_request_if dataCacheCpuRequest ();

    rob_ticket_request_if robTicketRequest ();
    rob_reg_query_if robRegQuery ();
    rob_store_query_if robStoreQuery ();

    // ========================= Pipeline Stages =========================
    if_stage ifStage (
`ifdef INSTRUCTION_MEMORY_EXPOSE_INTERNALS
        .DEBUG_mem(DEBUG_inst_mem),
`endif
        .clk(clk),  // drives PC
        .ifControl(ifControl),
        .ifIdRegs(ifIdRegsP),
        .ifHints(ifHints),
        // .cacheRequest(instCacheCpuRequest.master)
        .cacheRequest(instCacheCpuRequest.master)
`ifdef INSTRUCTION_CACHE_DIVERGENCE_TEST,
        .DEBUG_instMemRequest(DEBUG_instMemoryCpuRequest.master)
`endif
    );

    id_stage idStage (
        .clk(clk),  // drives register files
`ifdef REGISTER_FILE_EXPOSE_INTERNALS
        .DEBUG_regs(DEBUG_regs),
`endif
        .ifIdRegs(ifIdRegsQ),
        .idControl(idControl),
        .idExRegs(idExRegsP),
        .idImulRegs(idImulRegsP),
        .idHints(idHints),
        .regQuery(robRegQuery.master),
        .ticketRequest(robTicketRequest.master)
    );

    integer_multiply_pipeline imul (
        .clk(clk),
        .idImulRegs(idImulRegsP),
        .imulControl(imulControl),
        .imulHints(imulHints)
    );

    ex_stage exStage (
        .clk(clk),
        .idExRegs(idExRegsQ),
        .exControl(exControl),
        .exMemRegs(exMemRegsP),
        .exHints(exHints)
    );

    mem_stage memStage (
        .clk(clk),
        .exMemRegs(exMemRegsQ),
        .memControl(memControl),
        .memHints(memHints),
        .cacheRequest(dataCacheCpuRequest.master),
        .storeQuery(robStoreQuery.master)
`ifdef DATA_CACHE_DIVERGENCE_TEST,
        .DEBUG_dataMemRequest(DEBUG_dataMemoryCpuRequest.master)
`endif
    );

    wb_stage wbStage (
        .clk(clk),
        .wbControl(wbControl),
        .wbHints(wbHints)
    );

    // ========================= Reorder Buffer =========================
    reorder_buffer rob (
        .clk(clk),
        .robControl(robControl),
        .robHints(robHints),
        .ticketRequest(robTicketRequest.slave),
        .regQuery(robRegQuery.slave),
        .storeQuery(robStoreQuery.slave)
    );

    // ========================= Cache and Store Buffer =========================
    mem_request_if instCacheMemRequest ();
    mem_request_if dataCacheMemRequest ();
    mem_request_if sequencerMemRequest ();

    cache_hit_query_if _instCacheHitQuery ();  // unused
    cache #("InstructionCache") instructionCache (
        .clk(clk),
        .cpuRequest(instCacheCpuRequest.slave),
        .memRequest(instCacheMemRequest.master),
        .cpuHitQuery(_instCacheHitQuery.slave)
    );

`ifdef DATAPATH_USE_STORE_BUFFER
    cache_request_if dataCacheCacheRequest ();
    cache_hit_query_if dataCacheHitQuery ();
    store_buffer_frontend storeBuffer (
        .clk(clk),
        .cpuRequest(dataCacheCpuRequest.slave),
        .deligatedCpuRequest(dataCacheCacheRequest.master),
        .cacheHitQuery(dataCacheHitQuery.master)
    );
    cache #("DataCache") dataCache (
        .clk(clk),
        .cpuRequest(dataCacheCacheRequest.slave),
        .memRequest(dataCacheMemRequest.master),
        .cpuHitQuery(dataCacheHitQuery.slave)
    );
`else
    cache_hit_query_if _dataCacheHitQuery ();
    cache_fast dataCache (
        .clk(clk),
        .cpuRequest(dataCacheCpuRequest.slave),
        .memRequest(dataCacheMemRequest.master),
        .cpuHitQuery(_dataCacheHitQuery.slave)
    );
`endif

    memory_request_sequencer memRequestSequencer (
        .clk(clk),
        .instCacheRequest(instCacheMemRequest.slave),
        .dataCacheRequest(dataCacheMemRequest.slave),
        .memoryRequest(sequencerMemRequest.master)
    );

`ifdef UNIFIED_MEMORY_EXPOSE_INTERNALS
    byte_t DEBUG_mem[DATA_MEM_SIZE];
`endif
    unified_memory memory (
        .clk(clk),
        .request(sequencerMemRequest.slave)
`ifdef UNIFIED_MEMORY_EXPOSE_INTERNALS,
        .DEBUG_mem(DEBUG_mem)
`endif
    );

`ifdef INSTRUCTION_CACHE_DIVERGENCE_TEST
    cache_request_if DEBUG_instMemoryCpuRequest ();
    memory_inst instructionMemory (.cpuRequest(DEBUG_instMemoryCpuRequest.slave));
`endif

`ifdef DATA_CACHE_DIVERGENCE_TEST
    cache_request_if DEBUG_dataMemoryCpuRequest ();
    memory_data dataMemory (
        .clk(clk),
        .cpuRequest(DEBUG_dataMemoryCpuRequest.slave)
    );
`endif

    // ========================= Stage Control Logic =========================
    // Pipeline State Registers Propogation
    bool_t
        IfIdRegs_writeEnable,
        IdExRegs_writeEnable,
        IdImulRegs_writeEnable,
        ExMemRegs_writeEnable,
        MemWbRegs_writeEnable;
    bool_t IF_injectNop, ID_injectNop, EX_injectNop, MEM_injectNop;
    always_ff @(posedge clk) begin : PipelinePropogation
        // IF -> ID
        if (IfIdRegs_writeEnable) begin
            if (IF_injectNop) begin
                `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d Injecting NOP into ID stage", DEBUG_tick));
                // ifIdRegsQ.pc <= ifIdRegsP.pc;
                ifIdRegsQ.pc <= 32'h0;
                ifIdRegsQ.inst <= inst_make_nop();
                ifIdRegsQ.exceptions <= exception_make_none();
                ifIdRegsQ.instValid <= FALSE;
            end else begin
                `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d IF->ID forwarding", DEBUG_tick));
                ifIdRegsQ <= ifIdRegsP;
            end
        end else begin
            `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d IF->ID stage register stalled", DEBUG_tick));
        end

        // ID -> EX
        if (IdExRegs_writeEnable) begin
            if (ID_injectNop) begin
                `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d Injecting NOP into EX stage", DEBUG_tick));
                // idExRegsQ.pc <= idExRegsP.pc;
                idExRegsQ.pc <= 32'h0;
                idExRegsQ.ticket <= ROB_TICKET_INVALID;
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
                `DATAPATH_DEBUG_PRINT(
                    ("[Datapath]: @%0d Forwarding into EX stage (%0d -> %0d)", DEBUG_tick, 
                        idExRegsP.ticket, idExRegsQ.ticket));
                idExRegsQ <= idExRegsP;
            end
        end else begin
            `DATAPATH_DEBUG_PRINT(
                ("[Datapath]: @%0d ID->EX stage register stalled (%0d)", DEBUG_tick, idExRegsQ.ticket));
        end

        // ID -> IMUL
        if (IdImulRegs_writeEnable) begin
            if (ID_injectNop) begin
                `DATAPATH_DEBUG_PRINT(
                    ("[Datapath]: @%0d Injecting NOP into IMUL stage", DEBUG_tick));
                idImulRegsQ.ticket <= ROB_TICKET_INVALID;
                idImulRegsQ.A <= IMM_32_WHATEVER;
                idImulRegsQ.B <= IMM_32_WHATEVER;
            end else begin
                `DATAPATH_DEBUG_PRINT(
                    ("[Datapath]: @%0d ID->IMUL forwarding (%0d -> %0d)", DEBUG_tick,
                                       idImulRegsP.ticket, idImulRegsQ.ticket));
                idImulRegsQ <= idImulRegsP;
            end
        end else begin
            `DATAPATH_DEBUG_PRINT(
                ("[Datapath]: @%0d ID->IMUL stage register stalled (%0d)", DEBUG_tick, idImulRegsQ.ticket));
        end

        // EX -> MEM
        if (ExMemRegs_writeEnable) begin
            if (EX_injectNop) begin
                `DATAPATH_DEBUG_PRINT(
                    ("[Datapath]: @%0d Injecting NOP into MEM stage", DEBUG_tick));
                // exMemRegsQ.pc <= exMemRegsP.pc;
                exMemRegsQ.pc <= 32'h0;
                exMemRegsQ.ticket <= ROB_TICKET_INVALID;
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
                `DATAPATH_DEBUG_PRINT(
                    ("[Datapath]: @%0d EX->MEM forwarding (%0d -> %0d)", DEBUG_tick,
                    exMemRegsP.ticket, exMemRegsQ.ticket));
                exMemRegsQ <= exMemRegsP;
            end
        end else begin
            `DATAPATH_DEBUG_PRINT(
                ("[Datapath]: @%0d EX->MEM stage register stalled (%0d)", DEBUG_tick, exMemRegsQ.ticket));
        end
    end

    always_comb begin : StageControl
        // semantics of *Control.halt:
        // 1. the pipeline tells this stage to halt, i.e. don't change its state
        // 2. if later stage halts, previous stage must also halt

        // IF Control (IF is stateful, needs halting)
        ifControl.halt = idHints.shouldHalt || exHints.shouldHalt ||
                        memHints.shouldHalt || wbHints.shouldHalt;
        ifControl.WB_shouldJump = wbHints.WB_shouldJump;
        ifControl.WB_jumpPC = wbHints.WB_jumpPC;

        // ID Control (ID is stateful because of ROB ticket, needs halting)
        idControl.halt = exHints.shouldHalt || memHints.shouldHalt || wbHints.shouldHalt;
        idControl.WB_isWriteback = wbHints.WB_isWriteback;
        idControl.WB_rd = wbHints.WB_rd;
        idControl.WB_rdData = wbHints.WB_rdData;
        idControl.WB_hasException = wbHints.WB_hasException;
        idControl.WB_shouldJump = wbHints.WB_shouldJump;

        // EX Control
        // EX is not stateful
        exControl.placeholder = TRUE;

        // MEM Control
        // MEM is stateful
        memControl.ROB_commitTicket = robHints.commitTicket;
        memControl.ROB_commitIsStore = robHints.commitIsStore;
        memControl.ROB_commitStVirtAddr = robHints.commitStVirtAddr;
        memControl.ROB_commitStData = robHints.commitStData;
        memControl.ROB_commitStLen = robHints.commitStLen;
        memControl.ROB_commitStoreComplete = robHints.commitStComplete;

        // WB Control
        // WB is stateful
        wbControl.ROB_commitTicket = robHints.commitTicket;
        wbControl.ROB_commitException = robHints.commitExceptions;
        wbControl.ROB_commitIsWriteback = robHints.commitIsWriteback;
        wbControl.ROB_commitRd = robHints.commitRd;
        wbControl.ROB_commitRdData = robHints.commitRdData;
        wbControl.ROB_commitIsBranch = robHints.commitIsBranch;
        wbControl.ROB_commitShouldBranch = robHints.commitShouldBranch;
        wbControl.ROB_commitBranchPCVirtAddr = robHints.commitBranchPCVirtAddr;
        wbControl.IF_memRequestBusy = ifHints.IF_memRequestBusy;
        wbControl.MEM_memRequestBusy = memHints.MEM_memRequestBusy;

        // ROB Control
        robControl.WB_shouldJump = wbHints.WB_shouldJump;
        robControl.EX_ticket = exHints.EX_ticket;
        robControl.EX_isLoad = exHints.EX_isLoad;
        robControl.EX_isStore = exHints.EX_isStore;
        robControl.EX_isWriteback = exHints.EX_isWriteback;
        robControl.EX_isBranch = exHints.EX_isBranch;
        robControl.EX_aluResult = exHints.EX_aluResult;
        robControl.EX_branchPC = exHints.EX_branchPC;
        robControl.EX_shouldBranch = exHints.EX_shouldBranch;
        robControl.EX_exceptions = exHints.EX_exceptions;
        robControl.MEM_ticket = memHints.ticket;
        robControl.MEM_exceptions = memHints.MEM_exceptions;
        robControl.MEM_isLoad = memHints.MEM_pipeIsLoad;
        robControl.MEM_loadData = memHints.MEM_pipeLoadData;
        robControl.MEM_loadDataReady = memHints.MEM_pipeLoadDataReady;
        robControl.MEM_commitTicket = memHints.MEM_commitTicket;
        robControl.MEM_commitStoreComplete = memHints.MEM_commitStoreComplete;
        robControl.IMUL_ticket = imulHints.IMUL_resultTicket;
        robControl.IMUL_result = imulHints.IMUL_result;
        robControl.WB_commitTicket = wbHints.WB_commitTicket;
        robControl.WB_commitFinished = wbHints.WB_commitFinished;
    end


    always_comb begin : PipelineControl
        IfIdRegs_writeEnable = TRUE;
        IdExRegs_writeEnable = TRUE;
        ExMemRegs_writeEnable = TRUE;
        MemWbRegs_writeEnable = TRUE;
        IF_injectNop = FALSE;
        ID_injectNop = FALSE;
        EX_injectNop = FALSE;
        MEM_injectNop = FALSE;

        // semantics of *Hints.shouldHalt:
        // 1. don't send new instruction into this stage
        // 2. don't propogate the pipeline registers of this stage into the next stage
        //    -> The original pipeline registers are kept intacked
        if (ifHints.shouldHalt) begin
            IF_injectNop = TRUE;
        end

        if (idHints.shouldHalt) begin
            ID_injectNop = TRUE;
            IfIdRegs_writeEnable = FALSE;
        end

        if (exHints.shouldHalt) begin
            EX_injectNop = TRUE;
            IfIdRegs_writeEnable = FALSE;
            IdExRegs_writeEnable = FALSE;
        end

        if (memHints.shouldHalt) begin
            MEM_injectNop = TRUE;
            IfIdRegs_writeEnable = FALSE;
            IdExRegs_writeEnable = FALSE;
            ExMemRegs_writeEnable = FALSE;
        end

        // semantics of jump: kill everything before
        if (wbHints.WB_shouldJump) begin
            // kill all previous instructiosn
            IF_injectNop  = TRUE;
            ID_injectNop  = TRUE;
            EX_injectNop  = TRUE;
            MEM_injectNop = TRUE;
        end

    end

    word_t DEBUG_tick;
    always_ff @(posedge clk) begin
        DEBUG_tick <= DEBUG_tick + 1;
        if (ifHints.shouldHalt) begin
            `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d IF stage hint: Should Halt", DEBUG_tick));
        end else begin
            `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d IF stage hint: No need to Halt", DEBUG_tick));
        end
        if (idHints.shouldHalt) begin
            `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d ID stage hint: Should Halt", DEBUG_tick));
        end else begin
            `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d ID stage hint: No need to Halt", DEBUG_tick));
        end
        if (exHints.shouldHalt) begin
            `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d EX stage hint: Should Halt", DEBUG_tick));
        end else begin
            `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d EX stage hint: No need to Halt", DEBUG_tick));
        end
        if (memHints.shouldHalt) begin
            `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d MEM stage hint: Should Halt", DEBUG_tick));
        end else begin
            `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d MEM stage hint: No need to Halt", DEBUG_tick));
        end
        if (wbHints.shouldHalt) begin
            `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d WB stage hint: Should Halt", DEBUG_tick));
        end else begin
            `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d WB stage hint: No need to Halt", DEBUG_tick));
        end
        if (ifControl.halt) begin
            `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d IF stage !control!: Halt!", DEBUG_tick));
        end else begin
            `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d IF stage !control!: Go", DEBUG_tick));
        end
        if (idControl.halt) begin
            `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d ID stage !control!: Halt!", DEBUG_tick));
        end else begin
            `DATAPATH_DEBUG_PRINT(("[Datapath]: @%0d ID stage !control!: Go!", DEBUG_tick));
        end
    end


    word_t
        DEBUG_IF_haltHintCounter,
        DEBUG_ID_haltHintCounter,
        DEBUG_EX_haltHintCounter,
        DEBUG_MEM_haltHintCounter,
        DEBUG_WB_haltHintCounter;
    always_ff @(posedge clk) begin
        if (ifHints.shouldHalt) begin
            DEBUG_IF_haltHintCounter <= DEBUG_IF_haltHintCounter + 1;
        end
        if (idHints.shouldHalt) begin
            DEBUG_ID_haltHintCounter <= DEBUG_ID_haltHintCounter + 1;
        end
        if (exHints.shouldHalt) begin
            DEBUG_EX_haltHintCounter <= DEBUG_EX_haltHintCounter + 1;
        end
        if (memHints.shouldHalt) begin
            DEBUG_MEM_haltHintCounter <= DEBUG_MEM_haltHintCounter + 1;
        end
        if (wbHints.shouldHalt) begin
            DEBUG_WB_haltHintCounter <= DEBUG_WB_haltHintCounter + 1;
        end
    end

endmodule
