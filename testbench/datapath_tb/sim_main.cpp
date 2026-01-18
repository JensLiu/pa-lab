#include "Vdatapath_pipelined.h"
#include "Vdatapath_pipelined__Syms.h"
#include "riscv_instructions.hpp"
#include "verilated.h"
#include "verilated_fst_c.h"
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <regex>
#include <vector>

// #define USE_LOGGER
#ifdef USE_LOGGER
#include "pipeline_stage_logger.hpp"
#endif

namespace fs = std::filesystem;
typedef Vdatapath_pipelined SimClass;

// Blank lines and lines starting with # or // are ignored.
static std::map<int, uint32_t> parse_result_check(const fs::path &p) {
  std::map<int, uint32_t> expect;
  std::ifstream in(p);
  if (!in)
    return expect;

  std::string line;
  while (std::getline(in, line)) {
    std::cout << "Parsing line: " << line << std::endl;

    // Remove leading/trailing whitespace
    size_t first = line.find_first_not_of(" \t\r\n");
    if (first == std::string::npos)
      continue;
    line = line.substr(first);

    // Skip comments
    if (line[0] == '#' || line.substr(0, 2) == "//")
      continue;
    // Parse register and value: supports "x5 = 0x1234", "a0: 10", etc.
    std::regex pattern(
        R"(^([a-z][a-z0-9]*|[xX]\d{1,2}|\d{1,2})\s*[:=]\s*(0[xX][0-9a-fA-F]+|\d+))");
    std::smatch match;

    if (!std::regex_search(line, match, pattern))
      continue;

    std::cout << "Matched register/value: " << match[1].str() << " = "
              << match[2].str() << std::endl;

    std::string reg_str = match[1].str();
    std::string val_str = match[2].str();

    // Determine register number
    int reg_num = -1;
    if (reg_str[0] == 'x' || reg_str[0] == 'X') {
      reg_num = std::stoi(reg_str.substr(1));
    } else if (std::isdigit(reg_str[0])) {
      reg_num = std::stoi(reg_str);
    } else {
      reg_num = RISCVInstructions::regNumber(reg_str);
    }

    if (reg_num < 0 || reg_num > 31)
      continue;

    // Parse value (hex or decimal)
    uint32_t value;
    if (val_str.substr(0, 2) == "0x" || val_str.substr(0, 2) == "0X") {
      value = std::stoul(val_str, nullptr, 16);
    } else {
      value = std::stoul(val_str, nullptr, 10);
    }

    expect[reg_num] = value;
  }

  return expect;
}

