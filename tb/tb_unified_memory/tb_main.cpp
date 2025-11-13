#include "Vtb_unified_memory.h"
#include <iostream>
#include <verilated.h>

typedef Vtb_unified_memory SimClass;

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);

  SimClass *sim = new SimClass;

  sim->clk = 0;
  sim->eval();
  sim->clk = !sim->clk;
  sim->eval();

}