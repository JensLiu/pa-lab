import pkg_global_defs::*;

// `define ROB_STORE_QUERY_DEBUG_PRINT_EN
// `define ROB_REG_QUERY_DEBUG_PRINT_EN

module reorder_buffer (
    input logic clk,
    input rob_control_t robControl,
    output rob_hints_t robHints,
    rob_ticket_request_if.slave ticketRequest,  // ID stage
    rob_reg_query_if.slave regQuery,  // ID stage: register forwarding (currently no bypass here)
    rob_store_query_if.slave storeQuery  // MEM stage: CAM + forwarding
);

    localparam ROB_SIZE = 16;

    bool_t ROB_reset;
    assign ROB_reset = FALSE;  // TODO: reset

    // NOTE:
    // In our implementation, Write ROB and Write Reg are two different phases
    // This introduces one cycle delay
    // t1: MEM stage
    // t2: Wr: Write ROB
    // t3: Wr: Write register

    typedef struct {  // TODO: use union and reuse some spaces
        bool_t entryValid;  // if asserted, this entry is active
        // store
        // NOTE: If we were using Virtual Addresses
        //       we need identifier to distinguish between address spaces
        // Solution: USE ASID (Address Space Identifier)
        // Example:
        // STORE a1 -> 0x100
        // SWITCH ADDRESS SPACE OR PAGE REMAP
        // LOAD  a2 <- 0x100
        // assume 0x100 is still in the ROB, we should NOT bypass a1 to a2
        bool_t isStore;
        bool_t stVirtAddrValid;  // we only know the virtual address in MEM stage
        virt_addr_unique_t stVirtAddr;
        word_t stData;
        mem_stlen_t stLen;
        bool_t stComplete;  // only write to cache when it is the oldest instruction, block retire until write complete
        // register
        bool_t isWriteback;
        reg_nr_t rd;
        bool_t rdDataValid;  // we only know the data in EX (ALU), MEM (LOAD) or IMUL stage
        word_t rdData;
        // branch: This is added to simplify our flush logic?
        bool_t isBranch;
        bool_t shouldBranch;
        // exception
        exception_t exceptions;
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
        ticketRequest.ticket = ROB_TICKET_INVALID;  // default invalid
        if (!isFull && ticketRequest.request) begin
            ticketRequest.ready  = TRUE;
            ticketRequest.ticket = nextYoungest;
            if (ticketRequest.request) begin
                `ROB_DEBUG_PRINT(
                    ("[ROB]: @%0d: ROB Ticket Requested: Assigned Ticket %0d", DEBUG_tick, nextYoungest));
            end
        end
        if (isFull && ticketRequest.request) begin
            `ROB_DEBUG_PRINT(("[ROB]: @%0d: ROB Ticket Requested but ROB is Full", DEBUG_tick));
        end
    end

    always_ff @(posedge clk) begin : EnqueueLogic
        if (ROB_reset) begin
            nextYoungest <= 0;
            isFull <= FALSE;
            for (int i = 0; i < ROB_SIZE; i++) begin
                buffer[i].entryValid <= FALSE;
            end
        end else if (ticketRequest.request) begin
            if (!isFull) begin
                `ROB_DEBUG_PRINT(
                    ("[ROB]: @%0d: ROB Ticket %0d Enqueue Requested", DEBUG_tick, nextYoungest));
                if (nextYoungest + 1 == ROB_SIZE) begin
                    `ROB_DEBUG_PRINT(("[ROB]: @%0d: ROB nextYoungest wrap around", DEBUG_tick));
                    nextYoungest <= 0;
                end else begin
                    nextYoungest <= nextYoungest + 1;
                end

                if (nextYoungest < oldest && nextYoungest + 1 == oldest ||
                    nextYoungest >  oldest && nextYoungest + 1 - ROB_SIZE == oldest) begin
                    `ROB_DEBUG_PRINT(("[ROB]: @%0d: ROB is now Full after Enqueue", DEBUG_tick));
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
                // for branches
                buffer[nextYoungest].isBranch <= ticketRequest.isBranch;
                buffer[nextYoungest].shouldBranch <= FALSE;
                // exceptions
                buffer[nextYoungest].exceptions <= '0;
                buffer[nextYoungest].pc <= ticketRequest.pc;
                // debug
                buffer[nextYoungest].DEBUG_ticketId <= nextYoungest;
                buffer[nextYoungest].DEBUG_instInfo <= ticketRequest.DEBUG_instInfo;
                `ROB_DEBUG_PRINT(
                    (
                        "[ROB]: @%0d: ROB Enqueued Entry %0d: PC=%h, isStore=%0b, isWriteback=%0b, rd=%0d, inst=%h",
                        DEBUG_tick,
                        nextYoungest,
                        ticketRequest.pc,
                        ticketRequest.isStore,
                        ticketRequest.isWriteback,
                        ticketRequest.rd,
                        ticketRequest.DEBUG_instInfo.DEBUG_instBinary
                ));
            end
        end
    end

    always_comb begin : Hints
        robHints.isEmpty = isEmpty;
        robHints.isFull = isFull;
        robHints.DEBUG_commitTicket = buffer[oldest].DEBUG_ticketId;
        robHints.commitEntryValid = buffer[oldest].entryValid;
        robHints.commitExceptions = buffer[oldest].exceptions;
        robHints.commitPC = buffer[oldest].pc;
        // for regiester writeback commit
        robHints.commitIsWriteback = buffer[oldest].isWriteback;
        robHints.commitRd = buffer[oldest].rd;
        robHints.commitRdDataValid = buffer[oldest].rdDataValid;
        robHints.commitRdData = buffer[oldest].rdData;
        // for store commit
        robHints.commitIsStore = buffer[oldest].isStore;
        robHints.commitStVirtAddr = buffer[oldest].stVirtAddr;
        robHints.commitStVirtAddrValid = buffer[oldest].stVirtAddrValid;
        robHints.commitStData = buffer[oldest].stData;
        robHints.commitStLen = buffer[oldest].stLen;
        robHints.commitStComplete = buffer[oldest].stComplete;
        // for branch commit
        robHints.commitIsBranch = buffer[oldest].isBranch;
        robHints.commitShouldBranch = buffer[oldest].shouldBranch;
    end

    bool_t _shouldDequeue;
    always @(posedge clk) begin : DequeueLogic
        // `ROB_DEBUG_PRINT(
        //     ("[ROB]: @%0d: Dequeue Logic Check: isEmpty=%0b, isFull=%0b, oldest=%0d, oldestIsWriteback=%0b, oldestRdDataValid=%0b, oldestIsStore=%0b, oldestStComplete=%0b",
        //  DEBUG_tick, isEmpty, isFull, oldest, robHints.commitIsWriteback, robHints.commitRdDataValid, robHints.commitIsStore, robHints.commitStComplete));
        _shouldDequeue = FALSE;
        if (ROB_reset) begin
            oldest <= 0;
        end else if (!isEmpty) begin
            if (robHints.commitIsWriteback) begin
                // only dequeue when WB stage is acceping commits (to avoid losing instructions)
                if (robControl.WB_acceptCommit && robHints.commitRdDataValid) begin
                    _shouldDequeue = TRUE;
                    `ROB_DEBUG_PRINT(
                        ("[ROB]: @%0d: ROB Ticket %0d Dequeue for Writeback (rd=%0d, data=%h)",
                                 DEBUG_tick, oldest,
                                 buffer[oldest].rd,
                                 buffer[oldest].rdData));
                end
            end else if (robHints.commitIsStore) begin
                // only dequeue when MEM stage is acceping commits (to avoid losing instructions)
                // TODO: dequeue when store is complete (from the control signals)
                if (robHints.commitStComplete) begin
                    _shouldDequeue = TRUE;
                    `ROB_DEBUG_PRINT(
                        ("[ROB]: @%0d: ROB Ticket %0d Dequeue for Store (addr=%h, len=%0d, data=%h)",
                                 DEBUG_tick, oldest,
                                 buffer[oldest].stVirtAddr.va,
                                 buffer[oldest].stLen,
                                 buffer[oldest].stData));
                end
            end

            if (_shouldDequeue) begin
                if (oldest + 1 == ROB_SIZE) begin
                    oldest <= 0;
                end else begin
                    oldest <= oldest + 1;
                end
                buffer[oldest].entryValid <= FALSE;
                isFull <= FALSE;
            end
        end
    end

    // this logic is expensive, perhaps seralise update requests (slower performance)?
    bool_t EX_isRegBypassing, EX_isStoreBypassing, MEM_isLoadBypassing, IMUL_isRegBypassing;
    always @(posedge clk) begin : UpdateLogic
        EX_isRegBypassing   = FALSE;
        EX_isStoreBypassing = FALSE;
        MEM_isLoadBypassing = FALSE;
        IMUL_isRegBypassing = FALSE;

        // Each stage should have different tickets if they are valid
        if (robControl.EX_ticket != ROB_TICKET_INVALID &&
            robControl.MEM_ticket != ROB_TICKET_INVALID) begin
            $display("[ROB]: @%0d: EX_ticket=%0d, MEM_ticket=%0d", DEBUG_tick,
                     robControl.EX_ticket, robControl.MEM_ticket);
            assert (robControl.EX_ticket != robControl.MEM_ticket);
        end
        if (robControl.EX_ticket != ROB_TICKET_INVALID &&
            robControl.IMUL_ticket != ROB_TICKET_INVALID) begin
            assert (robControl.EX_ticket != robControl.IMUL_ticket);
        end
        if (robControl.MEM_ticket != ROB_TICKET_INVALID &&
            robControl.IMUL_ticket != ROB_TICKET_INVALID) begin
            assert (robControl.MEM_ticket != robControl.IMUL_ticket);
        end
        // ticket range checks and entry valid checks
        if (robControl.EX_ticket != ROB_TICKET_INVALID) begin
            `ROB_DEBUG_PRINT(
                ("[ROB]: @%0d: EX_ticket=%0d, valid=%0d", DEBUG_tick, robControl.EX_ticket, 
                buffer[robControl.EX_ticket].entryValid));
            assert (robControl.EX_ticket < ROB_SIZE);
            assert (buffer[robControl.EX_ticket].entryValid);
        end
        if (robControl.MEM_ticket != ROB_TICKET_INVALID) begin
            `ROB_DEBUG_PRINT(("[ROB]: @%0d: MEM_ticket=%0d", DEBUG_tick, robControl.MEM_ticket));
            assert (robControl.MEM_ticket < ROB_SIZE);
            assert (buffer[robControl.MEM_ticket].entryValid);
        end
        if (robControl.IMUL_ticket != ROB_TICKET_INVALID) begin
            $display("[ROB]: @%0d: IMUL_ticket = %0d", DEBUG_tick, robControl.IMUL_ticket);
            assert (robControl.IMUL_ticket < ROB_SIZE);
            assert (buffer[robControl.IMUL_ticket].entryValid);
        end

        // EX: ALU update
        if (robControl.EX_ticket != ROB_TICKET_INVALID) begin
            `ROB_DEBUG_PRINT(
                ("[ROB]: @%0d: EX Stage Update for ROB Ticket %0d", DEBUG_tick, robControl.EX_ticket));
            assert (buffer[robControl.EX_ticket].entryValid);
            if (!robControl.EX_isLoad && !robControl.EX_isStore) begin
                // not memory instructions -> ALU Result is rd data (not an address)
                // otherwise, they are virtual addresses, however we only want physical addresses
                if (robControl.EX_isBranch) begin
                    buffer[robControl.EX_ticket].shouldBranch <= robControl.EX_shouldBranch;
                end else if (buffer[robControl.EX_ticket].isWriteback) begin
                    buffer[robControl.EX_ticket].rdData <= robControl.EX_aluResult;
                    buffer[robControl.EX_ticket].rdDataValid <= TRUE;
                    buffer[robControl.EX_ticket].exceptions <= robControl.EX_exceptions;
                    EX_isRegBypassing = TRUE;
                end else begin
                    assert (buffer[robControl.EX_ticket].DEBUG_instInfo.DEBUG_instBinary == '0);
                end
                `ROB_DEBUG_PRINT(
                    ("[ROB]: @%0d: EX Stage ALU Update for ROB Ticket %0d: rdData=%h",
                     DEBUG_tick, robControl.EX_ticket,
                     robControl.EX_aluResult));
            end else if (robControl.EX_isStore) begin  // < STORE enters the MEM stage
                // EX update: STORE address calculation
                `ROB_DEBUG_PRINT(
                    ("[ROB]: @%0d: EX Stage STORE Update for ROB Ticket %0d: stVirtAddr=%h",
                     DEBUG_tick, robControl.EX_ticket,
                     robControl.EX_aluResult));
                // TODO: use ASID
                buffer[robControl.EX_ticket].stVirtAddr <= {9'b0, robControl.EX_aluResult};
                buffer[robControl.EX_ticket].stVirtAddrValid <= TRUE;
                buffer[robControl.EX_ticket].exceptions <= robControl.EX_exceptions;
                EX_isStoreBypassing = TRUE;
            end
        end

        // MEM update
        if (robControl.MEM_ticket != ROB_TICKET_INVALID) begin
            `ROB_DEBUG_PRINT(
                ("[ROB]: @%0d: MEM Stage Update for ROB Ticket %0d, MEM_isLoad=%0b",
                DEBUG_tick, robControl.MEM_ticket, robControl.MEM_isLoad));
            assert (buffer[robControl.MEM_ticket].entryValid);
            if (robControl.MEM_isLoad) begin  // < LOAD enters the MEM stage
                assert (!robControl.MEM_isCommitStore);
                `ROB_DEBUG_PRINT(
                    ("[ROB]: @%0d: MEM Stage LOAD Update for ROB Ticket %0d", DEBUG_tick, robControl.MEM_ticket));
                // MEM update: LOAD
                assert (buffer[robControl.MEM_ticket].isWriteback);
                buffer[robControl.MEM_ticket].rdDataValid <= robControl.MEM_loadDataReady;
                buffer[robControl.MEM_ticket].rdData <= robControl.MEM_loadData;
                MEM_isLoadBypassing = robControl.MEM_loadDataReady;
            end else if (robControl.MEM_isCommitStore) begin
                assert (!robControl.MEM_isLoad);
                // MEM update: commit STORE
                // TODO: debug print
                buffer[robControl.MEM_ticket].stComplete <= robControl.MEM_commitStoreComplete;
                buffer[robControl.MEM_ticket].exceptions <= robControl.MEM_exceptions;
            end else begin  // < register-register instructions or branches, ignore
                // `ROB_DEBUG_PRINT(
                //     ("[ROB]: @%0d: MEM Stage Non-Mem Instruction Update for ROB Ticket %0d", DEBUG_tick, robControl.MEM_ticket));
                assert (buffer[robControl.MEM_ticket].isWriteback ||
                    buffer[robControl.MEM_ticket].isBranch ||
                    buffer[robControl.MEM_ticket].DEBUG_instInfo.DEBUG_instBinary == '0);
            end
        end

        // IMUL update
        if (robControl.IMUL_ticket != ROB_TICKET_INVALID) begin
            assert (buffer[robControl.IMUL_ticket].entryValid);
            assert (buffer[robControl.IMUL_ticket].isWriteback);
            buffer[robControl.IMUL_ticket].rdData <= robControl.IMUL_result;
            buffer[robControl.IMUL_ticket].rdDataValid <= TRUE;
            IMUL_isRegBypassing = TRUE;
        end
    end

    // youngest in ROB (no bypass)
    bool_t _rs1EntryFound, _rs2EntryFound;
    word_t _rs1EntryIndex, _rs2EntryIndex;
    always_comb begin : RegQueryLogic  // this logic is very expensive
        // Assumption: the register query interface is only used in ID stage

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
`ifdef ROB_REG_QUERY_DEBUG_PRINT_EN
        `ROB_DEBUG_PRINT(
            ("[ROB]: @%0d: RegQuery rs1=%0d, rs2=%0d", DEBUG_tick, regQuery.rs1, regQuery.rs2));
`endif
        for (int i = 0; i < ROB_SIZE; i++) begin
            // start from the oldest to the youngest, iterate through the ROB
            // we do NOT use `break` so the latest entry always overrides previous ones
            automatic int index = (oldest + i + ROB_SIZE) % ROB_SIZE;
            if (buffer[index].entryValid)
                `ROB_DEBUG_PRINT(
                    ("[ROB]: @%0d: RegQuery Checking %0d, %0d ROB Entry %0d: rd=%0d, isWriteback=%0b, isEntryValid=%0b",
                     DEBUG_tick, regQuery.rs1, regQuery.rs2, index, buffer[index].rd, buffer[index].isWriteback, buffer[index].entryValid));
            if (buffer[index].entryValid && buffer[index].isWriteback) begin
                if (buffer[index].rd == regQuery.rs1) begin
`ifdef ROB_REG_QUERY_DEBUG_PRINT_EN
                    `ROB_DEBUG_PRINT(
                        ("[ROB]: @%0d: RegQuery rs1 Match at ROB Entry %0d: rd=%0d",
                         DEBUG_tick, index, buffer[index].rd));
`endif
                    _rs1EntryFound = TRUE;
                    _rs1EntryIndex = index;
                end
                if (buffer[index].rd == regQuery.rs2) begin
`ifdef ROB_REG_QUERY_DEBUG_PRINT_EN
                    `ROB_DEBUG_PRINT(
                        ("[ROB]: @%0d: RegQuery rs2 Match at ROB Entry %0d: rd=%0d",
                         DEBUG_tick, index, buffer[index].rd));
`endif
                    _rs2EntryFound = TRUE;
                    _rs2EntryIndex = index;
                end
            end
        end

        // check if we have bypasses that has newer version
        if (_rs1EntryFound) begin
            // `ifdef ROB_REG_QUERY_DEBUG_PRINT_EN
            //             `ROB_DEBUG_PRINT(
            //                 ("[ROB]: @%0d: RegQuery rs1 Hit at ROB Entry %0d: rd=%0d, data=%h, dataValid=%0b",
            //                  DEBUG_tick, _rs1EntryIndex, buffer[_rs1EntryIndex].rd,
            //                  buffer[_rs1EntryIndex].rdData, buffer[_rs1EntryIndex].rdDataValid));
            // `endif
            regQuery.rs1Data = buffer[_rs1EntryIndex].rdData;
            regQuery.rs1DataValid = buffer[_rs1EntryIndex].rdDataValid;
            regQuery.rs1HasEntry = TRUE;
            // TODO: use bypass
            // if (robControl.EX_ticket == _rs1EntryIndex) begin
            //     if (EX_isRegBypassing) begin
            //         regQuery.rs1Data = robControl.EX_aluResult;
            //         regQuery.rs1DataValid = TRUE;
            //         assert (!buffer[_rs1EntryIndex].rdDataValid);
            //     end
            // end else if (robControl.MEM_ticket == _rs1EntryIndex) begin
            //     if (MEM_isLoadBypassing) begin
            //         regQuery.rs1Data = robControl.MEM_loadData;
            //         regQuery.rs1DataValid = robControl.MEM_loadDataReady;
            //         assert (!buffer[_rs1EntryIndex].rdDataValid);
            //     end
            // end else if (robControl.IMUL_ticket == _rs1EntryIndex) begin
            //     if (IMUL_isRegBypassing) begin
            //         regQuery.rs1Data = robControl.IMUL_result;
            //         regQuery.rs1DataValid = robControl.IMUL_resultValid;
            //         assert (!buffer[_rs1EntryIndex].rdDataValid);
            //     end
            // end
        end

        // same as rs1
        if (_rs2EntryFound) begin
`ifdef ROB_REG_QUERY_DEBUG_PRINT_EN
            `ROB_DEBUG_PRINT(
                ("[ROB]: @%0d: RegQuery rs2 Hit at ROB Entry %0d: rd=%0d",
                 DEBUG_tick, _rs2EntryIndex, buffer[_rs2EntryIndex].rd));
`endif
            regQuery.rs2Data = buffer[_rs2EntryIndex].rdData;
            regQuery.rs2DataValid = buffer[_rs2EntryIndex].rdDataValid;
            regQuery.rs2HasEntry = TRUE;
            // TODO: use bypass
            // if (robControl.EX_ticket == _rs2EntryIndex) begin
            //     if (EX_isRegBypassing) begin
            //         regQuery.rs2Data = robControl.EX_aluResult;
            //         regQuery.rs2DataValid = TRUE;
            //         assert (!buffer[_rs2EntryIndex].rdDataValid);
            //     end
            // end else if (robControl.MEM_ticket == _rs2EntryIndex) begin
            //     if (MEM_isLoadBypassing) begin
            //         regQuery.rs2Data = robControl.MEM_loadData;
            //         regQuery.rs2DataValid = robControl.MEM_loadDataReady;
            //         assert (!buffer[_rs2EntryIndex].rdDataValid);
            //     end
            // end else if (robControl.IMUL_ticket == _rs2EntryIndex) begin
            //     if (IMUL_isRegBypassing) begin
            //         regQuery.rs2Data = robControl.IMUL_result;
            //         regQuery.rs2DataValid = robControl.IMUL_resultValid;
            //         assert (!buffer[_rs2EntryIndex].rdDataValid);
            //     end
            // end
        end

    end


    bool_t _stEntryFound;
    word_t _stEntryIdx;
    always_comb begin : StoreQueryLogic
        _stEntryFound = FALSE;
        _stEntryIdx = IMM_32_WHATEVER;
        storeQuery.hasEntry = FALSE;
        storeQuery.data = IMM_32_WHATEVER;
        storeQuery.dataLen = MEM_STLEN_INVALID;
        // partial store data that is not at least as large as requested
        // the caller should wait until this partial data is written to cache
        // at that time, the store query shuold no longer return hit and there's no
        // bypass needed, the caller just need to read from the cache
        // (the store buffer frontend waits for partial store as well)
        storeQuery.sufficientLength = FALSE;
`ifdef ROB_STORE_QUERY_DEBUG_PRINT_EN
        `ROB_DEBUG_PRINT(
            ("[ROB]: @%0d: StoreQuery virtAddr=%h, asid=%0d, dataLen=%0d",
             DEBUG_tick, storeQuery.virtAddr.va, storeQuery.virtAddr.asid, storeQuery.dataLen));
`endif
        for (int i = 0; i < ROB_SIZE; i++) begin
            automatic int index = (oldest + i + ROB_SIZE) % ROB_SIZE;
            if (index == storeQuery.ticket) begin
                // total range: [oldest, ... ticket, ... youngest]
                // we only query the range [oldest, ..., ticket]
                break;
            end
            if (buffer[index].entryValid && buffer[index].isStore) begin
`ifdef ROB_STORE_QUERY_DEBUG_PRINT_EN
                `ROB_DEBUG_PRINT(
                    ("[ROB]: @%0d: StoreQuery Checking ROB Entry %0d: stVirtAddrValid=%0b, stVirtAddr=%h",
                         DEBUG_tick, index,
                         buffer[index].stVirtAddrValid,
                         buffer[index].stVirtAddr.va));
`endif
                if (buffer[index].stVirtAddrValid &&
                    buffer[index].stVirtAddr == storeQuery.virtAddr) begin
                    _stEntryFound = TRUE;
                    _stEntryIdx   = index;
                end
            end
        end

        if (_stEntryFound) begin
            storeQuery.hasEntry = TRUE;
            storeQuery.data = buffer[_stEntryIdx].stData;
            storeQuery.dataLen = buffer[_stEntryIdx].stLen;
            if (storeQuery.dataLen <= buffer[_stEntryIdx].stLen) begin
                storeQuery.sufficientLength = TRUE;
            end
`ifdef ROB_STORE_QUERY_DEBUG_PRINT_EN
            `ROB_DEBUG_PRINT(
                ("[ROB]: @%0d: StoreQuery Hit at ROB Entry %0d: stVirtAddr=%h, stLen=%0d, stData=%h, sufficientLength=%0b",
                 DEBUG_tick, _stEntryIdx,
                 buffer[_stEntryIdx].stVirtAddr.va,
                 buffer[_stEntryIdx].stLen,
                 buffer[_stEntryIdx].stData,
                 storeQuery.sufficientLength));
`endif
        end

        // NO NEED OF BYPASS LOGIC HERE
        // ASSUMPTION: the store query interface is only used in MEM stage
        // since STORE instruction and LOAD instruction cannot be executed in the same stage
        // t1: STORE -> ROB
        // t2: LOAD <- ROB
        // we have one clock cycle to write the STORE into ROB before LOAD queries it
    end

    // if we have
    // - a LD already executing on MEM stage (perhaps cache miss), and
    // - a ST just became the oldest instruction
    // we wait for the LD to finish, then stall the pipeline to allow ST to continue

    word_t DEBUG_tick;
    always_ff @(posedge clk) begin
        DEBUG_tick <= DEBUG_tick + 1;
        `ROB_DEBUG_PRINT(
            ("[ROB]: @%0d ----- ROB Entries (Oldest: %0d, NextYoungest: %0d, isFull: %0b, isEmpty: %0b) -----",
            DEBUG_tick, oldest, nextYoungest, isFull, isEmpty));
        for (int i = 0; i < ROB_SIZE; i++) begin
            if (buffer[i].entryValid) begin
                assert (buffer[i].DEBUG_ticketId == i);
                `ROB_DEBUG_PRINT(
                    (
                    "[ROB]: @%0d ROB Entry %0d: PC=%h, isStore=%0b, stVirtAddrValid=%0b, stVirtAddr=%h, stLen=%0d, stData=%h, stComplete=%0b, isWriteback=%0b, rd=%0d, rdDataValid=%0b, rdData=%h, isBranch=%0b, shouldBranch=%0b, exceptions=%0h, inst=%h",
                    DEBUG_tick,
                    i,
                    buffer[i].pc,
                    buffer[i].isStore,
                    buffer[i].stVirtAddrValid,
                    buffer[i].stVirtAddr.va,
                    buffer[i].stData,
                    buffer[i].stLen,
                    buffer[i].stComplete,
                    buffer[i].isWriteback,
                    buffer[i].rd,
                    buffer[i].rdDataValid,
                    buffer[i].rdData,
                    buffer[i].isBranch,
                    buffer[i].shouldBranch,
                    buffer[i].exceptions,
                    buffer[i].DEBUG_instInfo.DEBUG_instBinary
                ));
            end
        end
        `ROB_DEBUG_PRINT(("[ROB]: @%0d -------------------------------", DEBUG_tick));
    end

endmodule
