#include <iostream>
#include "verilated.h"
#include "Vdatapath_pipelined.h"

typedef Vdatapath_pipelined SimClass;

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    SimClass *sim = new SimClass;
    
    for (int cycle = 0; cycle < 1000; cycle++) {
        sim->clk = 0;
        sim->eval();
        sim->clk = 1;
        sim->eval();
        // for (int i = 0; i < 32; i++) {
        //     if (sim->DEBUG_regs[i] != 0) {
        //         std::cout << "Cycle " << cycle << ": DEBUG_regs[" << i << "] = " << std::hex << (int)sim->DEBUG_regs[i] << std::dec << std::endl;
        //     }
        // }
    }

}