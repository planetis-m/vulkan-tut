#version 450
layout(local_size_x = 32) in;

layout(std430, binding = 0) buffer CounterBuffer {
  int nextTask;  // Atomic counter in its own buffer
};

layout(std430, binding = 1) buffer TaskBuffer {
  int numTasks;  // Total number of tasks
  int tasks[];   // Array of tasks
};

layout(std430, binding = 2) buffer ResultBuffer {
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
