// Required by GCC for struct/array operations in freestanding mode
void *memcpy(void *dest, const void *src, unsigned int n) {
    unsigned char *d = dest;
    const unsigned char *s = src;
    while (n--) {
        *d++ = *s++;
    }
    return dest;
}

#define STOP *(unsigned int *)(0xcafebabe) = 0xbeafbabe


#include "matrix_multiply_testcase.h"
#include "fib_testcase.h"
#include "bst_testcase.h"

int sum(int n) {
  int total = 0;
  for (int i = 1; i <= n; i++) {
    total += i;
  }
  return total;
}

int main() {
  // fib_test();
  // matrix_multiply_test();
  bst_test();
  STOP;
}