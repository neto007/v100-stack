#include <cstdio>
#include <cuda_runtime.h>
#define CK(x) do{cudaError_t _e=(x); if(_e){printf("ERR %s @%d\n",cudaGetErrorString(_e),__LINE__);return 1;}}while(0)

int main(){
  int n=0; CK(cudaGetDeviceCount(&n));
  if(n<2){ printf("precisa de 2 GPUs (achei %d)\n",n); return 1; }

  int can01=0, can10=0;
  CK(cudaDeviceCanAccessPeer(&can01,0,1));
  CK(cudaDeviceCanAccessPeer(&can10,1,0));
  printf("  P2P 0->1: %s | P2P 1->0: %s\n", can01?"SIM":"NAO", can10?"SIM":"NAO");
  if(!can01){ printf("  *** P2P INDISPONIVEL: o NVLink nao esta sendo usado ***\n"); return 1; }

  CK(cudaSetDevice(0)); CK(cudaDeviceEnablePeerAccess(1,0));
  CK(cudaSetDevice(1)); CK(cudaDeviceEnablePeerAccess(0,0));

  size_t bytes = 512ull*1024*1024;
  void *a,*b;
  CK(cudaSetDevice(0)); CK(cudaMalloc(&a,bytes));
  CK(cudaSetDevice(1)); CK(cudaMalloc(&b,bytes));
  CK(cudaSetDevice(0));

  for(int i=0;i<3;i++) CK(cudaMemcpyPeer(b,1,a,0,bytes));
  CK(cudaDeviceSynchronize());

  cudaEvent_t t0,t1; cudaEventCreate(&t0); cudaEventCreate(&t1);
  const int IT=50;
  cudaEventRecord(t0);
  for(int i=0;i<IT;i++) cudaMemcpyPeer(b,1,a,0,bytes);
  cudaEventRecord(t1); CK(cudaEventSynchronize(t1));
  float ms; cudaEventElapsedTime(&ms,t0,t1);
  double gbs = (double)bytes*IT/1e9/(ms/1e3);
  printf("  GPU0 -> GPU1 unidirecional: %.1f GB/s\n", gbs);
  printf("  referencia: NVLink NV6 ~= 150 GB/s | PCIe 3.0 x16 ~= 12 GB/s\n");
  printf("  veredito: %s\n", gbs > 60 ? "NVLINK ATIVO" : "*** caiu para PCIe ***");
  cudaFree(a); cudaFree(b);
  return 0;
}
