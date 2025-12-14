import pkg_global_defs::*;

// NOTE: If we were using Virtual Addresses
//       we need identifier to distinguish between address spaces
// Solution: USE ASID (Address Space Identifier)
// Example:
// STORE a1 -> 0x100
// SWITCH ADDRESS SPACE OR PAGE REMAP
// LOAD  a2 <- 0x100
// assume 0x100 is still in the ROB, we should NOT bypass a1 to a2
module reorder_buffer (
    input logic clk,
    input rob_control_t robControl,
    output rob_hints_t robHints,
    rob_ticket_request_if.slave ticketRequest,  // ID stage
    rob_reg_query_if.slave regQuery,  // ID stage: register forwarding (currently no bypass here)
    rob_store_query_if.slave storeQuery  // MEM stage: CAM + forwarding
);

    localparam ROB_SIZE = 16;

    // NOTE:
    // In our implementation, Write ROB and Write Reg are two different phases
    // This introduces one cycle delay
    // t1: MEM stage
    // t2: Wr: Write ROB
    // t3: Wr: Write register

    typedef struct {  // TODO: use union and reuse some spaces
        bool_t entryValid;
        // store
        bool_t isStore;
        bool_t stVirtAddrValid;
        virt_addr_unique_t stVirtAddr;
        word_t stData;
        mem_stlen_t stLen;
        bool_t stComplete;
        // register
        bool_t isWriteback;
        reg_nr_t rd;
        bool_t rdDataValid;
        word_t rdData;
        // branch: This is added to simplify our flush logic
        bool_t isBranch;
        bool_t branchTaken;
        // exception
        word_t exceptions;
        word_t pc;
        // debug
        word_t DEBUG_ticketId;
        inst_info_t DEBUG_instInfo;
    } rob_entry_t;

    rob_entry_t buffer[ROB_SIZE];

    word_t oldest, nextYoungest;
    bool_t isFull;
    bool_t isEmpty;
    assign isEmpty = !isFull && oldest == nextYoungest;

    word_t currentTicket;


    always_comb begin : TicketResponse
        ticketRequest.ready  = FALSE;
        ticketRequest.ticket = IMM_32_WHATEVER;
        if (!isFull) begin
            ticketRequest.ready  = TRUE;
            ticketRequest.ticket = nextYoungest;
        end
    end

    always_ff @(posedge clk) begin : EnqueueLogic
        if (ticketRequest.request) begin
            if (!isFull) begin
                if (nextYoungest + 1 == ROB_SIZE) begin
                    nextYoungest <= 0;
                end else begin
                    nextYoungest <= nextYoungest + 1;
                end
                if (nextYoungest == oldest) begin
                    isFull <= TRUE;
                end
                buffer[nextYoungest].entryValid <= TRUE;
                // for store instructions
                buffer[nextYoungest].isStore <= ticketRequest.isStore;
                buffer[nextYoungest].stVirtAddrValid <= FALSE;
                buffer[nextYoungest].stData <= ticketRequest.stData;
                buffer[nextYoungest].stLen <= ticketRequest.stLen;
                buffer[nextYoungest].stComplete <= FALSE;
                // for writebacks
                buffer[nextYoungest].isWriteback <= ticketRequest.isWriteback;
                buffer[nextYoungest].rd <= ticketRequest.rd;
                buffer[nextYoungest].rdDataValid <= FALSE;
                // exceptions
                buffer[nextYoungest].exceptions <= '0;
                buffer[nextYoungest].pc <= ticketRequest.pc;
                // debug
                buffer[nextYoungest].DEBUG_ticketId <= nextYoungest;
                buffer[nextYoungest].DEBUG_instInfo <= ticketRequest.DEBUG_instInfo;
            end
        end
    end

    always_comb begin : Hints
        robHints.isEmpty = isEmpty;
        robHints.isFull = isFull;
        // Do we need bypass logic?
        // t1: MEM write data
        // t2: WB get data and notify
        // this is the correct behabiour
        robHints.oldestIsWriteback = buffer[oldest].isWriteback;
        robHints.oldestRdDataValid = buffer[oldest].rdDataValid;
        robHints.oldestRdData = buffer[oldest].rdData;
        robHints.oldestIsStore = buffer[oldest].isStore;
        robHints.oldestStVirtAddr = buffer[oldest].stVirtAddr;
        robHints.oldestStVirtAddrValid = buffer[oldest].stVirtAddrValid;
        robHints.oldestStData = buffer[oldest].stData;
        robHints.oldestStLen = buffer[oldest].stLen;
        robHints.oldestStComplete = buffer[oldest].stComplete;
    end

    always_ff @(posedge clk) begin : DequeueLogic
        if (robHints.oldestIsWriteback || (robHints.oldestIsStore && robHints.oldestStComplete)) begin
            if (oldest + 1 == ROB_SIZE) begin
                oldest <= 0;
            end else begin
                oldest <= oldest + 1;
            end
            buffer[oldest].entryValid <= FALSE;
            isFull <= FALSE;
        end
    end

    // this logic is expensive, perhaps seralise update requests (slower performance)?
    bool_t EX_isRegBypassing, MEM_isStoreBypassing, MEM_isLoadBypassing, IMUL_isRegBypassing;
    always @(posedge clk) begin : UpdateLogic
        // Each stage should have different tickets
        assert (robControl.EX_ticket != robControl.MEM_ticket);
        assert (robControl.EX_ticket != robControl.IMUL_ticket);
        assert (robControl.MEM_ticket != robControl.IMUL_ticket);
        // ticket range checks and entry valid checks
        assert (robControl.EX_ticket < ROB_SIZE);
        assert (robControl.MEM_ticket < ROB_SIZE);
        assert (robControl.IMUL_ticket < ROB_SIZE);
        assert (buffer[robControl.EX_ticket].entryValid &&
                buffer[robControl.MEM_ticket].entryValid &&
                buffer[robControl.IMUL_ticket].entryValid);

        // EX: ALU update
        if (!robControl.EX_isLoad && !robControl.EX_isStore) begin
            // not memory instructions -> ALU Result is rd data (not an address)
            // otherwise, they are virtual addresses, however we only want physical addresses
            assert (buffer[robControl.EX_ticket].isWriteback);
            buffer[robControl.EX_ticket].rdData <= robControl.EX_aluResult;
            buffer[robControl.EX_ticket].rdDataValid <= robControl.EX_aluResultValid;
            buffer[robControl.EX_ticket].branchTaken <= robControl.EX_branchTaken;
            if (!robControl.EX_isBranch) begin
                EX_isRegBypassing = robControl.EX_aluResultValid;
            end
        end

        // MEM update
        if (robControl.MEM_isStore) begin  // < STORE enters the MEM stage
            // MEM update: STORE
            buffer[robControl.MEM_ticket].stVirtAddr <= robControl.MEM_virtAddr;
            buffer[robControl.MEM_ticket].stVirtAddrValid <= TRUE;
            assert (!buffer[robControl.MEM_ticket].stComplete);
            buffer[robControl.MEM_ticket].stData <= robControl.MEM_storeData;
            buffer[robControl.MEM_ticket].stLen  <= robControl.MEM_storeLen;
            MEM_isStoreBypassing = TRUE;
        end else if (robControl.MEM_isLoad) begin  // < LOAD enters the MEM stage
            // MEM update: LOAD
            assert (buffer[robControl.MEM_ticket].isWriteback);
            buffer[robControl.MEM_ticket].rdDataValid <= robControl.MEM_loadResultReady;
            buffer[robControl.MEM_ticket].rdData <= robControl.MEM_loadResult;
            MEM_isLoadBypassing = robControl.MEM_loadResultReady;
        end else begin  // < register-register instructions or branches, ignore
            assert (buffer[robControl.MEM_ticket].isWriteback ||
                    buffer[robControl.MEM_ticket].isBranch);
        end

        // IMUL update
        assert (buffer[robControl.IMUL_ticket].isWriteback);
        buffer[robControl.IMUL_ticket].rdData <= robControl.IMUL_result;
        buffer[robControl.IMUL_ticket].rdDataValid <= robControl.IMUL_resultValid;
        IMUL_isRegBypassing = robControl.IMUL_resultValid;
    end

    // youngest in ROB (no bypass)
    bool_t _rs1EntryFound, _rs2EntryFound;
    word_t _rs1EntryIndex, _rs2EntryIndex;
    always_comb begin : RegQueryLogic  // this logic is very expensive
        _rs1EntryFound = FALSE;
        _rs2EntryFound = FALSE;
        _rs1EntryIndex = IMM_32_WHATEVER;
        _rs2EntryIndex = IMM_32_WHATEVER;
        regQuery.rs1HasEntry = FALSE;
        regQuery.rs1Data = IMM_32_WHATEVER;
        regQuery.rs1DataValid = FALSE;
        regQuery.rs2HasEntry = FALSE;
        regQuery.rs2Data = IMM_32_WHATEVER;
        regQuery.rs2DataValid = FALSE;

        for (int i = nextYoungest; i < ROB_SIZE; i++) begin
            automatic int index = (nextYoungest - i) % ROB_SIZE;
            if (buffer[index].entryValid && buffer[index].isWriteback) begin
                if (buffer[index].rd == regQuery.rs1) begin
                    _rs1EntryFound = TRUE;
                    _rs1EntryIndex = index;
                end
                if (buffer[index].rd == regQuery.rs2) begin
                    _rs2EntryFound = TRUE;
                    _rs2EntryIndex = index;
                end
            end
        end

        // check if we have bypasses that has newer version
        if (_rs1EntryFound) begin
            regQuery.rs1Data = buffer[_rs1EntryIndex].rdData;
            regQuery.rs1DataValid = buffer[_rs1EntryIndex].rdDataValid;
            regQuery.rs1HasEntry = TRUE;
            if (robControl.EX_ticket == _rs1EntryIndex) begin
                if (EX_isRegBypassing) begin
                    regQuery.rs1Data = robControl.EX_aluResult;
                    regQuery.rs1DataValid = robControl.EX_aluResultValid;
                    assert (robControl.EX_aluResultValid);
                    assert (!buffer[_rs1EntryIndex].rdDataValid);
                end
            end else if (robControl.MEM_ticket == _rs1EntryIndex) begin
                if (MEM_isLoadBypassing) begin
                    regQuery.rs1Data = robControl.MEM_loadResult;
                    regQuery.rs1DataValid = robControl.MEM_loadResultReady;
                    assert (!buffer[_rs1EntryIndex].rdDataValid);
                end
            end else if (robControl.IMUL_ticket == _rs1EntryIndex) begin
                if (IMUL_isRegBypassing) begin
                    regQuery.rs1Data = robControl.IMUL_result;
                    regQuery.rs1DataValid = robControl.IMUL_resultValid;
                    assert (!buffer[_rs1EntryIndex].rdDataValid);
                end
            end
        end

        // same as rs1
        if (_rs2EntryFound) begin
            regQuery.rs2Data = buffer[_rs2EntryIndex].rdData;
            regQuery.rs2DataValid = buffer[_rs2EntryIndex].rdDataValid;
            regQuery.rs2HasEntry = TRUE;
            if (robControl.EX_ticket == _rs2EntryIndex) begin
                if (EX_isRegBypassing) begin
                    regQuery.rs2Data = robControl.EX_aluResult;
                    regQuery.rs2DataValid = robControl.EX_aluResultValid;
                    assert (robControl.EX_aluResultValid);
                    assert (!buffer[_rs2EntryIndex].rdDataValid);
                end
            end else if (robControl.MEM_ticket == _rs2EntryIndex) begin
                if (MEM_isLoadBypassing) begin
                    regQuery.rs2Data = robControl.MEM_loadResult;
                    regQuery.rs2DataValid = robControl.MEM_loadResultReady;
                    assert (!buffer[_rs2EntryIndex].rdDataValid);
                end
            end else if (robControl.IMUL_ticket == _rs2EntryIndex) begin
                if (IMUL_isRegBypassing) begin
                    regQuery.rs2Data = robControl.IMUL_result;
                    regQuery.rs2DataValid = robControl.IMUL_resultValid;
                    assert (!buffer[_rs2EntryIndex].rdDataValid);
                end
            end
        end

    end


    bool_t _stEntryFound;
    word_t _stEntryIdx;
    always_comb begin : StoreQueryLogic
        _stEntryFound = TRUE;
        _stEntryIdx = IMM_32_WHATEVER;
        storeQuery.hasEntry = FALSE;
        storeQuery.data = IMM_32_WHATEVER;
        storeQuery.dataLen = MEM_STLEN_INVALID;
        for (int i = nextYoungest; i < ROB_SIZE; i++) begin
            automatic int index = (nextYoungest - i) % ROB_SIZE;
            if (buffer[index].entryValid && buffer[index].isStore) begin
                if (buffer[index].stVirtAddrValid &&
                    buffer[index].stVirtAddr == storeQuery.virtAddr) begin
                    _stEntryFound = TRUE;
                    _stEntryIdx   = index;
                end
            end
        end

        // check for bypasses
        if (_stEntryFound) begin
            storeQuery.hasEntry = TRUE;
            storeQuery.data = buffer[_stEntryIdx].stData;
            storeQuery.dataLen = buffer[_stEntryIdx].stLen;
            if (robControl.MEM_ticket == _stEntryIdx) begin
                if (MEM_isStoreBypassing) begin
                    storeQuery.data = robControl.MEM_storeData;
                    storeQuery.dataLen = robControl.MEM_storeLen;
                end
            end
        end

    end

    // if we have
    // - a LD already executing on MEM stage (perhaps cache miss), and
    // - a ST just became the oldest instruction
    // we wait for the LD to finish, then stall the pipeline to allow ST to continue

endmodule
