`timescale 1ns / 1ps

module tb_decoder;
    import pkg_riscv_instructions::*;
    import pkg_global_defs::*;

    // DUT interface
    instruction_t inst;
    wire inst_info_t info;

    // instantiate decoder
    decoder dut (
        .inst(inst),
        .info(info)
    );

    integer passed = 0;
    integer failed = 0;

    task automatic check_eq(string name, logic ok);
        begin
            if (ok) begin
                $display("[PASS] %s", name);
                passed++;
            end else begin
                $display("[FAIL] %s", name);
                failed++;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_decoder.vcd");  // Sets the output file name
        $dumpvars(0, tb_decoder);  // Dumps all signals in the testbench and below
        $display("decoder_tb starting");

        // 1) R-type ADD x1, x2, x3
        inst = make_add(5'd1, 5'd2, 5'd3);
        #1;
        check_eq("R-ADD: isWriteback", info.isWriteback === 1'b1);
        check_eq("R-ADD: aluOp == ALU_ADD", info.aluOp === ALU_ADD);
        check_eq("R-ADD: rd==1", info.rd === 5'd1);
        check_eq("R-ADD: rs1==2", info.rs1 === 5'd2);
        check_eq("R-ADD: rs2==3", info.rs2 === 5'd3);
        check_eq("R-ADD: isLoad", info.isLoad === 1'b0);
        check_eq("R-ADD: isStore", info.isStore === 1'b0);
        check_eq("R-ADD: aluUseImmAsRs2", info.aluUseImmAsRs2 === 1'b0);
        check_eq("R-ADD: imm==0", info.imm === IMM_32_WHATEVER);
        check_eq("R-ADD: stldDataLen == DL_WORD", info.stldDataLen === DL_INVALID);
        check_eq("R-ADD: stldSignedness == SS_SIGNED", info.stldSignedness === SS_INVALID);

        // 2) R-type SUB x1, x2, x3
        inst = make_sub(5'd1, 5'd2, 5'd3);
        #1;
        check_eq("R-SUB: isWriteback", info.isWriteback === 1'b1);
        check_eq("R-SUB: aluOp == ALU_SUB", info.aluOp === ALU_SUB);
        check_eq("R-SUB: rd==1", info.rd === 5'd1);
        check_eq("R-SUB: rs1==2", info.rs1 === 5'd2);
        check_eq("R-SUB: rs2==3", info.rs2 === 5'd3);
        check_eq("R-SUB: isLoad", info.isLoad === 1'b0);
        check_eq("R-SUB: isStore", info.isStore === 1'b0);
        check_eq("R-SUB: aluUseImmAsRs2", info.aluUseImmAsRs2 === 1'b0);

        // 3) I-type ADDI x1, x2, imm=5
        inst = make_addi(5'd1, 5'd2, 12'd5);
        #1;
        check_eq("I-ADDI: isWriteback", info.isWriteback === 1'b1);
        check_eq("I-ADDI: aluUseImmAsRs2", info.aluUseImmAsRs2 === 1'b1);
        check_eq("I-ADDI: imm == 5", info.imm === 32'sd5);
        check_eq("I-ADDI: rd == 1", info.rd === 5'd1);
        check_eq("I-ADDI: rs1 == 2", info.rs1 === 5'd2);
        check_eq("I-ADDI: rs2 == REG_NR_INVALID_FALLBACK", info.rs2 === REG_NR_INVALID_FALLBACK);
        check_eq("I-ADDI: aluOp == ALU_ADD", info.aluOp === ALU_ADD);
        check_eq("I-ADDI: isLoad", info.isLoad === 1'b0);
        check_eq("I-ADDI: isStore", info.isStore === 1'b0);

        // 4) Load LB x1, 8(x2)
        inst = make_lb(5'd1, 5'd2, 12'd8);
        #1;
        check_eq("LB: isLoad", info.isLoad === 1'b1);
        check_eq("LB: aluUseImmAsRs2", info.aluUseImmAsRs2 === 1'b1);
        check_eq("LB: stldDataLen == DL_BYTE", info.stldDataLen === DL_BYTE);
        check_eq("LB: stldSignedness == SS_SIGNED", info.stldSignedness === SS_SIGNED);
        check_eq("LB: imm == 8", info.imm === 32'sd8);
        check_eq("LB: rd == 1", info.rd === 5'd1);
        check_eq("LB: rs1 == 2", info.rs1 === 5'd2);
        check_eq("LB: rs2 == REG_NR_INVALID_FALLBACK", info.rs2 === REG_NR_INVALID_FALLBACK);
        check_eq("LB: aluOp == ALU_ADD", info.aluOp === ALU_ADD);
        check_eq("LB: isWriteback", info.isWriteback === 1'b1);
        check_eq("LB: isStore", info.isStore === 1'b0);

        // 5) Load LBU x1, 8(x2)
        inst = make_lbu(5'd1, 5'd2, 12'd8);
        #1;
        check_eq("LBU: isLoad", info.isLoad === 1'b1);
        check_eq("LBU: stldDataLen == DL_BYTE", info.stldDataLen === DL_BYTE);
        check_eq("LBU: stldSignedness == SS_UNSIGNED", info.stldSignedness === SS_UNSIGNED);
        check_eq("LBU: aluUseImmAsRs2", info.aluUseImmAsRs2 === 1'b1);
        check_eq("LBU: imm == 8", info.imm === 32'sd8);
        check_eq("LBU: rd == 1", info.rd === 5'd1);
        check_eq("LBU: rs1 == 2", info.rs1 === 5'd2);
        check_eq("LBU: rs2 == REG_NR_INVALID_FALLBACK", info.rs2 === REG_NR_INVALID_FALLBACK);
        check_eq("LBU: aluOp == ALU_ADD", info.aluOp === ALU_ADD);
        check_eq("LBU: isWriteback", info.isWriteback === 1'b1);
        check_eq("LBU: isLoad", info.isLoad === 1'b1);
        check_eq("LBU: isStore", info.isStore === 1'b0);
        check_eq("LBU: isWriteback", info.isWriteback === 1'b1);

        // 6) Store SB x3, 8(x2)
        inst = make_sb(5'd3, 5'd2, 12'd8);
        #1;
        check_eq("SB: isStore", info.isStore === 1'b1);
        check_eq("SB: aluUseImmAsRs2", info.aluUseImmAsRs2 === 1'b1);
        check_eq("SB: stldDataLen == DL_BYTE", info.stldDataLen === DL_BYTE);
        check_eq("SB: imm == 8", info.imm === 32'sd8);
        check_eq("SB: rd == REG_NR_INVALID_FALLBACK", info.rd === REG_NR_INVALID_FALLBACK);
        check_eq("SB: rs1 == 2", info.rs1 === 5'd2);
        check_eq("SB: rs2 == 3", info.rs2 === 5'd3);
        check_eq("SB: aluOp == ALU_ADD", info.aluOp === ALU_ADD);
        check_eq("SB: isWriteback", info.isWriteback === 1'b0);
        check_eq("SB: aluUseImmAsRs2", info.aluUseImmAsRs2 === 1'b1);
        check_eq("SB: isLoad", info.isLoad === 1'b0);
        check_eq("SB: isStore", info.isStore === 1'b1);

        // 7) Branch BEQ x1, x2, offset=4
        inst = make_beq(5'd1, 5'd2, 13'd4);
        #1;
        check_eq("BEQ: branchType == BR_BEQ", info.branchType === BR_BEQ);
        // check_eq("BEQ: isBranch", info.isBranch === 1'b1);
        check_eq("BEQ: imm == 4", info.imm === 32'sd4);
        check_eq("BEQ: rd == REG_NR_INVALID_FALLBACK", info.rd === REG_NR_INVALID_FALLBACK);
        check_eq("BEQ: rs1 == 1", info.rs1 === 5'd1);
        check_eq("BEQ: rs2 == 2", info.rs2 === 5'd2);
        check_eq("BEQ: aluOp == ALU_ADD", info.aluOp === ALU_ADD);
        check_eq("BEQ: isWriteback", info.isWriteback === 1'b0);
        check_eq("BEQ: aluUseImmAsRs2", info.aluUseImmAsRs2 === 1'b1);
        check_eq("BEQ: isLoad", info.isLoad === 1'b0);
        check_eq("BEQ: isStore", info.isStore === 1'b0);

        // 8) Edge: ADDI with negative immediate
        inst = make_addi(5'd1, 5'd2, -12'sd1);
        #1;
        check_eq("I-ADDI: negative imm == -1", info.imm == {32{1'b1}});
        check_eq("I-ADDI: rd == 1", info.rd === 5'd1);
        check_eq("I-ADDI: rs1 == 2", info.rs1 === 5'd2);
        check_eq("I-ADDI: rs2 == REG_NR_INVALID_FALLBACK", info.rs2 === REG_NR_INVALID_FALLBACK);
        check_eq("I-ADDI: aluOp == ALU_ADD", info.aluOp === ALU_ADD);
        check_eq("I-ADDI: isWriteback", info.isWriteback === 1'b1);

        // 9) Edge: LBU with max unsigned immediate
        inst = make_lbu(5'd1, 5'd2, 12'hFFF);
        #1;
        check_eq("LBU: imm == -1", info.imm === -32'sd1);
        check_eq("LBU: rd == 1", info.rd === 5'd1);
        check_eq("LBU: rs1 == 2", info.rs1 === 5'd2);
        check_eq("LBU: rs2 == REG_NR_INVALID_FALLBACK", info.rs2 === REG_NR_INVALID_FALLBACK);
        check_eq("LBU: aluOp == ALU_ADD", info.aluOp === ALU_ADD);
        check_eq("LBU: isLoad", info.isLoad === 1'b1);
        check_eq("LBU: stldDataLen == DL_BYTE", info.stldDataLen === DL_BYTE);
        check_eq("LBU: stldSignedness == SS_UNSIGNED", info.stldSignedness === SS_UNSIGNED);
        check_eq("LBU: aluUseImmAsRs2", info.aluUseImmAsRs2 === 1'b1);

        // 10) Edge: Store with zero immediate
        inst = make_sb(5'd3, 5'd2, 12'd0);
        #1;
        check_eq("SB: zero imm == 0", info.imm === 32'd0);

        // 11) Edge: BEQ with negative offset
        inst = make_beq(5'd1, 5'd2, -13'sd8);
        #1;
        check_eq("BEQ: negative offset == -8", info.imm === -32'sd8);

        // 12) R-type AND x4, x5, x6
        inst = make_and(5'd4, 5'd5, 5'd6);
        #1;
        check_eq("R-AND: aluOp == ALU_AND", info.aluOp === ALU_AND);

        // 13) I-type ORI x7, x8, 0xAA
        inst = make_ori(5'd7, 5'd8, 12'hAA);
        #1;
        check_eq("I-ORI: aluOp == ALU_OR", info.aluOp === ALU_OR);

        // 14) Branch BLTU x9, x10, 0x10
        inst = make_bltu(5'd9, 5'd10, 13'h10);
        #1;
        check_eq("BLTU: branchType == BR_BLTU", info.branchType === BR_BLTU);

        // 15) LUI x11, 0x12345
        inst = make_lui(5'd11, 20'h12345);
        #1;
        check_eq("LUI: rd == 11", info.rd === 5'd11);

        // summary
        #1;
        $display("decoder_tb done: passed=%0d failed=%0d", passed, failed);
        if (failed == 0) $display("ALL TESTS PASSED");
        else $display("SOME TESTS FAILED");
        #1 $finish;
    end

endmodule
