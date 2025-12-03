#include "matrix_multiply_testcase.h"
#include "fib_testcase.h"

// #define STOP *(unsigned int *)(0xcafebabe) = 0xbeafbabe

int sum(int n) {
  int total = 0;
  for (int i = 1; i <= n; i++) {
    total += i;
  }
  return total;
}


#define STOP *(unsigned int *)(0xcafebabe) = 0xbeafbabe

int main() {
  fib_test();
  // matrix_multiply_test();
  STOP;
}