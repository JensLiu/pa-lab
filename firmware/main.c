int recursive_fibonacci(int n) {
  if (n == 0) {
    return 0;
  } else if (n == 1) {
    return 1;
  }
  return recursive_fibonacci(n - 2) + recursive_fibonacci(n - 1);
}

int iterative_fibonacci(int n) {
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

int sum(int n) {
  int total = 0;
  for (int i = 1; i <= n; i++) {
    total += i;
  }
  return total;
}

int main() {
  // int result = r_fibonacci(10);
  // int sum = 0;
  // for (int i = 1; i <= 10; i++) {
  //   sum += i;
  // }
  int result = recursive_fibonacci(8);
  return result;
}