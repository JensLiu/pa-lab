import pkg_global_defs::*;

module bypass_network_basic (
    bypass_network_basic_info_t   controlInfo,
    bypass_network_query_if.slave query
);
    bool_t rs1ExDep, rs1MemDep, rs1WbDep;
    assign rs1ExDep  = controlInfo.EX_rd == query.rs1 && query.rs1 != 5'd0;
    assign rs1MemDep = controlInfo.MEM_rd == query.rs1 && query.rs1 != 5'd0;
    assign rs1WbDep  = controlInfo.WB_rd == query.rs1 && query.rs1 != 5'd0;
    bool_t rs2ExDep, rs2MemDep, rs2WbDep;
    assign rs2MemDep = controlInfo.MEM_rd == query.rs2 && query.rs2 != 5'd0;
    assign rs2ExDep  = controlInfo.EX_rd == query.rs2 && query.rs2 != 5'd0;
    assign rs2WbDep  = controlInfo.WB_rd == query.rs2 && query.rs2 != 5'd0;

    always_comb begin : DependencyResolverResult
        query.rs1HasDep = rs1ExDep || rs1MemDep || rs1WbDep;
        query.rs2HasDep = rs2ExDep || rs2MemDep || rs2WbDep;
        // NOTE: we should NOT allow `EX_isLoad` to bypass since the its `EX_aluResult`
        //       is the load address not the data
        query.rs1ShouldHalt = rs1ExDep && controlInfo.EX_isLoad;
        query.rs2ShouldHalt = rs2ExDep && controlInfo.EX_isLoad;
    end

    always_comb begin : BypassResult
        if (rs1ExDep) begin
            query.rs1Data = controlInfo.EX_aluResult;
        end else if (rs1MemDep) begin
            query.rs1Data = controlInfo.MEM_memResult;
        end else if (rs1WbDep) begin
            query.rs1Data = controlInfo.WB_rdData;
        end else begin
            query.rs1Data = IMM_32_WHATEVER;
        end

        if (rs2ExDep) begin
            query.rs2Data = controlInfo.EX_aluResult;
        end else if (rs2MemDep) begin
            query.rs2Data = controlInfo.MEM_memResult;
        end else if (rs2WbDep) begin
            query.rs2Data = controlInfo.WB_rdData;
        end else begin
            query.rs2Data = IMM_32_WHATEVER;
        end
    end


endmodule
