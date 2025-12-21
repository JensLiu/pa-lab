interface rob_reg_query_if;  // for bypasses (ID)
    // word_t ticket;  // should only query from [oldest, ticket]
    reg_nr_t rs1;
    bool_t   rs1HasEntry;
    word_t   rs1Data;
    bool_t   rs1DataValid;

    reg_nr_t rs2;
    bool_t   rs2HasEntry;
    word_t   rs2Data;
    bool_t   rs2DataValid;
    modport master(
        // output ticket,
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
        // input ticket,
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