// Run one testcase directory: copy inst.mem into current working directory,
// create model, run a fixed number of cycles, then compare sim->DEBUG_regs
static bool run_testcase(const fs::path &testdir) {
  std::cout << "Running testcase: " << testdir << std::endl;

  const fs::path inst_src = testdir / "memory.hex";
  const fs::path result_check = testdir / "result_check";
  if (!fs::exists(inst_src)) {
    std::cout << "  skip: memory.hex not found in " << testdir << std::endl;
    return false;
  }

  // copy inst.mem into current working directory so the Verilog memory will
  // load it
  const fs::path inst_dst = fs::current_path() / "memory.hex";
  try {
    fs::copy_file(inst_src, inst_dst, fs::copy_options::overwrite_existing);
  } catch (const std::exception &e) {
    std::cout << "  failed to copy inst.mem: " << e.what() << std::endl;
    return false;
  }

  // parse expected results if present
  std::map<int, uint32_t> expect;
  if (fs::exists(result_check)) {
    expect = parse_result_check(result_check);
  }

  // Use a fresh VerilatedContext per testcase so traces and model instances
  // don't collide when running multiple tests in the same process.
  VerilatedContext *contextp = new VerilatedContext;
  contextp->traceEverOn(true);
  SimClass *sim = new SimClass(contextp, testdir.filename().c_str());
  std::ofstream dumpfile(testdir /
                         (testdir.filename().string() + std::string(".log")));
#ifdef USE_LOGGER
  PipelineStageLogger<SimClass> logger(sim, dumpfile);
#endif

  VerilatedFstC *tfp = new VerilatedFstC;
  sim->trace(tfp, 99);
  const std::string fstname =
      (testdir / (testdir.filename().string() + std::string(".fst"))).string();

  std::cout << "fst" << fstname << std::endl;
  tfp->open(fstname.c_str());

  const int max_cycles = 1000;
  for (int cycle = 0; cycle < max_cycles; cycle++) {
    if (cycle > 0) {
      sim->eval();
      tfp->dump(cycle * 10 - 2);
    }

    sim->clk = 1;
    sim->eval();
    tfp->dump(cycle * 10);
#ifdef USE_LOGGER
    logger.on_tick();
    logger.dump();
#endif

    sim->clk = 0;
    sim->eval();
    tfp->dump(cycle * 10 + 5);

    if (Verilated::gotFinish()) {
      std::cout << "Simulation finished at cycle " << cycle << std::endl;
      break;
    }
  }

  tfp->close();

  // compare expected registers
  bool pass = true;
  if (!expect.empty()) {
    for (const auto &p : expect) {
      int reg = p.first;
      uint32_t want = p.second;
      uint32_t got = 0;
      if (reg >= 0 && reg < 32) {
        // DEBUG_regs is a public output array
        got = static_cast<uint32_t>(sim->DEBUG_regs[reg]);
      } else {
        std::cout << "  unknown register index: " << reg << std::endl;
        pass = false;
        continue;
      }
      if (got != want) {
        std::cout << "  MISMATCH reg " << RISCVInstructions::regName(reg)
                  << ": got 0x" << std::hex << got << " want 0x" << want
                  << std::dec << std::endl;
        pass = false;
      } else {
        std::cout << "  OK reg " << RISCVInstructions::regName(reg) << " == 0x"
                  << std::hex << got << std::dec << std::endl;
      }
    }
  } else {
    std::cout << "  no result_check file found; no comparisons performed"
              << std::endl;
  }

  if (!pass) {
    const std::string errorfile = (testdir / "failed").string();
    std::ofstream ef(errorfile);
    ef << "Testcase failed\n";
    ef.close();
  }

  delete tfp;
  delete sim;
  delete contextp;
  return pass;
}

int main(int argc, char **argv) {
  // If an argument is provided, run a single testcase
  if (argc >= 2) {
    fs::path td(argv[1]);
    bool ok = run_testcase(td);
    return ok ? 0 : 2;
  }

  // Find all test directories that contain an inst.mem file by walking from
  // current path
  std::vector<fs::path> testdirs;
  try {
    for (auto &entry : fs::recursive_directory_iterator(fs::current_path())) {
      if (!entry.is_regular_file())
        continue;
      if (entry.path().filename() == "memory.hex" &&
          entry.path() != fs::current_path() / "memory.hex") {
        testdirs.push_back(entry.path().parent_path());
      }
    }
  } catch (const std::exception &e) {
    std::cerr << "Error while scanning for testcases: " << e.what()
              << std::endl;
    return 1;
  }

  if (testdirs.empty()) {
    std::cout << "No testcases (memory.hex) found under " << fs::current_path()
              << std::endl;
    return 0;
  }

  int passed = 0;
  int total = 0;
  // Run each testcase directly in this process
  for (const auto &td : testdirs) {
    total++;
    std::cout << "\n========================================" << std::endl;
    std::cout << "Running test: " << td.string() << std::endl;
    std::cout << "========================================" << std::endl;
    bool ok = run_testcase(td);
    if (ok) {
      passed++;
      std::cout << "PASSED" << std::endl;
    } else {
      std::cout << "FAILED" << std::endl;
    }
  }

  std::cout << "\n========================================" << std::endl;
  std::cout << "Test summary: " << passed << " / " << total << " passed."
            << std::endl;
  std::cout << "========================================" << std::endl;
  return (passed == total) ? 0 : 2;
}