#ifndef RESULT_CHECK_PARSER_HPP
#define RESULT_CHECK_PARSER_HPP
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <regex>

#include "riscv_reg_alias.hpp"

namespace fs = std::filesystem;
class ResultCheckParser {
public:
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
        auto it = reg_aliases.find(reg_str);
        if (it != reg_aliases.end()) {
          reg_num = it->second;
        }
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
};
#endif // RESULT_CHECK_PARSER_HPP