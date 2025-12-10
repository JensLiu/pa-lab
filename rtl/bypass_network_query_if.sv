import pkg_global_defs::*;

interface bypass_network_query_if;
    reg_nr_t rs1;
    reg_nr_t rs2;
    bool_t   rs1HasDep;
    bool_t   rs2HasDep;
    bool_t   rs1ShouldHalt;
    bool_t   rs2ShouldHalt;
    word_t   rs1Data;
    word_t   rs2Data;

    modport master(
        output rs1,
        output rs2,
        input rs1HasDep,
        input rs2HasDep,
        input rs1ShouldHalt,
        input rs2ShouldHalt,
        input rs1Data,
        input rs2Data
    );

    modport slave(
        input rs1,
        input rs2,
        output rs1HasDep,
        output rs2HasDep,
        output rs1ShouldHalt,
        output rs2ShouldHalt,
        output rs1Data,
        output rs2Data
    );
endinterface
