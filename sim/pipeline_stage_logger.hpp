#ifndef SIM_PIPELINE_STAGE_LOGGER_HPP
#define SIM_PIPELINE_STAGE_LOGGER_HPP
#include "riscv_instructions.hpp"
#include "verilated.h"
#include <assert.h>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <unordered_map>

#define DATAPATH_USE_STORE_BUFFER

#define DATA_ACCESS_1(x) x
#define DATA_ACCESS_2(x, y) x##__DOT__##y
#define DATA_ACCESS_3(x, y, z) x##__DOT__##y##__DOT__##z
#define DATA_ACCESS_4(x, y, z, w) x##__DOT__##y##__DOT__##z##__DOT__##w
#define DATA_ACCESS_5(x, y, z, w, v)                                           \
  x##__DOT__##y##__DOT__##z##__DOT__##w##__DOT__##v
#define DATA_ACCESS_6(x, y, z, w, v, u)                                        \
  x##__DOT__##y##__DOT__##z##__DOT__##w##__DOT__##v##__DOT__##u
#define DATA_ACCESS_GET_MACRO(_1, _2, _3, _4, _5, _6, NAME, ...) NAME
#define DATA_ACCESS(...)                                                       \
  DATA_ACCESS_GET_MACRO(__VA_ARGS__, DATA_ACCESS_6, DATA_ACCESS_5,             \
                        DATA_ACCESS_4, DATA_ACCESS_3, DATA_ACCESS_2,           \
                        DATA_ACCESS_1)(__VA_ARGS__)
#define PIPELINE_ACCESS(...) DATA_ACCESS(datapath_pipelined, __VA_ARGS__)
#define DATA_PRIVATE(x) __PVT__##x
#define PIPELINE_PRIVATE_ACCESS(...)                                           \
  DATA_ACCESS(__PVT__datapath_pipelined, __VA_ARGS__)

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

static std::unordered_map<int32_t, std::string> cache_state_string = {
    {0, "IDLE"}, {1, "EVICT_WAIT"}, {2, "REFILL_WAIT"}, {3, "DONE"}};

static std::unordered_map<int32_t, std::string> memory_state_string = {
    {0, "IDLE"}, {1, "MOCK_DELAY"}, {2, "DONE"}};

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

enum {
  CACHE_STATE_IDLE = 0,
  CACHE_STATE_EVICT_WAIT = 1,
  CACHE_STATE_REFILL_WAIT = 2,
  CACHE_STATE_DONE = 3
};

