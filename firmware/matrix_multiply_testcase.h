#define N 128
// Performance Test 1: Buffer Sum
// Count cycles for summing N elements
static int __test_buffer_sum() {
  int a[N];
  int sum = 0;
  int i;

  // Initialize array
  for (i = 0; i < N; i++) {
    a[i] = i + 1;
  }

  // Sum all elements
  for (i = 0; i < N; i++) {
    sum += a[i];
  }

  return sum; // Expected: 8256 = sum(1 to N)
}

// Performance Test 2: Memory Copy
// Count cycles for initializing and copying N elements
static int __test_mem_copy() {
  int a[N], b[N];
  int i;

  // Initialize array a
  for (i = 0; i < N; i++) {
    a[i] = 5;
  }

  // Copy array a to b
  for (i = 0; i < N; i++) {
    b[i] = a[i];
  }

  // Verify copy worked
  int sum = 0;
  for (i = 0; i < N; i++) {
    sum += b[i];
  }

  return sum; // Expected: 640 = N * 5
}

// Performance Test 3: Matrix Multiply
// Count cycles for NxN matrix multiplication
#define SMALLER_N 32
#define NI SMALLER_N
#define NJ SMALLER_N
#define NK SMALLER_N
static int __test_matrix_multiply() {
  int a[SMALLER_N][SMALLER_N], b[SMALLER_N][SMALLER_N], c[SMALLER_N][SMALLER_N];
  int i, j, k;

  // Initialize matrices
  for (i = 0; i < NI; i++) {
    for (j = 0; j < NJ; j++) {
      a[i][j] = 1;
      b[i][j] = 1;
    }
  }

  // Matrix multiplication
  for (i = 0; i < NI; i++) {
    for (j = 0; j < NJ; j++) {
      c[i][j] = 0;
      for (k = 0; k < NK; k++) {
        c[i][j] = c[i][j] + a[i][k] * b[k][j];
      }
    }
  }

  // Return a single element to verify
  return c[0][0]; // Expected: N
  // return 0;
}

static int matrix_multiply_test() {
  // Run performance tests
  int result1 = __test_buffer_sum();      // Expected: 8256
  int result2 = __test_mem_copy();        // Expected: 640
  int result3 = __test_matrix_multiply(); // Expected: N

  // Return sum of all results for verification
  return result1 + result2 + result3;
  // return 0;
}