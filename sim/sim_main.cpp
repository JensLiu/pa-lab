#include "Vdatapath_pipelined.h"
#include "Vdatapath_pipelined___024root.h"
#include "Vdatapath_pipelined_pkg_global_defs.h"
#include "riscv_instructions.hpp"
#include "verilated.h"
#include <assert.h>
#include <ctime>
#include <fstream>
#include <iostream>
#include <unordered_map>

#define DATA_OF(x, y) x##__DOT__##y
#define DATA_OF_PIPELINE(x) DATA_OF(datapath_pipelined, x)
#define DATA_PRIVATE(x) __PVT__##x

typedef Vdatapath_pipelined SimClass;

enum PipelineStageID {
  STAGE_IF = 0,
  STAGE_ID = 1,
  STAGE_EX = 2,
  STAGE_MEM = 3,
  STAGE_WB = 4,
};

auto pipeline_stage_id_to_string(const PipelineStageID stage) -> std::string {
  switch (stage) {
  case STAGE_IF:
    return "IF";
  case STAGE_ID:
    return "ID";
  case STAGE_EX:
    return "EX";
  case STAGE_MEM:
    return "MEM";
  case STAGE_WB:
    return "WB";
  default:
    return "UNKNOWN";
  }
}

struct PipelineStageState {
  const int id;
  const PipelineStageID stage;
  const uint32_t pc;
  const RISCVInstructions::DecodedInstruction instruction;
  const bool is_nop; // true if this is a NOP (PC == 0)

public:
  PipelineStageState(const uint32_t id, const PipelineStageID stage,
                     const uint32_t pc,
                     const RISCVInstructions::DecodedInstruction instruction)
      : id(id), stage(stage), pc(pc), instruction(instruction),
        is_nop(pc == 0) {}
};

class OnikiriGenerator {
  static auto gen_first_encounter_inner(const PipelineStageState &state)
      -> std::string {
    std::string asm_str =
        RISCVInstructions::RISCVDecoder::toAssembly(state.instruction);
    std::string onikiri_declare = "I\t" + std::to_string(state.id) + "\t" +
                                  std::to_string(state.pc) + "\t" + "0";
    std::string onikiri_comment =
        "L\t" + std::to_string(state.id) + "\t0\t" + asm_str;
    return onikiri_declare + "\n" + onikiri_comment;
  }

  static auto gen_stage_inner(const PipelineStageState &state) -> std::string {
    std::string onikiri_stage = "S\t" + std::to_string(state.id) + "\t0\t" +
                                pipeline_stage_id_to_string(state.stage);
    return onikiri_stage;
  }

public:
  static auto gen_stage(const PipelineStageState &state) -> std::string {
    std::string onikiri_str;
    // Declare instruction when first seen in IF stage (and it's not a NOP)
    if (state.stage == STAGE_IF && !state.is_nop) {
      onikiri_str += gen_first_encounter_inner(state) + "\n";
    }
    // Always show stage transition
    onikiri_str += gen_stage_inner(state);
    return onikiri_str;
  }

  static auto gen_flush(const int32_t inst_id, const PipelineStageState &state)
      -> std::string {
    std::string onikiri_flush = "F\t" + std::to_string(inst_id) + "\t0\t" +
                                pipeline_stage_id_to_string(state.stage);
    return onikiri_flush;
  }

  static auto gen_next_cycle() -> std::string { return "C\t1"; }

  static auto gen_header(const int start_cycle = 0) -> std::string {
    return "Kanata\t0004\nC=\t" + std::to_string(start_cycle);
  }
};

