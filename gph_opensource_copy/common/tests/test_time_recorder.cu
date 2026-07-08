#include "gtest/gtest.h"
#include "Exp_batch_result_holder.cuh"
#include "assert.h"

const int N = 3076; // Matrix size

__global__ void matrixMul(const float* A, const float* B, float* C) {
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int col = blockIdx.x * blockDim.x + threadIdx.x;

    if (row < N && col < N) {
        float sum = 0.0f;
        for (int i = 0; i < N; i++) {
            sum += A[row * N + i] * B[i * N + col];
        }
        C[row * N + col] = sum;
    }
}


TEST(TestUnifiedTimeRecorder, general_test_1) {
    UnifiedTimeRecorder recorder;
    
    // Allocate host memory
    float* h_A = new float[N * N];
    float* h_B = new float[N * N];
    float* h_C = new float[N * N];

    // Initialize input matrices with random values
    for (int i = 0; i < N * N; i++) {
        h_A[i] = static_cast<float>(rand()) / RAND_MAX;
        h_B[i] = static_cast<float>(rand()) / RAND_MAX;
    }

    // Allocate device memory
    float* d_A, * d_B, *d_C;
    cudaMalloc((void**)&d_A, N * N * sizeof(float));
    cudaMalloc((void**)&d_B, N * N * sizeof(float));
    cudaMalloc((void**)&d_C, N * N * sizeof(float));

    // Transfer input matrices from host to device
    cudaMemcpy(d_A, h_A, N * N * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_B, h_B, N * N * sizeof(float), cudaMemcpyHostToDevice);

    // Define grid and block dimensions
    dim3 blockSize(16, 16);
    dim3 gridSize((N + blockSize.x - 1) / blockSize.x, (N + blockSize.y - 1) / blockSize.y);

    // Launch the matrixMul kernel
    recorder.start_timer("OneSecondKernel", true);
    recorder.start_timer("CPUTimer", false);
    matrixMul<<<gridSize, blockSize>>>(d_A, d_B, d_C);
    recorder.finish_timer("OneSecondKernel");
    cudaDeviceSynchronize();
    recorder.finish_timer("CPUTimer");

    // Transfer result matrix from device to host
    cudaMemcpy(h_C, d_C, N * N * sizeof(float), cudaMemcpyDeviceToHost);

    // Print result (optional)
    /*for (int i = 0; i < N * N; i++) {
        std::cout << h_C[i] << " ";
        if ((i + 1) % N == 0)
            std::cout << std::endl;
    }*/

    // Free memory
    delete[] h_A;
    delete[] h_B;
    delete[] h_C;
    cudaFree(d_A);
    cudaFree(d_B);
    cudaFree(d_C);

    ASSERT_LT(abs(recorder.export_map_timer_results()["OneSecondKernel"] - recorder.export_map_timer_results()["CPUTimer"]), 100000);
}



// TEST(TestUnifiedTimeRecorder, general_test_1) {
//     UnifiedTimeRecorder recorder;
//     recorder.start_timer("OneSecondKernel", true);
//     dummyKernel<<<1, 1>>>(1, get_GPU_Rate());
//     // cudaDeviceSynchronize();
//     recorder.finish_timer("OneSecondKernel");
//     ASSERT_EQ(1000, recorder.export_map_timer_results()["OneSecondKernel"]) << "GPU rate" <<get_GPU_Rate();
// }