`timescale 1ps / 1ps
`include "rtl_common.svh"

module if_stage
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;
    import pkg_virtual_memory::*;
(
`ifdef INSTRUCTION_MEMORY_EXPOSE_INTERNALS
    output byte_t                  DEBUG_mem   [INST_MEM_SIZE],
`endif
    input  clk_t                   clk,
    input  if_control_t            ifControl,
    output if_id_regs_t            ifIdRegs,
    output if_hints_t              ifHints,
    // interface to the external cache
    cache_request_if.master cacheRequest
`ifdef INSTRUCTION_CACHE_DIVERGENCE_TEST
    // debug interface to compare with direct memory access
    ,cache_request_if.master DEBUG_instMemRequest
`endif
);

    // Bug Hunt: Confusing Response
    // ALU:     "let's jump"
    // IF:      "Sure, let's fetch from the new PC"
    //          "Cache, I changed my mind, give me the new PC"
    // CACHE:   "Sorry, didn't hear you"
    //          ...
    //          "here is the instruction at your previous PC"
    //          "I'm not telling you it's the old one"
    //          "bacause you didn't let me finish your previous request"
    // IF:      "WTF"

    // Temporary Fix: Halt when IF is draining
    // ALU:     "I want to jump. IF, can we jump?"
    // IF:      "Not yet, I am waiting for my cache response"
    // ALU:     "Eveybody, wait"
    // CACHE:   "Done"
    // IF:      "I am ready"
    // ALU:     "Let's jump"

    typedef enum logic [1:0] {
        SEQUENTIAL,
        BRANCH_WAIT
    } state_t;

    state_t currentState, nextState;

    reg_t jumpPC;
    reg_t IF_pcQ;  // PC register
  
    initial begin
        IF_pcQ = START_ADDRESS;
        currentState = SEQUENTIAL;
        $display("Start executing at %h", IF_pcQ);
    end

    always_comb begin
        nextState = currentState;
        case (currentState)
            SEQUENTIAL: begin
                if (ifControl.WB_shouldJump && !cacheRequest.ready) begin
                    `IF_STAGE_DEBUG_PRINT((
                        "[IF]: @%0d received jump while requesting memory, transition to BRANCH_WAIT",
                        DEBUG_tick));
                    nextState = BRANCH_WAIT;
                end
            end
            BRANCH_WAIT: begin
                if (cacheRequest.ready) begin
                    `IF_STAGE_DEBUG_PRINT((
                        "[IF]: @%0d memory request finished, resuming branch",
                        DEBUG_tick));
                    nextState = SEQUENTIAL;
                end
            end
            default: begin
                assert (FALSE);
            end
        endcase
    end
    always_ff @(posedge clk) begin
        currentState <= nextState;
    end

    always_ff @(posedge clk) begin
        `IF_STAGE_DEBUG_PRINT((
            "[IF]: @%0d halt=%0b, cacheReady=%0b, WB_jumpPC=%0h, WB_shouldJump=%0b",
            DEBUG_tick, ifControl.halt, cacheRequest.ready, ifControl.WB_jumpPC, ifControl.WB_shouldJump));
        if (currentState == BRANCH_WAIT) begin
            `IF_STAGE_DEBUG_PRINT(("[IF]: @%0d In BRANCH_WAIT state", DEBUG_tick));
        end else begin
            `IF_STAGE_DEBUG_PRINT(("[IF]: @%0d In SEQUENTIAL state", DEBUG_tick));
        end
        if (currentState == SEQUENTIAL && nextState == SEQUENTIAL) begin
            if (ifControl.WB_shouldJump && cacheRequest.ready) begin
                IF_pcQ <= ifControl.WB_jumpPC;
            end else if (ifControl.halt || !cacheRequest.ready) begin
                `IF_STAGE_DEBUG_PRINT(("[IF]: @%0d Halting, keeping PC at %h", DEBUG_tick, IF_pcQ));
                IF_pcQ <= IF_pcQ;
            end else begin
                `IF_STAGE_DEBUG_PRINT((
                    "[IF]: @%0d Advancing PC from %h to %h",
                    DEBUG_tick,
                    IF_pcQ,
                    IF_pcQ + 4));
                IF_pcQ <= IF_pcQ + 4;
            end
        end else if (currentState == SEQUENTIAL && nextState == BRANCH_WAIT) begin
            `IF_STAGE_DEBUG_PRINT((
                "[IF]: @%0d transition to BRANCH_WAIT, saving jumpPC=%0h",
                DEBUG_tick, ifControl.WB_jumpPC));
            jumpPC <= ifControl.WB_jumpPC;
        end else if (currentState == BRANCH_WAIT && nextState == SEQUENTIAL) begin
            `IF_STAGE_DEBUG_PRINT((
                "[IF]: @%0d transition to SEQUENTIAL, restoring jumpPC=%0h",
                DEBUG_tick, ifControl.WB_jumpPC));
            IF_pcQ <= jumpPC;
        end
    end
    
    mmu i_mmu (
        .clk(clk),
        .reset(1'b0),  // no reset in this stage
        .satp(0),  // no virtual memory in this stage
        .virtual_addr(IF_pcQ),
        .access_type(ACCESS_EXECUTE), // instruction fetch
        .physical_addr(),  // not used in this stage
        .req_o(),  // request to cache
        .we_o(),  // write enable for cache
        .stall(),  // stop pipeline
        .exception_o(),  // page fault or other exception
        .cause_o()  // exception cause
    );

    instruction_t IF_inst;
    always_comb begin : CacheRequestLogic
        IF_inst = cacheRequest.dataFromCache;
        cacheRequest.addr = IF_pcQ;  // stable, it is flopped
        cacheRequest.isRead = TRUE;
        cacheRequest.request = TRUE;
        cacheRequest.dataLen = MEM_STLEN_WORD;
        `IF_STAGE_DEBUG_PRINT(
            ("[IF]: @%0d Requesting instruction at PA %h",
                                      DEBUG_tick,
                              cacheRequest.addr));
