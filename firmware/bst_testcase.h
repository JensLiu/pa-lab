#define MAX_NODES 64
#define NULL 0

// Static Memory Pool for Nodes
struct Node {
  int key;
  int left; // Storing indices instead of pointers
  int right;
  int height;
};

struct Node pool[MAX_NODES];
int pool_ptr = 0;

// Simple memory allocator from static pool
static int __allocate_node(int key) {
  if (pool_ptr >= MAX_NODES)
    return -1;
  int idx = pool_ptr++;
  pool[idx].key = key;
  pool[idx].left = -1;
  pool[idx].right = -1;
  pool[idx].height = 1;
  return idx;
}

// Utility functions using indices
static int __get_height(int idx) {
  if (idx == -1)
    return 0;
  return pool[idx].height;
}

int max(int a, int b) { return (a > b) ? a : b; }

static int __get_balance(int idx) {
  if (idx == -1)
    return 0;
  return __get_height(pool[idx].left) - __get_height(pool[idx].right);
}

// Rotation Logic (Complex Control Flow)
static int __right_rotate(int y) {
  int x = pool[y].left;
  int T2 = pool[x].right;

  pool[x].right = y;
  pool[y].left = T2;

  pool[y].height =
      max(__get_height(pool[y].left), __get_height(pool[y].right)) + 1;
  pool[x].height =
      max(__get_height(pool[x].left), __get_height(pool[x].right)) + 1;

  return x;
}

static int __left_rotate(int x) {
  int y = pool[x].right;
  int T2 = pool[y].left;

  pool[y].left = x;
  pool[x].right = T2;

  pool[x].height =
      max(__get_height(pool[x].left), __get_height(pool[x].right)) + 1;
  pool[y].height =
      max(__get_height(pool[y].left), __get_height(pool[y].right)) + 1;

  return y;
}

// Recursive Insertion
int __insert(int node_idx, int key) {
  if (node_idx == -1)
    return __allocate_node(key);

  if (key < pool[node_idx].key)
    pool[node_idx].left = __insert(pool[node_idx].left, key);
  else if (key > pool[node_idx].key)
    pool[node_idx].right = __insert(pool[node_idx].right, key);
  else
    return node_idx;

  pool[node_idx].height = 1 + max(__get_height(pool[node_idx].left),
                                  __get_height(pool[node_idx].right));

  int balance = __get_balance(node_idx);

  // Left Left Case
  if (balance > 1 && key < pool[pool[node_idx].left].key)
    return __right_rotate(node_idx);
  // Right Right Case
  if (balance < -1 && key > pool[pool[node_idx].right].key)
    return __left_rotate(node_idx);

  // Left Right Case
  if (balance > 1 && key > pool[pool[node_idx].left].key) {
    pool[node_idx].left = __left_rotate(pool[node_idx].left);
    return __right_rotate(node_idx);
  }

  // Right Left Case
  if (balance < -1 && key < pool[pool[node_idx].right].key) {
    pool[node_idx].right = __right_rotate(pool[node_idx].right);
    return __left_rotate(node_idx);
  }

  return node_idx;
}

// Checksum logic to verify data integrity
unsigned int __compute_checksum(int idx, unsigned int current_sum) {
  if (idx == -1)
    return current_sum;

  // In-order traversal to touch all data points
  current_sum = __compute_checksum(pool[idx].left, current_sum);
  current_sum = (current_sum * 33) ^ (unsigned int)pool[idx].key;
  current_sum = __compute_checksum(pool[idx].right, current_sum);

  return current_sum;
}

int bst_test() {
  int root = -1;

  // Input sequence designed to trigger all rotation types
  // int keys[] = {50, 25, 75, 10, 30, 60, 80, 5, 15, 27, 35, 55, 65, 77, 85};
  int keys[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
  int n = sizeof(keys) / sizeof(keys[0]);

  for (int i = 0; i < n; i++) {
    root = __insert(root, keys[i]);
  }

  unsigned int result = __compute_checksum(root, 5381);

  return result;
}