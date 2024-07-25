#version 450
layout(local_size_x = 32) in;

layout(std430, binding = 0) buffer lay0 {
  int nextTask;  // Atomic counter to keep track of the next task to allocate
  int numTasks;  // Total number of tasks
  int tasks[];   // Array of tasks (1 means task is available, 0 means taken)
};

layout(std430, binding = 1) buffer lay1 {
  int results[];  // Array to store which invocation got which task
};

void main() {
  const uint id = gl_GlobalInvocationID.x;
  int myTask = -1;  // Initialize to -1 (no task allocated)

  int taskId = atomicAdd(nextTask, 1);
  if (taskId < numTasks) {
    // Mark the task as taken
    if (atomicCompSwap(tasks[taskId], 1, 0) == 1) {
      myTask = taskId;
    }
  }

  // Store the result
  results[id] = myTask;

  // Insert memory barrier if necessary
  memoryBarrierBuffer();
}