`ifdef INSTRUCTION_CACHE_DIVERGENCE_TEST
        DEBUG_instMemRequest.addr = cacheRequest.addr;
        DEBUG_instMemRequest.isRead = cacheRequest.isRead;
        DEBUG_instMemRequest.request = cacheRequest.request;
        DEBUG_instMemRequest.dataLen = MEM_STLEN_WORD;
        assert (DEBUG_instMemRequest.ready);
`endif
    end

`ifdef INSTRUCTION_CACHE_DIVERGENCE_TEST
    always_comb begin: DivergenceTest
        if (cacheRequest.ready) begin
            assert (cacheRequest.dataFromCache == DEBUG_instMemRequest.dataFromCache);
        end
    end
`endif

    always_comb begin
        if (cacheRequest.ready) begin
            `IF_STAGE_DEBUG_PRINT(
                ("[IF]: @%0d Fetched instruction %h from PA %h",
                                          DEBUG_tick,
                                  IF_inst,
                                  IF_pcQ));
            if (ifControl.WB_shouldJump) begin
            end
        end
        `IF_STAGE_DEBUG_PRINT(("[IF]: @%0d instValid=%0b", DEBUG_tick, cacheRequest.ready));
        ifIdRegs.instValid = cacheRequest.ready;
        ifIdRegs.pc   = IF_pcQ;
        ifIdRegs.inst = IF_inst;
        assert (cacheRequest.request);  // should always be true
        // TODO: redundent signal, kept for clarity
        // 1. exHints.shouldHalt = exControl.IF_cannotJump = ifHints.cannotJump = cacheRequest.ready
        // 2. ifHints.shouldHalt = cacheRequest.ready
        // 3. ifControl.halt = (...) || exHints.shouldHalt || ifHints.shouldHalt
        //                   = (...) || (cacheRequest.ready || cacheRequest.ready) <- redundent 
        ifHints.shouldHalt = !cacheRequest.ready;
        ifHints.IF_memRequestBusy = !cacheRequest.ready;
`ifdef DEBUG_INST_INFO_EXTENSION
        ifIdRegs.DEBUG_instID = DEBUG_nextInstID;
`endif
    end

`ifdef DEBUG_INST_INFO_EXTENSION
    word_t DEBUG_nextInstID;
    initial DEBUG_nextInstID = 0;
    always_ff @(posedge clk) begin
        if (!ifControl.halt) begin
            DEBUG_nextInstID <= DEBUG_nextInstID + 1;
        end
    end
`endif

    logic [31:0] DEBUG_tick;
    always_ff @(posedge clk) begin
        DEBUG_tick <= DEBUG_tick + 1;
    end

endmodule
