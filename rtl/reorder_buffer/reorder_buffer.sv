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
    always_comb begin
        `ROB_DEBUG_PRINT(
            (
                "[ROB]: @%0d: ROB Reset check: WB_commitTicket=%0h, WB_commitFinished=%0h, WB_shouldJump=%0h", 
                DEBUG_tick, robControl.WB_commitTicket,
                robControl.WB_commitFinished, robControl.WB_shouldJump));
        if (robControl.WB_commitTicket != ROB_TICKET_INVALID &&
            robControl.WB_commitFinished &&
            robControl.WB_shouldJump) begin
            ROB_reset = TRUE;
            `ROB_DEBUG_PRINT(
                (
                "[ROB]: @%0d: ROB Reset Triggered by Commit, WB_commitTicket=%0h, WB_commitFinished=%0h, WB_shouldJump=%0h", 
                DEBUG_tick, robControl.WB_commitTicket,
                robControl.WB_commitFinished, robControl.WB_shouldJump));
        end else begin
            ROB_reset = FALSE;
        end
    end
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
        // cannot complete until WB stage because we can have exceptions
        bool_t stComplete;

        // register
        bool_t   isWriteback;
        reg_nr_t rd;
        bool_t   rdDataValid;  // we only know the data in EX (ALU), MEM (LOAD) or IMUL stage
        word_t   rdData;

        // branch: This is added to simplify our flush logic?
        bool_t isBranch;
        bool_t branchDecided;
        bool_t shouldBranch;
        addr_t branchPCVirtAddr;

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
        `ROB_DEBUG_PRINT(("[ROB]: @%0d: ========== ENQUEUE LOGIC RUN ===============", DEBUG_tick));
        if (ROB_reset) begin
            nextYoungest <= 0;
            isFull <= FALSE;
            for (int i = 0; i < ROB_SIZE; i++) begin
                `ROB_DEBUG_PRINT(("[ROB]: @%0d: ROB Clearing Entry %0d", DEBUG_tick, i));
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
                // buffer[nextYoungest].stComplete <= FALSE;
                // for writebacks
                buffer[nextYoungest].isWriteback <= ticketRequest.isWriteback;
                buffer[nextYoungest].rd <= ticketRequest.rd;
                buffer[nextYoungest].rdDataValid <= FALSE;
                // for branches
                buffer[nextYoungest].isBranch <= ticketRequest.isBranch;
                buffer[nextYoungest].shouldBranch <= FALSE;
                buffer[nextYoungest].branchDecided <= FALSE;
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
        // ROB status
        robHints.isEmpty = isEmpty;
        robHints.isFull = isFull;

        // ROB commit info
        // NOTE: only valid when all information is ready
        robHints.commitTicket = oldest;
        if (!buffer[oldest].entryValid) begin
            `ROB_DEBUG_PRINT(("[ROB]: @%0d: ROB Commit Entry %0d Not Valid", DEBUG_tick, oldest));
            robHints.commitTicket = ROB_TICKET_INVALID;
        end
        robHints.commitExceptions = buffer[oldest].exceptions;
        robHints.commitPC = buffer[oldest].pc;

        // for register writeback commit
        if (buffer[oldest].isWriteback) begin
            if (!buffer[oldest].rdDataValid) begin
                `ROB_DEBUG_PRINT(
                    ("[ROB]: @%0d: ROB Commit Entry %0d Writeback Data Not Valid", DEBUG_tick, oldest));
                robHints.commitTicket = ROB_TICKET_INVALID;
            end
        end
        robHints.commitIsWriteback = buffer[oldest].isWriteback;
        robHints.commitRd = buffer[oldest].rd;
        robHints.commitRdData = buffer[oldest].rdData;

        // for store commit
        if (buffer[oldest].isStore) begin
            if (!buffer[oldest].stVirtAddrValid) begin
                `ROB_DEBUG_PRINT(
                    ("[ROB]: @%0d: ROB Commit Entry %0d Store Address Not Valid", DEBUG_tick, oldest));
                robHints.commitTicket = ROB_TICKET_INVALID;
            end
        end
        robHints.commitIsStore = buffer[oldest].isStore;
        robHints.commitStVirtAddr = buffer[oldest].stVirtAddr;
        robHints.commitStData = buffer[oldest].stData;
        robHints.commitStLen = buffer[oldest].stLen;
        robHints.commitStComplete = buffer[oldest].stComplete;

        // for branch commit
        if (buffer[oldest].isBranch) begin
            if (!buffer[oldest].branchDecided) begin
                `ROB_DEBUG_PRINT(
                    ("[ROB]: @%0d: ROB Commit Entry %0d Branch Not Decided", DEBUG_tick, oldest));
                robHints.commitTicket = ROB_TICKET_INVALID;
            end
        end
        robHints.commitIsBranch = buffer[oldest].isBranch;

        // if (EX_isBranchBypassing) begin
        //     `ROB_DEBUG_PRINT(
        //         ("[ROB]: @%0d: ROB Commit Entry %0d Branch Bypassing from EX Stage", DEBUG_tick, oldest));
        //     robHints.commitShouldBranch = robControl.EX_shouldBranch;
        //     robHints.commitBranchPCVirtAddr = robControl.EX_branchPC;
        // end else begin
        robHints.commitShouldBranch = buffer[oldest].shouldBranch;
        robHints.commitBranchPCVirtAddr = buffer[oldest].branchPCVirtAddr;
        // end

        if (robHints.commitTicket != ROB_TICKET_INVALID) begin
            `ROB_DEBUG_PRINT(
                ("[ROB]: @%0d: ROB Commit Ready for Ticket %0d", DEBUG_tick, robHints.commitTicket));
            `ROB_DEBUG_PRINT(
                (
            "[ROB]: @%0d: ROB Commit Check for Oldest Ticket %0d, entry's ticket ID %0d",
            DEBUG_tick, oldest, buffer[oldest].DEBUG_ticketId));
            assert (buffer[oldest].DEBUG_ticketId == oldest);
        end
    end

    bool_t _shouldDequeue;
    bool_t commitStComplete;
    always @(posedge clk) begin : DequeueLogic
        `ROB_DEBUG_PRINT(("[ROB]: @%0d: ========== DEQUEUE LOGIC RUN ===============", DEBUG_tick));
        // `ROB_DEBUG_PRINT(
        //     ("[ROB]: @%0d: Dequeue Logic Check: isEmpty=%0b, isFull=%0b, oldest=%0d, oldestIsWriteback=%0b, oldestRdDataValid=%0b, oldestIsStore=%0b, oldestStComplete=%0b",
        //  DEBUG_tick, isEmpty, isFull, oldest, robHints.commitIsWriteback, robHints.commitRdDataValid, robHints.commitIsStore, robHints.commitStComplete));
        _shouldDequeue = FALSE;
        if (ROB_reset) begin
            `ROB_DEBUG_PRINT(("[ROB]: @%0d: ROB Reset Triggered, Clearing ROB", DEBUG_tick));
            oldest <= 0;
            isFull <= FALSE;
            for (int i = 0; i < ROB_SIZE; i++) begin
                buffer[i].entryValid <= FALSE;
            end
        end else if (
            !isEmpty && robControl.WB_commitTicket == oldest && robControl.WB_commitFinished) begin
            `ROB_DEBUG_PRINT(("[ROB]: @%0d: ROB Ticket %0d Dequeue Requested", DEBUG_tick, oldest));
            // only when instruction reaches the WB stage can we dequeue.
            // Don't dequeue at early stages to check for exceptions
            if (robHints.commitIsWriteback) begin
                _shouldDequeue = TRUE;
                `ROB_DEBUG_PRINT(
                    ("[ROB]: @%0d: ROB Ticket %0d Dequeue for Writeback (rd=%0d, data=%h)",
                                 DEBUG_tick, oldest,
                                 buffer[oldest].rd,
                                 buffer[oldest].rdData));
            end

            if (robHints.commitIsStore) begin
                // only dequeue when MEM stage is acceping commits (to avoid losing instructions)
                if (commitStComplete) begin
                    _shouldDequeue = TRUE;
                    `ROB_DEBUG_PRINT(
                        ("[ROB]: @%0d: ROB Ticket %0d Dequeue for Store (addr=%h, len=%0d, data=%h)",
                                 DEBUG_tick, oldest,
                                 buffer[oldest].stVirtAddr.va,
                                 buffer[oldest].stLen,
                                 buffer[oldest].stData));
                end
            end

            if (robHints.commitIsBranch) begin
                // when the branch is not taken, we can dequeue
                // when the branch is taken, the rob should be reset anyway
                // NOTE: WB_finishedTicket is ONLY valid when WB assume we can safely delete this entry
                //       if branch should be taken but IF cannot jump, WB_finishedTicket is INVALID
                _shouldDequeue = TRUE;
                `ROB_DEBUG_PRINT(
                    ("[ROB]: @%0d: ROB Ticket %0d Dequeue for Branch (shouldBranch=%0b, branchAddr=%h)",
                                 DEBUG_tick, oldest,
                                 buffer[oldest].shouldBranch,
                                 buffer[oldest].branchPCVirtAddr));
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
        end else begin
            `ROB_DEBUG_PRINT(
                (
                "[ROB]: @%0d: ROB Ticket %0d Not Dequeued, WB_commitTicket=%0d, WB_commitFinished=%0d",
                DEBUG_tick, oldest, robControl.WB_commitTicket, robControl.WB_commitFinished));
        end
        `ROB_DEBUG_PRINT(("[ROB]: @%0d: ========== DEQUEUE LOGIC END ===============", DEBUG_tick));
    end

    // this logic is expensive, perhaps seralise update requests (slower performance)?
    bool_t EX_isBranchBypassing, EX_isRegBypassing, EX_isStoreBypassing;
    bool_t MEM_isLoadBypassing, IMUL_isRegBypassing;
    assign EX_isBranchBypassing = robControl.EX_ticket != ROB_TICKET_INVALID &&
                                 robControl.EX_isBranch;
    assign EX_isRegBypassing = robControl.EX_ticket != ROB_TICKET_INVALID &&
                               !robControl.EX_isLoad && !robControl.EX_isStore &&
                               robControl.EX_isWriteback;
    assign EX_isStoreBypassing = robControl.EX_ticket != ROB_TICKET_INVALID &&
                                 robControl.EX_isStore;
    assign MEM_isLoadBypassing = robControl.MEM_ticket != ROB_TICKET_INVALID &&
                                 !robControl.MEM_isCommitting && robControl.MEM_isLoad;
    assign IMUL_isRegBypassing = robControl.IMUL_ticket != ROB_TICKET_INVALID;
    always @(posedge clk) begin : UpdateLogic
        `ROB_DEBUG_PRINT(("[ROB]: @%0d: ========== UPDATE LOGIC RUN ===============", DEBUG_tick));
        // Each stage should have different tickets if they are valid
        if (robControl.EX_ticket != ROB_TICKET_INVALID &&
            robControl.MEM_ticket != ROB_TICKET_INVALID) begin
            `ROB_DEBUG_PRINT(
                ("[ROB]: @%0d: EX_ticket=%0d, MEM_ticket=%0d", DEBUG_tick,
                     robControl.EX_ticket, robControl.MEM_ticket));
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
            if (robControl.MEM_isLoad) begin
                assert (robControl.MEM_ticket < ROB_SIZE);
                assert (buffer[robControl.MEM_ticket].entryValid);
            end else begin
                // is STORE instruction, the following scenario may happen
                // t1: ID stage: STORE@ticket 1: r1 -> A1 (not calculated)
                //     EX stage: NOP@ticket INVALID
                //     MEM stage: NOP@ticket INVALID
                // t2: ID stage: NOP@ticket INVALID
                //     EX stage: STORE@ticket 1: r1 -> A1 (calculated)
                //     MEM stage: NOP@ticket INVALID (not visible now)
                // t3: ID stage: NOP@ticket INVALID
                //     EX stage: NOP@ticket INVALID
            end
        end
        if (robControl.IMUL_ticket != ROB_TICKET_INVALID) begin
            $display("[ROB]: @%0d: IMUL_ticket = %0d", DEBUG_tick, robControl.IMUL_ticket);
            assert (robControl.IMUL_ticket < ROB_SIZE);
            assert (buffer[robControl.IMUL_ticket].entryValid);
        end

        // EX (ALU) update
        if (robControl.EX_ticket != ROB_TICKET_INVALID) begin
            `ROB_DEBUG_PRINT(
                ("[ROB]: @%0d: EX Stage Update for ROB Ticket %0d", DEBUG_tick, robControl.EX_ticket));
            assert (buffer[robControl.EX_ticket].entryValid);
            if (!robControl.EX_isLoad && !robControl.EX_isStore) begin
                // not memory instructions -> ALU Result is rd data (not an address)
                // otherwise, they are virtual addresses, however we only want physical addresses
                if (robControl.EX_isBranch) begin
                    // JAL/JALR/BRANCH enters the BRANCH category
                    // NOTE: they can also be writeback instructions (JAL/JALR)
                    buffer[robControl.EX_ticket].shouldBranch <= robControl.EX_shouldBranch;
                    buffer[robControl.EX_ticket].branchDecided <= TRUE;
                    buffer[robControl.EX_ticket].branchPCVirtAddr <= robControl.EX_branchPC;
                end
                if (buffer[robControl.EX_ticket].isWriteback) begin
                    buffer[robControl.EX_ticket].rdData <= robControl.EX_aluResult;
                    buffer[robControl.EX_ticket].rdDataValid <= TRUE;
                    buffer[robControl.EX_ticket].exceptions <= robControl.EX_exceptions;
                end else if (!robControl.EX_isBranch) begin
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
            end
        end

        // MEM update
        commitStComplete = FALSE;
        if (robControl.MEM_commitTicket != ROB_TICKET_INVALID) begin
            commitStComplete = robControl.MEM_commitStoreComplete;
            buffer[robControl.MEM_ticket].exceptions <= robControl.MEM_exceptions;
            `ROB_DEBUG_PRINT(
                (
                "[ROB]: @%0d: MEM Stage Commit Update for ROB Ticket %0d, MEM_isCommitStore=%0b",
                DEBUG_tick, robControl.MEM_commitTicket,
                robControl.MEM_commitStoreComplete));
        end
        if (robControl.MEM_ticket != ROB_TICKET_INVALID && robControl.MEM_isLoad &&
            !robControl.MEM_isCommitting) begin
            assert (buffer[robControl.MEM_ticket].entryValid);
            assert (buffer[robControl.MEM_ticket].isWriteback);
            buffer[robControl.MEM_ticket].rdDataValid <= robControl.MEM_loadDataReady;
            buffer[robControl.MEM_ticket].rdData <= robControl.MEM_loadData;
            `ROB_DEBUG_PRINT(
                (
                "[ROB]: @%0d: MEM Stage Update for ROB Ticket %0d, MEM_isLoad=%0b",
                DEBUG_tick, robControl.MEM_ticket, robControl.MEM_isLoad));
            `ROB_DEBUG_PRINT(
                (
                "[ROB]: @%0d: MEM Stage LOAD Update for ROB Ticket %0d", DEBUG_tick, robControl.MEM_ticket));
        end else begin
            `ROB_DEBUG_PRINT(
                (
                "[ROB]: @%0d: MEM Stage no update for ROB Ticket %0d", DEBUG_tick, robControl.MEM_ticket));
            assert (buffer[robControl.MEM_ticket].isWriteback ||
                    buffer[robControl.MEM_ticket].isBranch ||
                    buffer[robControl.MEM_ticket].isStore ||
                    buffer[robControl.MEM_ticket].DEBUG_instInfo.DEBUG_instBinary == '0);
        end

        `ROB_DEBUG_PRINT(
            (
            "[ROB] @%0d: commitStComplete=%0d, robControl.MEM_ticket=%0d robControl.MEM_commitTicket=%0d, robControl.MEM_commitStoreComplete=%0d",
            DEBUG_tick, commitStComplete, robControl.MEM_ticket,
            robControl.MEM_commitTicket, robControl.MEM_commitStoreComplete));

        // IMUL update
        if (robControl.IMUL_ticket != ROB_TICKET_INVALID) begin
            assert (buffer[robControl.IMUL_ticket].entryValid);
            assert (buffer[robControl.IMUL_ticket].isWriteback);
            buffer[robControl.IMUL_ticket].rdData <= robControl.IMUL_result;
            buffer[robControl.IMUL_ticket].rdDataValid <= TRUE;
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
        if (_rs1EntryFound && regQuery.rs1 > 0) begin
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
            if (robControl.EX_ticket == _rs1EntryIndex) begin
                if (EX_isRegBypassing) begin
                    regQuery.rs1Data = robControl.EX_aluResult;
                    regQuery.rs1DataValid = TRUE;
                end
            end 
            // else if (robControl.MEM_ticket == _rs1EntryIndex) begin
            //     if (MEM_isLoadBypassing) begin
            //         assert (!robControl.MEM_isCommitting && robControl.MEM_commitTicket == ROB_TICKET_INVALID);
            //         $display(
            //             "@%d: bypassing instruction @%h: %h, rs1=%d, MEM_ticket=%0d, MEM_loadData=%h, MEM_loadDataReady=%b",
            //             DEBUG_tick, buffer[_rs1EntryIndex].pc,
            //             buffer[_rs1EntryIndex].DEBUG_instInfo.DEBUG_instBinary, regQuery.rs1,
            //             robControl.MEM_ticket, robControl.MEM_loadData,
            //             robControl.MEM_loadDataReady);
            //         regQuery.rs1Data = robControl.MEM_loadData;
            //         regQuery.rs1DataValid = robControl.MEM_loadDataReady;
            //     end
            // end
            // else if (robControl.IMUL_ticket == _rs1EntryIndex) begin
            //     if (IMUL_isRegBypassing) begin
            //         regQuery.rs1Data = robControl.IMUL_result;
            //         regQuery.rs1DataValid = robControl.IMUL_resultValid;
            //         assert (!buffer[_rs1EntryIndex].rdDataValid);
            //     end
            // end
        end

        // same as rs1
        if (_rs2EntryFound && regQuery.rs2 > 0) begin
`ifdef ROB_REG_QUERY_DEBUG_PRINT_EN
            `ROB_DEBUG_PRINT(
                ("[ROB]: @%0d: RegQuery rs2 Hit at ROB Entry %0d: rd=%0d",
                 DEBUG_tick, _rs2EntryIndex, buffer[_rs2EntryIndex].rd));
`endif
            regQuery.rs2Data = buffer[_rs2EntryIndex].rdData;
            regQuery.rs2DataValid = buffer[_rs2EntryIndex].rdDataValid;
            regQuery.rs2HasEntry = TRUE;
            // TODO: use bypass
            if (robControl.EX_ticket == _rs2EntryIndex) begin
                if (EX_isRegBypassing) begin
                    regQuery.rs2Data = robControl.EX_aluResult;
                    regQuery.rs2DataValid = TRUE;
                end
            end
            // else if (robControl.MEM_ticket == _rs2EntryIndex) begin
            //     if (MEM_isLoadBypassing) begin
            //         assert (!robControl.MEM_isCommitting && robControl.MEM_commitTicket == ROB_TICKET_INVALID);
            //         regQuery.rs2Data = robControl.MEM_loadData;
            //         regQuery.rs2DataValid = robControl.MEM_loadDataReady;
            //     end
            // end
            // else if (robControl.IMUL_ticket == _rs2EntryIndex) begin
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
            ("[ROB]: @%0d ====== ROB Entries (Oldest: %0d, NextYoungest: %0d, isFull: %0b, isEmpty: %0b) =======",
            DEBUG_tick, oldest, nextYoungest, isFull, isEmpty));
        for (int i = 0; i < ROB_SIZE; i++) begin
            if (buffer[i].entryValid) begin
                assert (buffer[i].DEBUG_ticketId == i);
                if (buffer[i].isBranch) begin
                    if (buffer[i].isWriteback) begin
                        `ROB_DEBUG_PRINT(
                            ("[ROB]: @%0d [%0d] BR: PC=%h, inst=%h, rd=%0d, rdDataValid=%0b, rdData=%h, shouldBranch=%0b, branchDecided=%0b, branchAddr=%0h, exceptions=%h",
                        DEBUG_tick,
                        i,
                        buffer[i].pc,
                        buffer[i].DEBUG_instInfo.DEBUG_instBinary,
                        buffer[i].rd,
                        buffer[i].rdDataValid,
                        buffer[i].rdData,
                        buffer[i].shouldBranch,
                        buffer[i].branchDecided,
                        buffer[i].branchPCVirtAddr,
                        buffer[i].exceptions));
                    end else begin
                        `ROB_DEBUG_PRINT(
                            ("[ROB]: @%0d [%0d] BR: PC=%h, inst=%h, isBranch=%0b, shouldBranch=%0b, branchDecided=%0b, branchAddr=%0h, exceptions=%h",
                        DEBUG_tick,
                        i,
                        buffer[i].pc,
                        buffer[i].DEBUG_instInfo.DEBUG_instBinary,
                        buffer[i].isBranch,
                        buffer[i].shouldBranch,
                        buffer[i].branchDecided,
                        buffer[i].branchPCVirtAddr,
                        buffer[i].exceptions));
                    end
                end else if (buffer[i].isStore) begin
                    `ROB_DEBUG_PRINT(
                        ("[ROB]: @%0d [%0d] ST: PC=%h, inst=%h, stVirtAddrValid=%0b, stVirtAddr=%h, stLen=%0d, stData=%h, stComplete=%0b, exceptions=%h",
                    DEBUG_tick,
                    i,
                    buffer[i].pc,
                    buffer[i].DEBUG_instInfo.DEBUG_instBinary,
                    buffer[i].stVirtAddrValid,
                    buffer[i].stVirtAddr.va,
                    buffer[i].stLen,
                    buffer[i].stData,
                    buffer[i].stComplete,
                    buffer[i].exceptions));
                end else if (buffer[i].isWriteback) begin
                    `ROB_DEBUG_PRINT(
                        (
                    "[ROB]: @%0d [%0d] WB: PC=%h, inst=%h, rd=%0d, rdDataValid=%0b, rdData=%h, exceptions=%h",
                    DEBUG_tick,
                    i,
                    buffer[i].pc,
                    buffer[i].DEBUG_instInfo.DEBUG_instBinary,
                    buffer[i].rd,
                    buffer[i].rdDataValid,
                    buffer[i].rdData,
                    buffer[i].exceptions
                ));
                end
            end
        end
        `ROB_DEBUG_PRINT(("[ROB]: @%0d -------------------------------", DEBUG_tick));
    end

endmodule
