`timescale 1ns / 1ps

module tb_reorder_buffer;

    import pkg_global_defs::*;

    // Signals
    logic clk;
    logic rst;
    rob_control_t robControl;
    rob_hints_t robHints;

    // Interfaces
    rob_ticket_request_if ticketRequest ();
    rob_reg_query_if regQuery ();
    rob_store_query_if storeQuery ();

    // DUT instantiation
    reorder_buffer dut (
        .clk(clk),
        .rst(rst),
        .robControl(robControl),
        .robHints(robHints),
        .ticketRequest(ticketRequest.slave),
        .regQuery(regQuery.slave),
        .storeQuery(storeQuery.slave)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    word_t tick;
    always_ff @(posedge clk) begin
        tick <= tick + 1;
    end

    // Helper task to reset the DUT
    task reset_dut();
        rst = 1;
        // robControl = '0; // Verilator issue with '0 assignment to struct
        robControl.EX_ticket = ROB_TICKET_INVALID;
        robControl.EX_isLoad = FALSE;
        robControl.EX_isStore = FALSE;
        robControl.EX_aluResult = 0;
        robControl.EX_aluResultValid = FALSE;
        robControl.EX_isBranch = FALSE;
        robControl.EX_branchTaken = FALSE;

        robControl.MEM_ticket = ROB_TICKET_INVALID;
        robControl.MEM_virtAddr = '{va: 0, asid: 0};
        robControl.MEM_isLoad = FALSE;
        robControl.MEM_loadResult = 0;
        robControl.MEM_loadResultReady = FALSE;
        robControl.MEM_isStore = FALSE;
        robControl.MEM_storeData = 0;
        robControl.MEM_storeLen = MEM_STLEN_WORD;
        robControl.MEM_storeComplete = FALSE;
        robControl.MEM_exception_invalidAccess = FALSE;

        robControl.IMUL_ticket = ROB_TICKET_INVALID;
        robControl.IMUL_result = 0;
        robControl.IMUL_resultValid = FALSE;

        ticketRequest.request = FALSE;
        ticketRequest.isStore = FALSE;
        ticketRequest.stLen = MEM_STLEN_WORD;
        ticketRequest.stData = '0;
        ticketRequest.isWriteback = FALSE;
        ticketRequest.rd = 0;
        ticketRequest.pc = '0;
        ticketRequest.DEBUG_instInfo = inst_info_make_nop();

        regQuery.rs1 = 0;
        regQuery.rs2 = 0;

        storeQuery.virtAddr = '{va: '0, asid: '0};
        storeQuery.dataLen = MEM_STLEN_WORD;

        repeat (2) @(posedge clk);
        rst = 0;
        @(posedge clk);
    endtask

    // Helper task to request a ticket
    task request_ticket(input bool_t isStore, input bool_t isWriteback, input reg_nr_t rd,
                        output word_t ticket);
        ticketRequest.request = TRUE;
        ticketRequest.isStore = isStore;
        ticketRequest.isWriteback = isWriteback;
        ticketRequest.rd = rd;
        ticketRequest.stLen = MEM_STLEN_WORD;
        ticketRequest.stData = 32'hDEADBEEF;
        ticketRequest.pc = 32'h1000;

        wait (ticketRequest.ready);
        ticket = ticketRequest.ticket;
        @(posedge clk);
        ticketRequest.request = FALSE;
        $display("@%0d Got ticket: %0d", tick, ticket);
        @(posedge clk);
    endtask

    // Test scenarios
    initial begin
        word_t t1, t2, t3;

        $display("@%0d Starting tb_reorder_buffer...", tick);

        // 1. Reset
        reset_dut();
        assert (robHints.isEmpty == TRUE)
        else $error("ROB should be empty after reset");
        assert (robHints.isFull == FALSE)
        else $error("ROB should not be full after reset");

        // 3. Enqueue a store instruction
        $display("@%0d Test: Enqueue Store", tick);
        request_ticket(TRUE, FALSE, 0, t1);

        // 2. Enqueue a register writeback instruction
        $display("@%0d Test: Enqueue Register Writeback", tick);
        request_ticket(FALSE, TRUE, 5, t2);  // rd=5
        assert (robHints.isEmpty == FALSE);
        else $error("ROB should not be empty");

        // 4. Update EX stage (ALU result for t2)
        $display("@%0d Test: Update EX stage", tick);
        robControl.EX_ticket = t2;
        robControl.EX_aluResult = 32'hAABBCCDD;
        robControl.EX_aluResultValid = TRUE;
        robControl.EX_isLoad = FALSE;
        robControl.EX_isStore = FALSE;
        robControl.EX_isBranch = FALSE;

        @(posedge clk);
        #1;
        robControl.EX_ticket = ROB_TICKET_INVALID;
        robControl.EX_aluResultValid = FALSE;  // Clear valid after one cycle

        // Check if data is forwarded via regQuery
        regQuery.rs1 = 5;
        #5;
        assert (regQuery.rs1HasEntry == TRUE)
        else $error("Should find entry for r5");
        assert (regQuery.rs1Data == 32'hAABBCCDD)
        else $error("Should forward data for r5");
        assert (regQuery.rs1DataValid == TRUE)
        else $error("Data should be valid");

        // 5. Update MEM stage (Store address for t1)
        $display("Test: Update MEM stage (Store)");
        robControl.MEM_ticket = t1;
        robControl.MEM_isStore = TRUE;
        robControl.MEM_virtAddr.va = 32'h2000;
        robControl.MEM_storeData = 32'h12345678;
        robControl.MEM_storeLen = MEM_STLEN_WORD;
        robControl.MEM_storeComplete = TRUE;  // Mark as complete for testing retirement
        $display("@%0d Updated MEM stage for ticket %0d", tick, t1);

        @(posedge clk);
        #1;
        $display("@%0d Cleared MEM stage", tick);
        robControl.MEM_ticket = ROB_TICKET_INVALID;
        robControl.MEM_isStore = FALSE;
        robControl.MEM_storeComplete = FALSE;

        // Check store query
        storeQuery.virtAddr.va = 32'h2000;
        #1;
        assert (storeQuery.hasEntry == TRUE)
        else $error("Should find store entry");
        // Note: Store data forwarding might depend on implementation details in ROB

        // 6. Retire instructions
        $display("@%0d Test: Retire", tick);

        // t1 (Store) should be ready to retire (stComplete set in step 5)
        // t2 (Writeback) should be ready to retire (rdDataValid set in step 4)

        // Wait for DequeueLogic to process t1
        @(posedge clk);
        #1;

        // Check if t1 retired
        // After t1 retires, oldest should be t2 (ticket 1)
        // And since t2 is already valid, it should be ready to retire
        $display("@%0d Checking ROB hints after retiring t1", tick);
        assert (robHints.oldestIsWriteback == TRUE)
        else $error("Oldest should be Writeback (t2) after Store (t1) retires");
        $display("@%0d Checking if t2 data is valid", tick);
        assert (robHints.oldestRdDataValid == TRUE)
        else $error("Oldest (t2) data should be valid");

        // Wait for DequeueLogic to process t2
        @(posedge clk);
        #1;

        // Now ROB should be empty
        assert (robHints.isEmpty == TRUE)
        else $error("ROB should be empty after retiring t2");

        $display("@%0d Test finished successfully", tick);
        $finish;
    end
endmodule
