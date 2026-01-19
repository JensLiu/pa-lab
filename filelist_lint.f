# Lint-only filelist: packages + RTL modules (no testbenches)
# packages (dependency order)
includes/pkg_riscv_instructions.sv
includes/pkg_virtual_memory.sv
includes/pkg_global_defs.sv

# include helpers / interfaces
rtl/cache/cache_request_if.sv
rtl/cache/cache_hit_query_if.sv
rtl/cache/cache_writeonly_request_if.sv
rtl/memory/mem_request_if.sv
rtl/reorder_buffer/rob_reg_query_if.sv
rtl/reorder_buffer/rob_store_query_if.sv
rtl/reorder_buffer/rob_ticket_request_if.sv
rtl/store_buffer/store_buffer_request_if.sv
rtl/virtual_memory/inner/cpu_mmmu_if.sv
rtl/virtual_memory/inner/mmu_pw_if.sv
rtl/virtual_memory/inner/mmu_tlb_if.sv
rtl/virtual_memory/inner/pw_cache_if.sv

# RTL (top-level and submodules)
// rtl/datapath/datapath_pipelined.sv
// rtl/datapath/if_stage.sv
// rtl/datapath/id_stage.sv
// rtl/datapath/ex_stage.sv
// rtl/datapath/mem_stage.sv
// rtl/datapath/wb_stage.sv
// rtl/datapath.sv
// rtl/alu.sv
// rtl/comparator.sv
// rtl/decoder.sv
// rtl/register_file.sv
// rtl/memory.sv
// rtl/memory_inst.sv
// rtl/memory_data.sv
// rtl/cache.sv
