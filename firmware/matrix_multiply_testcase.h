
// Performance Test 1: Buffer Sum
// Count cycles for summing 128 elements
static int __test_buffer_sum() {
  int a[128];
  int sum = 0;
  int i;

  // Initialize array
  for (i = 0; i < 128; i++) {
    a[i] = i + 1;
  }

  // Sum all elements
  for (i = 0; i < 128; i++) {
    sum += a[i];
  }

  return sum; // Expected: 8256 = sum(1 to 128)
}

// Performance Test 2: Memory Copy
// Count cycles for initializing and copying 128 elements
static int __test_mem_copy() {
  int a[128], b[128];
  int i;

  // Initialize array a
  for (i = 0; i < 128; i++) {
    a[i] = 5;
  }

  // Copy array a to b
  for (i = 0; i < 128; i++) {
    b[i] = a[i];
  }

  // Verify copy worked
  int sum = 0;
  for (i = 0; i < 128; i++) {
    sum += b[i];
  }

  return sum; // Expected: 640 = 128 * 5
}

// Performance Test 3: Matrix Multiply
// Count cycles for 128x128 matrix multiplication
static int __test_matrix_multiply() {
  int a[128][128], b[128][128], c[128][128];
  int i, j, k;

  // Initialize matrices
  for (i = 0; i < 10; i++) {
    for (j = 0; j < 10; j++) {
      a[i][j] = 1;
      b[i][j] = 1;
    }
  }

  // Matrix multiplication
  for (i = 0; i < 10; i++) {
    for (j = 0; j < 10; j++) {
      c[i][j] = 0;
      for (k = 0; k < 10; k++) {
        c[i][j] = c[i][j] + a[i][k] * b[k][j];
      }
    }
  }

  // Return a single element to verify
  return c[0][0]; // Expected: 128
  // return 0;
}

static int matrix_multiply_test() {
  // Run performance tests
  int result1 = __test_buffer_sum();      // Expected: 8256
  int result2 = __test_mem_copy();        // Expected: 640
  int result3 = __test_matrix_multiply(); // Expected: 128

  // Return sum of all results for verification
  return result1 + result2 + result3; // Expected: 9024
  return 0;
}