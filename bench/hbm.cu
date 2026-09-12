#include <cstdio>
#include <cuda_runtime.h>
#define CK(x) do{cudaError_t e=(x); if(e){printf("ERR %s @%d\n",cudaGetErrorString(e),__LINE__);return 1;}}while(0)

__global__ void triad(float4* __restrict__ a, const float4* __restrict__ b,
                      const float4* __restrict__ c, size_t n, float s){
  size_t i = blockIdx.x*(size_t)blockDim.x + threadIdx.x;
  size_t stride = (size_t)gridDim.x*blockDim.x;
  for(; i<n; i+=stride){ float4 x=b[i], y=c[i];
    a[i] = make_float4(x.x+s*y.x, x.y+s*y.y, x.z+s*y.z, x.w+s*y.w); }
}

int main(int argc,char**argv){
  int dev = argc>1?atoi(argv[1]):0;
  CK(cudaSetDevice(dev));
  cudaDeviceProp p; CK(cudaGetDeviceProperties(&p,dev));
  size_t bytes = 1500ull*1024*1024;          // 1.5 GB por buffer
  size_t n = bytes/sizeof(float4);
  float4 *a,*b,*c;
  CK(cudaMalloc(&a,bytes)); CK(cudaMalloc(&b,bytes)); CK(cudaMalloc(&c,bytes));
  CK(cudaMemset(b,1,bytes)); CK(cudaMemset(c,2,bytes));
  int blocks = p.multiProcessorCount*32;
  for(int i=0;i<5;i++) triad<<<blocks,256>>>(a,b,c,n,1.5f);   // warmup
  CK(cudaDeviceSynchronize());
  cudaEvent_t t0,t1; cudaEventCreate(&t0); cudaEventCreate(&t1);
  const int IT=30;
  cudaEventRecord(t0);
  for(int i=0;i<IT;i++) triad<<<blocks,256>>>(a,b,c,n,1.5f);
  cudaEventRecord(t1); CK(cudaEventSynchronize(t1));
  float ms; cudaEventElapsedTime(&ms,t0,t1);
  double gb = 3.0*bytes*IT/1e9;              // 2 leituras + 1 escrita
  printf("GPU%d %-26s  TRIAD HBM2: %7.1f GB/s  (%.1f%% do pico de 900)\n",
         dev, p.name, gb/(ms/1e3), 100.0*(gb/(ms/1e3))/900.0);
  cudaFree(a);cudaFree(b);cudaFree(c);
  return 0;
}
