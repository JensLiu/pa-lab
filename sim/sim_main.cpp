#include "Vdatapath_pipelined.h"
#include "Vdatapath_pipelined__Syms.h"
#include "pipeline_stage_logger.hpp"
#include "verilated.h"
#include "verilated_fst_c.h"
#include <iostream>

typedef Vdatapath_pipelined SimClass;

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  Verilated::traceEverOn(true);

  SimClass *sim = new SimClass;
  std::ofstream dumpfile("simulation.log");
  PipelineStageLogger<SimClass> logger(sim, dumpfile);

  VerilatedFstC *tfp = new VerilatedFstC;
  sim->trace(tfp, 99);
  tfp->open("simulation.fst");

  try {
    for (int cycle = 0; cycle < 1000; cycle++) {
      if (cycle > 0) {
        sim->eval();
        tfp->dump(cycle * 10 - 2);
      }

      sim->clk = 1;
      sim->eval();
      tfp->dump(cycle * 10);
      logger.on_tick();
      logger.dump();

      sim->clk = 0;
      sim->eval();
      tfp->dump(cycle * 10 + 5);
    }
  } catch (const std::exception &e) {
    std::cerr << "Simulation error: " << e.what() << std::endl;
  }

  tfp->close();
}