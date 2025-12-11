#pragma once
#include "Microsoft/D3D12Downlevel.h"

#include <wrl/client.h>

struct FrameContext
{
  Microsoft::WRL::ComPtr<ID3D12CommandAllocator> CommandAllocator;
  Microsoft::WRL::ComPtr<ID3D12GraphicsCommandList> CommandList{};
  Microsoft::WRL::ComPtr<ID3D12Resource> BackBuffer;
  D3D12_CPU_DESCRIPTOR_HANDLE MainRenderTargetDescriptor{0};
};