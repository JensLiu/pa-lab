`timescale 1ns / 1ps

module tb_datapath;
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;

    // Clock generation
    logic tb_clk;
    always #5 tb_clk = ~tb_clk;

    reg_t DEBUG_pc;
    instruction_t DEBUG_inst;
    reg_t DEBUG_regs[0:31];
    datapath dut (
        .clk(tb_clk),
        .DEBUG_pc(DEBUG_pc),
        .DEBUG_inst(DEBUG_inst),
        .DEBUG_regs(DEBUG_regs)
    );


    // Create instructions and write to mem
    instruction_t inst;
    initial begin
        int fd;
        string mem_filename = "inst_mem.hex";
        fd = $fopen(mem_filename, "w");
        if (fd == 0) begin
            $fatal("Could not open mem file");
        end

        // Example: ADD x1, x2, x3
        inst = make_add(5'd1, 5'd2, 5'd3);
        $fdisplay(fd, "%08x", inst.raw);

        // Example: SUB x4, x5, x6
        inst = make_sub(5'd4, 5'd5, 5'd6);
        $fdisplay(fd, "%08x", inst.raw);

        // Add more instructions as needed

        $fclose(fd);
    end

    // Read instructions into instruction memory
    initial begin
        // Wait for mem file to be written
        #1;
        $readmemh("inst_mem.hex", dut.memInst.mem);
        $finish;
    end



endmodule
