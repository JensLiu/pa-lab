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

    reg_t IF_pcQ;  // PC register
  
    initial begin
        IF_pcQ = START_ADDRESS;
        $display("Start executing at %h", IF_pcQ);
    end

    always_ff @(posedge clk) begin
        // TODO exception handling
        if (ifControl.halt) begin
            IF_pcQ <= IF_pcQ;
        end else if (ifControl.branchTaken) begin
            IF_pcQ <= ifControl.pcBr;
        end else begin
            IF_pcQ <= IF_pcQ + 4;
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
        ifIdRegs.pc   = IF_pcQ;
        ifIdRegs.inst = IF_inst;
        assert (cacheRequest.request);  // should always be true
        // TODO: redundent signal, kept for clarity
        // 1. exHints.shouldHalt = exControl.IF_cannotJump = ifHints.cannotJump = cacheRequest.ready
        // 2. ifHints.shouldHalt = cacheRequest.ready
        // 3. ifControl.halt = (...) || exHints.shouldHalt || ifHints.shouldHalt
        //                   = (...) || (cacheRequest.ready || cacheRequest.ready) <- redundent 
        ifHints.shouldHalt = !cacheRequest.ready;
        ifHints.cannotJump = !cacheRequest.ready;
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

endmodule
