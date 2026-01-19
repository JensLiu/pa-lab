`timescale 1ns / 1ps

module tb_tlb;
    import pkg_virtual_memory::*;
    import pkg_global_defs::*;

    logic clk, rst_n;

    mmu_tlb_if tlb_if ();

    tlb dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .tlb_mmu_if(tlb_if)
    );

    // ---------------- Clock ----------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ---------------- Defaults ----------------
    task automatic drive_defaults();
        tlb_if.lookup_req         = 0;
        tlb_if.lookup_vaddr       = '0;
        tlb_if.lookup_access_type = ACCESS_NONE;
        tlb_if.lookup_satp        = '0;
        tlb_if.lookup_priv        = USER_MODE;

        tlb_if.fill_req           = 0;
        tlb_if.fill_vpn           = '0;
        tlb_if.fill_ppn           = '0;
        tlb_if.fill_perm          = '0;
        tlb_if.fill_satp          = '0;

        tlb_if.flush_req          = 0;
    endtask

    // Reset corto, con señales estables
    task automatic apply_reset_short();
        rst_n = 0;
        drive_defaults();

        // Mantén reset 2 ciclos completos
        repeat (2) @(posedge clk);
        rst_n = 1;

        // margen post-reset
        @(posedge clk);
    endtask

    // VCD limpio
    initial begin
        $dumpfile("build/tb_tlb.vcd");
        $dumpvars(0, tb_tlb);
        $dumpoff;
    end

    // Timeout
    initial begin : timeout
        #20000;
        $fatal(1, "[TB] TIMEOUT: algo se quedo colgado");
    end

    // ============================================================================
    // Helpers: Protocolo drive @negedge, sample después de #1 delay
    //
    // IMPORTANTE: El TLB tiene lógica SECUENCIAL para fill y flush (always_ff).
    // - fill_req=1 presente en posedge -> entrada escrita EN ese posedge
    //   Las asignaciones no-bloqueantes (<=) se ejecutan DESPUÉS del posedge,
    //   por lo que necesitamos un #1 delay para ver los nuevos valores.
    //
    // - flush_req=1 -> igual comportamiento que fill
    //
    // - lookup es COMBINACIONAL: lookup_req=1 -> respuesta inmediata (con #1 para propagar)
    // ============================================================================

    // Flush: asertar en negedge -> DUT procesa en posedge -> esperar #1 para que surta efecto
    task automatic do_flush();
        @(negedge clk);
        tlb_if.flush_req = 1;

        @(posedge clk);  // DUT captura flush_req y ejecuta invalidación
        #1;  // Esperar propagación de asignaciones no-bloqueantes

        @(negedge clk);
        tlb_if.flush_req = 0;
    endtask

    // Fill: asertar en negedge -> DUT escribe en posedge -> esperar #1
    task automatic do_fill(input vpn_t vpn, input ppn_t ppn, input permission_bits_t perm,
                           input satp_register_t satp);
        @(negedge clk);
        tlb_if.fill_req  = 1;
        tlb_if.fill_vpn  = vpn;
        tlb_if.fill_ppn  = ppn;
        tlb_if.fill_perm = perm;
        tlb_if.fill_satp = satp;

        @(posedge clk);  // DUT captura fill_req y escribe entrada
        #1;  // Esperar propagación de asignaciones no-bloqueantes

        @(negedge clk);
        tlb_if.fill_req  = 0;
        tlb_if.fill_vpn  = '0;
        tlb_if.fill_ppn  = '0;
        tlb_if.fill_perm = '0;
        tlb_if.fill_satp = '0;
    endtask

    // Lookup y verificación combinados.
    // Activa lookup, espera propagación combinacional (#1), verifica, y limpia.
    task automatic do_lookup_and_check(input vaddr_t vaddr, input access_type_t acc,
                                       input satp_register_t satp, input priv_mode_t priv,
                                       input logic expect_hit, input paddr_t exp_paddr);
        @(negedge clk);
        tlb_if.lookup_req         = 1;
        tlb_if.lookup_vaddr       = vaddr;
        tlb_if.lookup_access_type = acc;
        tlb_if.lookup_satp        = satp;
        tlb_if.lookup_priv        = priv;

        #1;  // Propagar lógica combinacional

        // Verificar respuesta
        if (!tlb_if.lookup_ready) begin
            $fatal(1, "[TLB] lookup_ready=0 (no respondio)");
        end

        if (expect_hit) begin
            if (!tlb_if.hit) begin
                $fatal(1, "[TLB] esperado HIT, pero fue MISS");
            end
            if (tlb_if.perm_fault) begin
                $fatal(1, "[TLB] perm_fault=1 inesperado");
            end
            if (tlb_if.paddr !== exp_paddr) begin
                $fatal(1, "[TLB] paddr mismatch exp=%h got=%h", exp_paddr, tlb_if.paddr);
            end
            $display("[TLB]   -> HIT OK, paddr=%h", tlb_if.paddr);
        end else begin
            if (tlb_if.hit) begin
                $fatal(1, "[TLB] esperado MISS, pero fue HIT (paddr=%h)", tlb_if.paddr);
            end
            $display("[TLB]   -> MISS OK");
        end

        @(posedge clk);  // Mantener señales un ciclo completo

        @(negedge clk);
        tlb_if.lookup_req         = 0;
        tlb_if.lookup_vaddr       = '0;
        tlb_if.lookup_access_type = ACCESS_NONE;
        tlb_if.lookup_satp        = '0;
        tlb_if.lookup_priv        = USER_MODE;
    endtask

    // ---------------- Tests ----------------
    initial begin : test_seq
        satp_register_t   satp;
        permission_bits_t perm;
        vaddr_t           vaddr;
        vaddr_t vaddr2, vaddr3;  // Declarar aquí, al inicio del bloque
        vaddr_t vaddr_bad;  // Para test de timing incorrecto
        paddr_t exp_paddr;

        apply_reset_short();
        $dumpon;

        // satp mínima
        satp = '0;
        satp.asid = 1;

        perm = '0;
        perm.r = 1;
        perm.w = 1;
        perm.x = 1;
        perm.u = 1;
        perm.a = 1;
        perm.d = 1;

        // -------------------------------------------------------------------------
        $display("\n[TLB] ========== TEST 1: Miss en TLB vacía ==========");
        do_flush();
        vaddr = 32'h1234_5678;
        $display("[TLB] Lookup vaddr=%h", vaddr);
        do_lookup_and_check(vaddr, ACCESS_LOAD, satp, USER_MODE, 1'b0, '0);

        // -------------------------------------------------------------------------
        $display("\n[TLB] ========== TEST 2: Fill + Hit ==========");
        $display("[TLB] Fill: vpn=%h -> ppn=%h", vaddr[31:12], 20'hABCDE);
        do_fill(vaddr[31:12], 20'hABCDE, perm, satp);

        $display("[TLB] Lookup vaddr=%h", vaddr);
        exp_paddr = {20'hABCDE, vaddr[11:0]};
        do_lookup_and_check(vaddr, ACCESS_LOAD, satp, USER_MODE, 1'b1, exp_paddr);

        // -------------------------------------------------------------------------
        $display("\n[TLB] ========== TEST 3: Flush -> Miss ==========");
        do_flush();
        $display("[TLB] Lookup vaddr=%h post-flush", vaddr);
        do_lookup_and_check(vaddr, ACCESS_LOAD, satp, USER_MODE, 1'b0, '0);

        // -------------------------------------------------------------------------
        $display("\n[TLB] ========== TEST 4: Múltiples entradas ==========");
        vaddr2 = 32'hAAAA_0000;
        vaddr3 = 32'hBBBB_1234;

        $display("[TLB] Fill: vpn=%h -> ppn=%h", vaddr[31:12], 20'h11111);
        do_fill(vaddr[31:12], 20'h11111, perm, satp);

        $display("[TLB] Fill: vpn=%h -> ppn=%h", vaddr2[31:12], 20'h22222);
        do_fill(vaddr2[31:12], 20'h22222, perm, satp);

        $display("[TLB] Fill: vpn=%h -> ppn=%h", vaddr3[31:12], 20'h33333);
        do_fill(vaddr3[31:12], 20'h33333, perm, satp);

        $display("[TLB] Verificando entrada 1...");
        do_lookup_and_check(vaddr, ACCESS_LOAD, satp, USER_MODE, 1'b1, {20'h11111, vaddr[11:0]});

        $display("[TLB] Verificando entrada 2...");
        do_lookup_and_check(vaddr2, ACCESS_LOAD, satp, USER_MODE, 1'b1, {20'h22222, vaddr2[11:0]});

        $display("[TLB] Verificando entrada 3...");
        do_lookup_and_check(vaddr3, ACCESS_LOAD, satp, USER_MODE, 1'b1, {20'h33333, vaddr3[11:0]});

        // -------------------------------------------------------------------------
        $display("\n[TLB] ========== TEST 5: Fill en posedge (timing incorrecto) ==========");
        // Este test demuestra qué pasa si mandas fill_req justo en el posedge
        // en lugar de en el negedge. El DUT no captura el fill en ese ciclo.
        do_flush();

        vaddr_bad = 32'hDEAD_BEEF;

        $display("[TLB] Fill INCORRECTO: enviando fill_req en posedge");
        @(posedge clk);  // Esperamos al posedge
        // Cambiamos señales JUSTO DESPUÉS del posedge (el always_ff ya muestreó)
        tlb_if.fill_req  = 1;
        tlb_if.fill_vpn  = vaddr_bad[31:12];
        tlb_if.fill_ppn  = 20'hBAD00;
        tlb_if.fill_perm = perm;
        tlb_if.fill_satp = satp;

        // Lookup inmediato en el mismo "ciclo" - debería ser MISS
        // porque el fill aún no ha sido capturado por el DUT
        #1;
        tlb_if.lookup_req         = 1;
        tlb_if.lookup_vaddr       = vaddr_bad;
        tlb_if.lookup_access_type = ACCESS_LOAD;
        tlb_if.lookup_satp        = satp;
        tlb_if.lookup_priv        = USER_MODE;
        #1;

        $display("[TLB]   fill_req=%b, lookup_req=%b", tlb_if.fill_req, tlb_if.lookup_req);
        $display("[TLB]   hit=%b (esperado: 0, porque fill no fue capturado aún)", tlb_if.hit);

        if (tlb_if.hit) begin
            $display(
                "[TLB]   NOTA: hit=1, el fill se vio instantáneamente (comportamiento combinacional inesperado)");
        end else begin
            $display("[TLB]   CORRECTO: hit=0, el fill no ha sido procesado por always_ff");
        end

        // Ahora esperamos al siguiente posedge donde SÍ se captura el fill
        @(posedge clk);
        #1;
        $display("[TLB] Después del posedge: verificando que ahora SÍ hay hit");

        // El fill debería estar ahora en el TLB
        tlb_if.lookup_vaddr = vaddr_bad;
        #1;

        if (tlb_if.hit) begin
            $display("[TLB]   -> HIT OK: el fill fue capturado en el posedge anterior");
        end else begin
            $display("[TLB]   -> Aún MISS: necesita otro ciclo");
        end

        // Limpiar
        @(negedge clk);
        tlb_if.fill_req   = 0;
        tlb_if.lookup_req = 0;
        drive_defaults();

        // -------------------------------------------------------------------------
        $display("\n[TLB] ========== ALL TESTS PASSED ==========");
        $finish;
    end

endmodule