class PipelineStageLogger {
private:
  const SimClass *sim;
  const std::string dumpfile;
  uint64_t tick;
  std::unordered_set<int32_t> instructions_flushed;

public:
  void test() {
    const auto &if_id_regs_p = sim->rootp->DATA_OF_PIPELINE(ifIdRegsP);
    const auto &id_ex_regs_p = sim->rootp->DATA_OF_PIPELINE(idExRegsP);
    const auto &ex_mem_regs_p = sim->rootp->DATA_OF_PIPELINE(exMemRegsP);
    const auto &mem_wb_regs_p = sim->rootp->DATA_OF_PIPELINE(memWbRegsP);
    const auto &mem_wb_regs_P = sim->rootp->DATA_OF_PIPELINE(memWbRegsP);

    const auto &if_control = sim->rootp->DATA_OF_PIPELINE(ifControl);
    const auto &id_control = sim->rootp->DATA_OF_PIPELINE(idControl);
    // const auto &if_hints = sim->rootp->DATA_OF_PIPELINE(ifControl);
    const auto &id_hints = sim->rootp->DATA_OF_PIPELINE(idHints);

    std::unordered_map<int32_t, PipelineStageID> valid_instructions;
    {
      const int32_t if_inst_id = if_id_regs_p.DATA_PRIVATE(DEBUG_instID);
      const int32_t id_inst_id =
          id_ex_regs_p.DATA_PRIVATE(instInfo).DATA_PRIVATE(DEBUG_instID);
      const int32_t ex_inst_id =
          ex_mem_regs_p.DATA_PRIVATE(instInfo).DATA_PRIVATE(DEBUG_instID);
      const int32_t mem_inst_id =
          mem_wb_regs_p.DATA_PRIVATE(instInfo).DATA_PRIVATE(DEBUG_instID);
      const int32_t wb_inst_id =
          mem_wb_regs_p.DATA_PRIVATE(instInfo).DATA_PRIVATE(DEBUG_instID);
      std::unordered_map<int32_t, std::set<PipelineStageID>>
          current_instructions;
      current_instructions[if_inst_id].insert(STAGE_IF);
      current_instructions[id_inst_id].insert(STAGE_ID);
      current_instructions[ex_inst_id].insert(STAGE_EX);
      current_instructions[mem_inst_id].insert(STAGE_MEM);
      current_instructions[wb_inst_id].insert(STAGE_WB);

      for (const auto &pair : current_instructions) {
        const int32_t inst_id = pair.first;
        const PipelineStageID last_stage = *pair.second.rbegin();
        valid_instructions[inst_id] = last_stage;
      }
    }

    for (const auto &pair : valid_instructions) {
      const int32_t inst_id = pair.first;
      const PipelineStageID last_stage = pair.second;
      switch (last_stage) {
      case STAGE_IF: {
        const auto &if_states = get_if_states();
        break;
      }
      case STAGE_ID: {
        const auto &id_states = get_id_states();
        break;
      }
      case STAGE_EX: {
        const auto &ex_states = get_ex_states();
        break;
      }
      case STAGE_MEM: {
        const auto &mem_states = get_mem_states();
        break;
      }
      case STAGE_WB: {
        const auto &wb_states = get_wb_states();
        break;
      }
      default:
        assert(false && "Invalid pipeline stage");
      }
    }
  }
  auto get_if_states() -> PipelineStageState {
    const auto &if_id_regs_p = sim->rootp->DATA_OF_PIPELINE(ifIdRegsP);
    const auto &if_control = sim->rootp->DATA_OF_PIPELINE(ifControl);
    // const auto &if_hints = sim->rootp->DATA_OF_PIPELINE(ifControl);
    const uint32_t id = if_id_regs_p.DATA_PRIVATE(DEBUG_instID);
    const uint32_t pc = if_id_regs_p.DATA_PRIVATE(pc);
    const uint32_t inst = (uint32_t)if_id_regs_p.DATA_PRIVATE(inst);
    const auto &instruction = RISCVInstructions::RISCVDecoder::decode(inst);
    return {id, STAGE_IF, pc, instruction};
  }
  auto get_id_states() -> PipelineStageState {
    const auto &if_id_regs_q = sim->rootp->DATA_OF_PIPELINE(ifIdRegsQ);
    const auto &id_ex_regs_p = sim->rootp->DATA_OF_PIPELINE(idExRegsP);
    const auto &id_control = sim->rootp->DATA_OF_PIPELINE(ifControl);
    const auto &id_hints = sim->rootp->DATA_OF_PIPELINE(ifControl);
    const uint32_t id =
        id_ex_regs_p.DATA_PRIVATE(instInfo).DATA_PRIVATE(DEBUG_instID);
    const uint32_t pc = id_ex_regs_p.DATA_PRIVATE(pc);
    const uint32_t inst =
        (uint32_t)id_ex_regs_p.DATA_PRIVATE(instInfo).DATA_PRIVATE(
            DEBUG_instBinary);
    const auto &instruction = RISCVInstructions::RISCVDecoder::decode(inst);
    return {id, STAGE_ID, pc, instruction};
  }

  auto get_ex_states() -> PipelineStageState {
    const auto &id_ex_regs_q = sim->rootp->DATA_OF_PIPELINE(idExRegsQ);
    const auto &ex_mem_regs_p = sim->rootp->DATA_OF_PIPELINE(exMemRegsP);
    const auto &ex_control = sim->rootp->DATA_OF_PIPELINE(idControl);
    const auto &ex_hints = sim->rootp->DATA_OF_PIPELINE(idHints);
    const uint32_t id =
        ex_mem_regs_p.DATA_PRIVATE(instInfo).DATA_PRIVATE(DEBUG_instID);
    const uint32_t pc = ex_mem_regs_p.DATA_PRIVATE(pc);
    const uint32_t inst =
        (uint32_t)ex_mem_regs_p.DATA_PRIVATE(instInfo).DATA_PRIVATE(
            DEBUG_instBinary);
    const auto &instruction = RISCVInstructions::RISCVDecoder::decode(inst);
    return {id, STAGE_EX, pc, instruction};
  }

