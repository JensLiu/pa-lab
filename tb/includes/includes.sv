`include "../../includes/includes.sv"

`define BEGIN_WRITE_FILE(mem_filename) \
        int fd``mem_filename = $fopen(mem_filename, "w"); \
        if (fd``mem_filename  == 0) begin \
            $fatal(0, "Could not open instruction memory file for writing."); \
        end begin \
        fd = fd``mem_filename;

`define END_WRITE_FILE(mem_filename) \
        $fclose(fd``mem_filename); \
        end

`define BEGIN_INST(START_ADDR) \
    begin \
    integer pc = START_ADDR;

`define END_INST \
    end

`define INST_HEX_DUMP(fd, inst, comment) \
    $fwrite(fd, "%h %h %h %h // (%h) %s\n", \
            inst.raw[7:0], inst.raw[15:8], \
            inst.raw[23:16], inst.raw[31:24], \
            inst, comment);

`define MAKE_LABEL(label_name) \
    $fwrite(fd, "// %s @0x%h:\n", label_name, pc);

`define MAKE_INST_3(inst_name, arg0, arg1, arg2) \
    inst = make_``inst_name(arg0, arg1, arg2); \
    begin \
        string format = $sformatf("@0x%h: %s\t%s=0x%0h, %s=0x%0h, %s=0x%0h", \
        pc, `"inst_name`", `"arg0`", arg0, `"arg1`", arg1, `"arg2`", arg2);  \
        `INST_HEX_DUMP(fd, inst, format) \
    end \
    pc = pc + 4;

`define MAKE_INST_2(inst_name, arg0, arg1) \
    inst = make_``inst_name(arg0, arg1); \
    begin \
    string format = $sformatf("@0x%h: %s\t%s=0x%0h, %s=0x%0h", pc, `"inst_name`", `"arg0`", arg0, `"arg1`", arg1);  \
    `INST_HEX_DUMP(fd, inst, format) \
    end \
    pc = pc + 4;

`define MAKE_INST_1(inst_name, arg0) \
    inst = make_``inst_name(arg0); \
    begin \
    string format = $sformatf("@0x%h: %s\t%s=0x%0h", pc, `"inst_name`", `"arg0`", arg0);  \
    `INST_HEX_DUMP(fd, inst, format) \
    end \
    pc = pc + 4;

`define MAKE_INST_0(inst_name) \
    inst = make_``inst_name(); \
    begin \
    string format = $sformatf("@0x%h: %s", pc, `"inst_name`");  \
    `INST_HEX_DUMP(fd, inst, format) \
    end \
    pc = pc + 4;