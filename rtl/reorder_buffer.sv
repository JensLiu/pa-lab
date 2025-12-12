import pkg_global_defs::*;

interface rob_ticket_request_if;
    bool_t request;
    bool_t ready;
    word_t ticket;
    bool_t isStore;
    mem_stlen_t stLen;
    word_t stData;
    bool_t isWriteback;
    reg_nr_t rd;
    addr_t pc;
    inst_info_t DEBUG_instInfo;
    modport master(
        output request,
        input ready,
        input ticket,
        output isStore,
        output stLen,
        output stData,
        output isWriteback,
        output rd,
        output pc,
        output DEBUG_instInfo
    );
    modport slave(
        input request,
        output ready,
        output ticket,
        input isStore,
        input stLen,
        input stData,
        input isWriteback,
        input rd,
        input pc,
        input DEBUG_instInfo
    );
endinterface

interface rob_entry_update_request_if;
    bool_t request;
    word_t ticket;
    // store update
    bool_t isStore;
    addr_t stPhysAddr;
    bool_t stPhysAddrValid;
    bool_t stComplete;  // we could reuse rdDataValid
    // writeback update

endinterface

interface rob_reg_query_if;
    reg_nr_t rs1;
    bool_t   rs1HasEntry;
    word_t   rs1Data;
    bool_t   rs1DataValid;

    reg_nr_t rs2;
    bool_t   rs2HasEntry;
    word_t   rs2Data;
    bool_t   rs2DataValid;
    modport master(
        output rs1,
        output rs2,
        input rs1HasEntry,
        input rs2HasEntry,
        input rs1Data,
        input rs1DataValid,
        input rs2Data,
        input rs2DataValid
    );
    modport slave(
        input rs1,
        input rs2,
        output rs1HasEntry,
        output rs2HasEntry,
        output rs1Data,
        output rs1DataValid,
        output rs2Data,
        output rs2DataValid
    );
endinterface

interface rob_store_query_if;
    addr_t addr;
    bool_t hasEntry;
    word_t data;
    // NOTE:
    // if we only write one byte to an address and want to read a whole bit from the address
    // we should first read the old one from the cache and then apply this update
    logic  dataLen;

    modport master(output addr, input hasEntry, input data, input dataLen);
    modport slave(input addr, output hasEntry, output data, output dataLen);
endinterface

interface rob_update_request_if;
    word_t ticket;


endinterface

typedef struct {
    bool_t isEmpty;
    bool_t isFull;
    // registers
    bool_t oldestIsWriteback;
    reg_nr_t oldestRd;
    bool_t oldestRdDataValid;
    word_t oldestRdData;
    // store
    bool_t oldestIsStore;
    addr_t oldestStPhysAddr;
    bool_t oldestStPhysAddrValid;
    word_t oldestStData;
    mem_stlen_t oldestStLen;
    bool_t oldestStComplete;
} rob_hints_t;

typedef struct {
    // EX Stage (ALU)
    word_t EX_ticket;
    bool_t EX_isLoad;
    bool_t EX_isStore;
    word_t EX_aluResult;
    bool_t EX_aluResultValid;
    bool_t EX_branchTaken;
    // MEM Stage
    word_t MEM_ticket;
    bool_t MEM_isLoad;
    bool_t MEM_isStore;
    addr_t MEM_physAddr;
    bool_t MEM_physAddrReady;
    word_t MEM_memLoadResult;
    bool_t MEM_memLoadResultReady;
    bool_t MEM_exception_invalidAccess;
    // INT-MUL Stage (Multiplication Pipeline Finished)
    word_t IMUL_ticket;
    word_t IMUL_result;
    bool_t IMUL_resultValid;
} rob_control_t;

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
        addr_t stPhysAddr;
        bool_t stPhysAddrValid;
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
        // NOTE: If we were using Virtual Addresses
        //       we need identifier to distinguish between address spaces
        // STORE a1 -> 0x100
        // SWITCH ADDRESS SPACE OR PAGE REMAP
        // LOAD  a2 <- 0x100
        // assume 0x100 is still in the ROB, we should NOT bypass a1 to a2
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
                buffer[nextYoungest].stPhysAddrValid <= FALSE;
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
        robHints.oldestStPhysAddr = buffer[oldest].stPhysAddr;
        robHints.oldestStPhysAddrValid = buffer[oldest].stPhysAddrValid;
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
    always_ff @(posedge clk) begin : UpdateLogic
        assert (robControl.EX_ticket != robControl.MEM_ticket);
        assert (robControl.EX_ticket != robControl.IMUL_ticket);
        assert (robControl.MEM_ticket != robControl.IMUL_ticket);
        assert (robControl.EX_ticket < ROB_SIZE);
        assert (robControl.MEM_ticket < ROB_SIZE);
        assert (robControl.IMUL_ticket < ROB_SIZE);
        assert (buffer[robControl.EX_ticket].entryValid &&
                buffer[robControl.MEM_ticket].entryValid &&
                buffer[robControl.IMUL_ticket].entryValid);

        // ALU update
        if (!robControl.EX_isLoad && !robControl.EX_isStore) begin
            // not memory instructions -> ALU Result is rd data (not an address)
            // otherwise, they are virtual addresses, however we only want physical addresses
            assert (buffer[robControl.EX_ticket].isWriteback);
            buffer[robControl.EX_ticket].rdData <= robControl.EX_aluResult;
            buffer[robControl.EX_ticket].rdDataValid <= robControl.EX_aluResultValid;
            buffer[robControl.EX_ticket].branchTaken <= robControl.EX_branchTaken;
        end

        if (robControl.MEM_isStore) begin
            // MEM update: TLB
            buffer[robControl.MEM_ticket].stPhysAddr <= robControl.MEM_physAddr;
            buffer[robControl.MEM_ticket].stPhysAddrValid <= robControl.MEM_physAddrReady;
        end else if (robControl.MEM_isLoad) begin
            // MEM update: Cache
            assert (buffer[robControl.MEM_ticket].isWriteback);
            buffer[robControl.MEM_ticket].rdDataValid <= robControl.MEM_memLoadResultReady;
            buffer[robControl.MEM_ticket].rdData <= robControl.MEM_memLoadResult;
        end else begin
            // register-register instructions
            assert (buffer[robControl.MEM_ticket].isWriteback);
            assert (buffer[robControl.MEM_ticket].rdDataValid);
        end

        // IMUL update
        assert (buffer[robControl.IMUL_ticket].isWriteback);
        buffer[robControl.IMUL_ticket].rdData <= robControl.IMUL_result;
        buffer[robControl.IMUL_ticket].rdDataValid <= robControl.IMUL_resultValid;
    end

    // youngest in ROB (no bypass)
    bool_t _rs1EntryFound, _rs2EntryFound;
    word_t _rs1EntryIndex, _rs2EntryIndex;
    always_comb begin : RegQueryLogic  // this logic is very expensive
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
        
    end


    // if we have
    // - a LD already executing on MEM stage (perhaps cache miss), and
    // - a ST just became the oldest instruction
    // we wait for the LD to finish, then stall the pipeline to allow ST to continue

endmodule