template <typename SimClass> class PipelineStageLogger {
private:
  const SimClass *sim;
  std::ostream &os;
  uint64_t tick;
  std::unordered_set<int32_t> instructions_flushed;
  std::unordered_map<std::string, double> metric_counters;

public:
  void collect_cache_metrics() {
    {
      const auto &inst_cache_current_state =
          sim->rootp->PIPELINE_ACCESS(instructionCache, currentState);
      const auto &inst_cache_next_satate =
          sim->rootp->PIPELINE_ACCESS(instructionCache, nextState);
      if (inst_cache_current_state == CACHE_STATE_IDLE &&
          inst_cache_next_satate != CACHE_STATE_IDLE) {
        metric_counters["inst_cache_miss"]++;
      }
    }
    {
#ifdef DATAPATH_USE_STORE_BUFFER
      const auto &data_cache_current_state =
          sim->rootp->PIPELINE_ACCESS(storeBuffer, dataCache, currentState);
      const auto &data_cache_next_satate =
          sim->rootp->PIPELINE_ACCESS(storeBuffer, dataCache, nextState);
#else
      const auto &data_cache_current_state =
          sim->rootp->PIPELINE_ACCESS(dataCache, currentState);
      const auto &data_cache_next_satate =
          sim->rootp->PIPELINE_ACCESS(dataCache, nextState);
#endif
      if (data_cache_current_state == CACHE_STATE_IDLE &&
          data_cache_next_satate != CACHE_STATE_IDLE) {
        metric_counters["data_cache_miss"]++;
      }
    }
    {
#ifdef DATAPATH_USE_STORE_BUFFER
#else
      const auto &data_cache_current_state =
          sim->rootp->PIPELINE_ACCESS(dataCache, currentState);
      const auto &data_cache_next_satate =
          sim->rootp->PIPELINE_ACCESS(dataCache, nextState);
      if (data_cache_current_state == CACHE_STATE_IDLE &&
          data_cache_next_satate != CACHE_STATE_IDLE) {
        metric_counters["data_cache_miss"]++;
      }
#endif
    }
  }

  void collect_pipeline_metrics() {
    {
      const auto &if_should_halt =
          sim->rootp->PIPELINE_ACCESS(ifHints).DATA_PRIVATE(shouldHalt);
      if (if_should_halt) {
        metric_counters["if_stage_halts"]++;
      }
    }
    {
      const auto &id_should_halt =
          sim->rootp->PIPELINE_ACCESS(idHints).DATA_PRIVATE(shouldHalt);
      if (id_should_halt) {
        metric_counters["id_stage_halts"]++;
      }
    }
    {
      const auto &ex_should_halt =
          sim->rootp->PIPELINE_ACCESS(exHints).DATA_PRIVATE(shouldHalt);
      if (ex_should_halt) {
        metric_counters["ex_stage_halts"]++;
      }
    }
    {
      const auto &mem_should_halt =
          sim->rootp->PIPELINE_ACCESS(memHints).DATA_PRIVATE(shouldHalt);
      if (mem_should_halt) {
        metric_counters["mem_stage_halts"]++;
      }
    }
  }

  void collect_metrics() {
    collect_cache_metrics();
    collect_pipeline_metrics();
  }

  void test() {
    const auto &if_id_regs_p = sim->rootp->PIPELINE_ACCESS(ifIdRegsP);
    const auto &id_ex_regs_p = sim->rootp->PIPELINE_ACCESS(idExRegsP);
    const auto &ex_mem_regs_p = sim->rootp->PIPELINE_ACCESS(exMemRegsP);
    const auto &mem_wb_regs_p = sim->rootp->PIPELINE_ACCESS(memWbRegsP);
    const auto &mem_wb_regs_P = sim->rootp->PIPELINE_ACCESS(memWbRegsP);

    const auto &if_control = sim->rootp->PIPELINE_ACCESS(ifControl);
    const auto &id_control = sim->rootp->PIPELINE_ACCESS(idControl);
    // const auto &if_hints = sim->rootp->PIPELINE_ACCESS(ifControl);
    const auto &id_hints = sim->rootp->PIPELINE_ACCESS(idHints);

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
    const auto &if_id_regs_p = sim->rootp->PIPELINE_ACCESS(ifIdRegsP);
    const auto &if_control = sim->rootp->PIPELINE_ACCESS(ifControl);
    // const auto &if_hints = sim->rootp->PIPELINE_ACCESS(ifControl);
    const uint32_t id = if_id_regs_p.DATA_PRIVATE(DEBUG_instID);
    const uint32_t pc = if_id_regs_p.DATA_PRIVATE(pc);
    const uint32_t inst = (uint32_t)if_id_regs_p.DATA_PRIVATE(inst);
    const auto &instruction = RISCVInstructions::RISCVDecoder::decode(inst);
    return {id, STAGE_IF, pc, instruction};
  }
  auto get_id_states() -> PipelineStageState {
    const auto &if_id_regs_q = sim->rootp->PIPELINE_ACCESS(ifIdRegsQ);
    const auto &id_ex_regs_p = sim->rootp->PIPELINE_ACCESS(idExRegsP);
    const auto &id_control = sim->rootp->PIPELINE_ACCESS(ifControl);
    const auto &id_hints = sim->rootp->PIPELINE_ACCESS(ifControl);
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
    const auto &id_ex_regs_q = sim->rootp->PIPELINE_ACCESS(idExRegsQ);
    const auto &ex_mem_regs_p = sim->rootp->PIPELINE_ACCESS(exMemRegsP);
    const auto &ex_control = sim->rootp->PIPELINE_ACCESS(idControl);
    const auto &ex_hints = sim->rootp->PIPELINE_ACCESS(idHints);
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
    const auto &ex_mem_regs_q = sim->rootp->PIPELINE_ACCESS(exMemRegsQ);
    const auto &mem_wb_regs_p = sim->rootp->PIPELINE_ACCESS(memWbRegsP);
    // const auto &mem_control = sim->rootp->PIPELINE_ACCESS(exControl);
    const auto &mem_hints = sim->rootp->PIPELINE_ACCESS(exHints);
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
    const auto &mem_wb_regs_q = sim->rootp->PIPELINE_ACCESS(memWbRegsQ);
    // const auto &wb_control = sim->rootp->PIPELINE_ACCESS(memControl);
    const auto &wb_hints = sim->rootp->PIPELINE_ACCESS(memHints);
    const uint32_t id =
        mem_wb_regs_q.DATA_PRIVATE(instInfo).DATA_PRIVATE(DEBUG_instID);
    const uint32_t pc = mem_wb_regs_q.DATA_PRIVATE(pc);
    const uint32_t inst =
        (uint32_t)mem_wb_regs_q.DATA_PRIVATE(instInfo).DATA_PRIVATE(
            DEBUG_instBinary);
    const auto &instruction = RISCVInstructions::RISCVDecoder::decode(inst);
    return {id, STAGE_WB, pc, instruction};
  }

  void stage_state_dump() {
    const auto &if_states = get_if_states();
    const auto &id_states = get_id_states();
    const auto &ex_states = get_ex_states();
    const auto &mem_states = get_mem_states();
    const auto &wb_states = get_wb_states();
    os << "=== Cycle " << tick << " ===" << std::endl;
    os << "IF: PC=0x" << std::hex << if_states.pc
       << "\tINST_ID=" << if_states.id << "\tINST="
       << RISCVInstructions::RISCVDecoder::toAssembly(if_states.instruction)
       << std::endl;
    os << "ID: PC=0x" << std::hex << id_states.pc
       << "\tINST_ID=" << id_states.id << "\tINST="
       << RISCVInstructions::RISCVDecoder::toAssembly(id_states.instruction)
       << std::endl;
    os << "EX: PC=0x" << std::hex << ex_states.pc
       << "\tINST_ID=" << ex_states.id << "\tINST="
       << RISCVInstructions::RISCVDecoder::toAssembly(ex_states.instruction)
       << std::endl;
    os << "MEM: PC=0x" << std::hex << mem_states.pc
       << "\tINST_ID=" << mem_states.id << "\tINST="
       << RISCVInstructions::RISCVDecoder::toAssembly(mem_states.instruction)
       << std::endl;
    os << "WB: PC=0x" << std::hex << wb_states.pc
       << "\tINST_ID=" << wb_states.id << "\tINST="
       << RISCVInstructions::RISCVDecoder::toAssembly(wb_states.instruction)
       << std::endl;
    os << std::endl;
  }

  void inst_cache_state_dump() {
    const auto &current_state =
        sim->rootp->PIPELINE_ACCESS(instructionCache, currentState);
    const auto &next_state =
        sim->rootp->PIPELINE_ACCESS(instructionCache, nextState);
    const auto &target_way_idx =
        sim->rootp->PIPELINE_ACCESS(instructionCache, targetWayIdx);
    const auto &victim_addr =
        sim->rootp->PIPELINE_ACCESS(instructionCache, victimAddrAligned);
    const auto &cache_mem =
        sim->rootp->PIPELINE_ACCESS(instructionCache, cacheMem);
    const auto &policy_metadata =
        sim->rootp->PIPELINE_ACCESS(instructionCache, policyMetadata);
    const auto &is_hit = sim->rootp->PIPELINE_ACCESS(instructionCache, isHit);
    const auto &is_set_full =
        sim->rootp->PIPELINE_ACCESS(instructionCache, isSetFull);
    const auto &is_victim_dirty =
        sim->rootp->PIPELINE_ACCESS(instructionCache, isVictimDirty);
    const auto &cpu_request =
        sim->rootp->PIPELINE_PRIVATE_ACCESS(instCacheCpuRequest);
    const auto &mem_request =
        sim->rootp->PIPELINE_PRIVATE_ACCESS(instCacheMemRequest);

    os << "Instruction Cache State:" << std::endl;
    os << "  Is Hit: " << (is_hit ? "Yes" : "No") << std::endl;
    os << "  Current State: " << cache_state_string.at(current_state)
       << std::endl;
    os << "  Next State: " << cache_state_string.at(next_state) << std::endl;
    os << "  Target Way Index: " << static_cast<int>(target_way_idx)
       << std::endl;
    os << "  Victim Address: 0x" << std::hex << victim_addr << std::dec
       << std::endl;
    os << "  Is Set Full: " << (is_set_full ? "Yes" : "No") << std::endl;
    os << "  Is Victim Dirty: " << (is_victim_dirty ? "Yes" : "No")
       << std::endl;

    // os << "  CPU Request Interface: "
    //   //  << "Request=" <<
    //   static_cast<int>(cpu_request->DATA_ACCESS(request))
    //    << ", Ready=" << static_cast<int>(cpu_request->DATA_ACCESS(ready))
    //   //  << ", Addr=0x" << std::hex << cpu_request->DATA_ACCESS(addr)
    //    << ", DataFromCache=0x" << cpu_request->DATA_ACCESS(dataFromCache)
    //    << std::dec << ", DataToCache=0x"
    //    << cpu_request->DATA_ACCESS(dataToCache) << std::dec
    //    << ", isRead=" << static_cast<int>(cpu_request->DATA_ACCESS(isRead))
    //    << std::endl;
    // os << "  Memory Request Interface: "
    //    << "Request=" << static_cast<int>(mem_request->DATA_ACCESS(request))
    //    << ", Ready=" << static_cast<int>(mem_request->DATA_ACCESS(ready))
    //    << ", Addr=0x" << std::hex << mem_request->DATA_ACCESS(addr)
    //    << ", DataFromMem=0x" << mem_request->DATA_ACCESS(dataFromMem)
    //    << std::dec << ", DataToMem=0x" << mem_request->DATA_ACCESS(dataToMem)
    //    << std::dec
    //    << ", isRead=" << static_cast<int>(mem_request->DATA_ACCESS(isRead))
    //    << std::endl;
    os << "  Cache Memory Contents:" << std::endl;
    for (size_t set_idx = 0; set_idx < cache_mem.size(); ++set_idx) {
      for (size_t way_idx = 0; way_idx < cache_mem[set_idx].size(); ++way_idx) {
        const auto &line = cache_mem[set_idx][way_idx];
        os << "    Set " << set_idx << ", Way " << way_idx << ": "
           << "Tag=0x" << std::hex << line.DATA_PRIVATE(tag)
           << ", Valid=" << static_cast<int>(line.DATA_PRIVATE(valid))
           << ", Dirty=" << static_cast<int>(line.DATA_PRIVATE(dirty))
           << ", Data=[";
        ;
        for (size_t byte_idx = 0; byte_idx < 16; ++byte_idx) {
          os << std::hex
             << ((line.DATA_PRIVATE(data)[byte_idx / 8] >>
                  ((byte_idx % 8) * 8)) &
                 0xFF);
          if (byte_idx != 15)
            os << " ";
        }
        os << "]" << std::dec << std::endl;
      }
    }

    os << std::endl;
  }

  void data_cache_state_dump() {
#ifdef DATAPATH_USE_STORE_BUFFER
    const auto &current_state =
        sim->rootp->PIPELINE_ACCESS(storeBuffer, dataCache, currentState);
    const auto &next_state =
        sim->rootp->PIPELINE_ACCESS(storeBuffer, dataCache, nextState);
    const auto &target_way_idx =
        sim->rootp->PIPELINE_ACCESS(storeBuffer, dataCache, targetWayIdx);
    const auto &victim_addr =
        sim->rootp->PIPELINE_ACCESS(storeBuffer, dataCache, victimAddr);
    const auto &cache_mem =
        sim->rootp->PIPELINE_ACCESS(storeBuffer, dataCache, cacheMem);
    const auto &policy_metadata =
        sim->rootp->PIPELINE_ACCESS(storeBuffer, dataCache, policyMetadata);
#else
    const auto &current_state =
        sim->rootp->PIPELINE_ACCESS(dataCache, currentState);
    const auto &next_state = sim->rootp->PIPELINE_ACCESS(dataCache, nextState);
    const auto &target_way_idx =
        sim->rootp->PIPELINE_ACCESS(dataCache, targetWayIdx);
    const auto &victim_addr =
        sim->rootp->PIPELINE_ACCESS(dataCache, victimAddr);
    const auto &cache_mem = sim->rootp->PIPELINE_ACCESS(dataCache, cacheMem);
    const auto &policy_metadata =
        sim->rootp->PIPELINE_ACCESS(dataCache, policyMetadata);
#endif
    os << "Data Cache State:" << std::endl;
    os << "  Current State: " << cache_state_string.at(current_state)
       << std::endl;
    os << "  Next State: " << cache_state_string.at(next_state) << std::endl;
    os << "  Target Way Index: " << static_cast<int>(target_way_idx)
       << std::endl;
    os << "  Victim Address: 0x" << std::hex << victim_addr << std::dec
       << std::endl;
    os << "  Cache Memory Contents:" << std::endl;
    for (size_t set_idx = 0; set_idx < cache_mem.size(); ++set_idx) {
      for (size_t way_idx = 0; way_idx < cache_mem[set_idx].size(); ++way_idx) {
        const auto &line = cache_mem[set_idx][way_idx];
        os << "    Set " << set_idx << ", Way " << way_idx << ": "
           << "Tag=0x" << std::hex << line.DATA_PRIVATE(tag)
           << ", Valid=" << static_cast<int>(line.DATA_PRIVATE(valid))
           << ", Dirty=" << static_cast<int>(line.DATA_PRIVATE(dirty))
           << ", Data=[";
        ;
        for (size_t byte_idx = 0; byte_idx < 16; ++byte_idx) {
          os << std::hex
             << ((line.DATA_PRIVATE(data)[byte_idx / 8] >>
                  ((byte_idx % 8) * 8)) &
                 0xFF);
          if (byte_idx != 15)
            os << " ";
        }
        os << "]" << std::dec << std::endl;
      }
    }

    os << std::endl;
  }

  void memory_state_dump() {
    const auto &memory = sim->rootp->PIPELINE_ACCESS(memory, mem);
    os << "Memory State:" << std::endl;
    const auto current_state =
        sim->rootp->PIPELINE_ACCESS(memory, currentState);
    const auto next_state = sim->rootp->PIPELINE_ACCESS(memory, nextState);
    const auto delay_counter =
        sim->rootp->PIPELINE_ACCESS(memory, delayCountdown);

    os << "  Current State: " << memory_state_string.at(current_state)
       << " (delay_counter=" << std::to_string(delay_counter) << ")"
       << std::endl;
    os << "  Next State: " << memory_state_string.at(next_state)
       << " (delay_counter=" << std::to_string(delay_counter) << ")"
       << std::endl;
    os << "  Memory Contents (non-zero words):" << std::endl;
    std::vector<std::pair<size_t, uint32_t>> non_zero_addrs;

    // Check word-aligned addresses (every 4 bytes)
    for (size_t addr = 0; addr < memory.size(); addr += 4) {
      // Read 4 bytes to form a 32-bit word (little-endian)
      if (addr + 3 < memory.size()) {
        uint32_t word = (uint32_t)memory[addr] |
                        ((uint32_t)memory[addr + 1] << 8) |
                        ((uint32_t)memory[addr + 2] << 16) |
                        ((uint32_t)memory[addr + 3] << 24);
        if (word != 0) {
          non_zero_addrs.push_back({addr, word});
        }
      }
    }

    if (!non_zero_addrs.empty()) {
      const size_t cols = 4; // Number of columns in the grid
      for (size_t i = 0; i < non_zero_addrs.size(); ++i) {
        const auto &[addr, word] = non_zero_addrs[i];
        os << "  [0x" << std::hex << std::setw(8) << std::setfill('0') << addr
           << "]=0x" << std::setw(8) << word << std::dec;
        if ((i + 1) % cols == 0 || i == non_zero_addrs.size() - 1) {
          os << std::endl;
        }
      }
    } else {
      os << "  (all zeros)" << std::endl;
    }

    os << std::endl;
  }

public:
  PipelineStageLogger(const SimClass *sim, std::ostream &os)
      : sim(sim), os(os), tick(0) {}

  void on_tick() {
    tick++;
    collect_metrics();
  }

  void stop() {
    metric_counters["insts"] =
        sim->rootp->PIPELINE_ACCESS(DEBUG_executedInstCount);
    metric_counters["cycles"] = sim->rootp->PIPELINE_ACCESS(DEBUG_cycles);
    metric_counters["mem_read_reqs"] = sim->rootp->PIPELINE_ACCESS(memory, DEBUG_readRequests);
    metric_counters["mem_write_reqs"] = sim->rootp->PIPELINE_ACCESS(memory, DEBUG_writeRequests);
    {
      const double &n_insts = metric_counters["insts"];
      const double &n_cycles = metric_counters["cycles"];
      const double &ipc = n_insts / n_cycles;
      metric_counters["IPC"] = ipc;
    }
  }

  auto get_metrics() -> const std::unordered_map<std::string, double> & {
    return metric_counters;
  }

  void dump() {
    stage_state_dump();
    inst_cache_state_dump();
    // data_cache_state_dump();
    memory_state_dump();
  }
};
#endif // SIM_PIPELINE_STAGE_LOGGER_HPP