  auto get_mem_states() -> PipelineStageState {
    const auto &ex_mem_regs_q = sim->rootp->DATA_OF_PIPELINE(exMemRegsQ);
    const auto &mem_wb_regs_p = sim->rootp->DATA_OF_PIPELINE(memWbRegsP);
    // const auto &mem_control = sim->rootp->DATA_OF_PIPELINE(exControl);
    const auto &mem_hints = sim->rootp->DATA_OF_PIPELINE(exHints);
    const uint32_t id =
        mem_wb_regs_p.DATA_PRIVATE(instInfo).DATA_PRIVATE(DEBUG_instID);
    const uint32_t pc = mem_wb_regs_p.DATA_PRIVATE(pc);
    const uint32_t inst =
        (uint32_t)mem_wb_regs_p.DATA_PRIVATE(instInfo).DATA_PRIVATE(
            DEBUG_instBinary);
    const auto &instruction = RISCVInstructions::RISCVDecoder::decode(inst);
    return {id, STAGE_MEM, pc, instruction};
  }

  auto get_wb_states() -> PipelineStageState {
    const auto &mem_wb_regs_q = sim->rootp->DATA_OF_PIPELINE(memWbRegsQ);
    // const auto &wb_control = sim->rootp->DATA_OF_PIPELINE(memControl);
    const auto &wb_hints = sim->rootp->DATA_OF_PIPELINE(memHints);
    const uint32_t id =
        mem_wb_regs_q.DATA_PRIVATE(instInfo).DATA_PRIVATE(DEBUG_instID);
    const uint32_t pc = mem_wb_regs_q.DATA_PRIVATE(pc);
    const uint32_t inst =
        (uint32_t)mem_wb_regs_q.DATA_PRIVATE(instInfo).DATA_PRIVATE(
            DEBUG_instBinary);
    const auto &instruction = RISCVInstructions::RISCVDecoder::decode(inst);
    return {id, STAGE_WB, pc, instruction};
  }

  auto state_info_print() {
    const auto &if_states = get_if_states();
    const auto &id_states = get_id_states();
    const auto &ex_states = get_ex_states();
    const auto &mem_states = get_mem_states();
    const auto &wb_states = get_wb_states();
    std::cout << "=== Cycle " << tick << " ===" << std::endl;
    std::cout << "WB: PC=0x" << std::hex << wb_states.pc
              << "\tINST_ID=" << wb_states.id << "\tINST="
              << RISCVInstructions::RISCVDecoder::toAssembly(
                     wb_states.instruction)
              << std::endl;
    std::cout << "MEM: PC=0x" << std::hex << mem_states.pc
              << "\tINST_ID=" << mem_states.id << "\tINST="
              << RISCVInstructions::RISCVDecoder::toAssembly(
                     mem_states.instruction)
              << std::endl;
    std::cout << "EX: PC=0x" << std::hex << ex_states.pc
              << "\tINST_ID=" << ex_states.id << "\tINST="
              << RISCVInstructions::RISCVDecoder::toAssembly(
                     ex_states.instruction)
              << std::endl;
    std::cout << "ID: PC=0x" << std::hex << id_states.pc
              << "\tINST_ID=" << id_states.id << "\tINST="
              << RISCVInstructions::RISCVDecoder::toAssembly(
                     id_states.instruction)
              << std::endl;
    std::cout << "IF: PC=0x" << std::hex << if_states.pc
              << "\tINST_ID=" << if_states.id << "\tINST="
              << RISCVInstructions::RISCVDecoder::toAssembly(
                     if_states.instruction)
              << std::endl;
    std::cout << std::endl;
  }

  // auto onikiri_format_gen() -> std::string {
  //   for (const auto &inst_id : instructions_flushed) {
  //     // Generate retire event for flushed instructions
  //     onikiri_str += OnikiriGenerator::gen_retire(flushed_state) + "\n";
  //   }
  //   instructions_flushed.clear();
  //   return onikiri_str;
  // }

  // void onikiri_write() {
  //   std::string onikiri_str = onikiri_format_gen();
  //   if (dumpfile.empty()) {
  //     std::cout << onikiri_str << std::endl;
  //     return;
  //   }
  //   std::ios_base::openmode mode =
  //       std::ios::out | (tick == 0 ? std::ios::trunc : std::ios::app);
  //   std::ofstream ofs(dumpfile, mode);
  //   if (!ofs) {
  //     std::cerr << "Failed to open dumpfile: " << dumpfile << std::endl;
  //     return;
  //   }
  //   ofs << onikiri_str << std::endl;
  // }

  void on_tick() {
    // onikiri_write();
    state_info_print();
    tick++;
  }

public:
  PipelineStageLogger(const SimClass *sim, std::string dumpfile)
      : sim(sim), dumpfile(dumpfile), tick(0) {}
};

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);

  SimClass *sim = new SimClass;
  const std::string dumpfile = "simulation.log";
  PipelineStageLogger logger(sim, dumpfile);

  for (int cycle = 0; cycle < 15; cycle++) {
    sim->clk = 0;
    sim->eval();

    // raising clock edge
    logger.on_tick();

    sim->clk = 1;
    sim->eval();
  }
}