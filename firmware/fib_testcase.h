int __recursive_fibonacci(int n) {
  if (n == 0) {
    return 0;
  } else if (n == 1) {
    return 1;
  }
  return __recursive_fibonacci(n - 2) + __recursive_fibonacci(n - 1);
}

int __iterative_fibonacci(int n) {
  if (n == 0) {
    return 0;
  } else if (n == 1) {
    return 1;
  }

  int a = 0;
  int b = 1;
  int c;

  for (int i = 2; i <= n; i++) {
    c = a + b;
    a = b;
    b = c;
  }

  return b;
}

int __memorised_fibonacci(int n, int log_array[], int size) {
  if (n < size && log_array[n] != 0) {
    // non-zero means we already computed this
    return log_array[n];
  }
  if (n == 0) {
    return 0;
  } else if (n == 1) {
    return 1;
  }
  int answer = __memorised_fibonacci(n - 2, log_array, size) +
               __memorised_fibonacci(n - 1, log_array, size);
  if (n < size) {
    log_array[n] = answer; // save answer for reuse later
  }
  return answer;
}

static int fib_test() {
  int log_array[100]; // Initialize log_array with zeros
  int result = __memorised_fibonacci(30, log_array, 100);
  // int result = iterative_fibonacci(20);
  return result;
}