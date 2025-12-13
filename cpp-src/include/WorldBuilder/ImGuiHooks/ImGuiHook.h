#pragma once
#include "../reverse/RenderContext.h"
#include "FrameContext.h"
#include "Microsoft/D3D12Downlevel.h"

#include <mutex>
#include <vector>
#include <wrl/client.h>

using TCRenderNode_Present_InternalPresent = void*(int32_t*, uint8_t, UINT);
using TCRenderGlobal_Resize = void*(uint32_t a1, uint32_t a2, uint32_t a3, uint8_t a4, int32_t* a5);
typedef LRESULT(WINAPI* WndProc_t)(HWND, UINT, WPARAM, LPARAM);


class ImGuiHook
{
public:
  ImGuiHook() = delete;
  static void Hook();
  static void RequestReset();
private:
  static bool m_hooked;
  static bool m_initialized;
  static TCRenderNode_Present_InternalPresent* m_originalPresent;
  static TCRenderGlobal_Resize* m_originalResize;
  static WndProc_t m_originalWndProc;
  static IDXGISwapChain4* m_swapChain;
  static ID3D12CommandQueue* m_commandQueue;
  static Microsoft::WRL::ComPtr<ID3D12Device> m_device;
  static Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> m_rtvDescHeap;
  static Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> m_srvDescHeap;
  static std::vector<FrameContext> m_frameContexts;
  static std::mutex m_initMutex;
  static std::mutex m_updatePlatforms;
  static bool m_initializationFailed;
  static bool m_viewportsEnabled;

  static HWND m_hwnd;

  static bool m_overlayEnabled;
  static bool m_toggledInput;

  static bool m_resetRequested;

  static void* PresentHooked(int32_t* apDeviceIndex, uint8_t aSomeSync, UINT aSyncInterval);
  static void* ResizeHooked(uint32_t a1, uint32_t a2, uint32_t a3, uint8_t a4, int32_t* a5);
  static void DrawImGuiFrame();
  static void InitializeImGui();
  static void ResetImGui();

  static LRESULT OnWndProc(HWND ahWnd, UINT auMsg, WPARAM awParam, LPARAM alParam);
};


