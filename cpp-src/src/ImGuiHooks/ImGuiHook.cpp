#include "../../include/WorldBuilder/ImGuiHooks/ImGuiHook.h"

#include "../../include/WorldBuilder/reverse/Addresses.h"
#include "MinHook.h"
#include "imgui_impl_dx12.h"
#include "imgui_impl_win32.h"

#include "../../include/WorldBuilder/UI/WindowManager.h"
#include "../../include/WorldBuilder/globals.h"
#include "../../include/WorldBuilder/reverse/RenderContext.h"
#include <RedLib/RedLib.hpp>
#include <cstdint>
#include <d3d12.h>
#include <dxgi1_2.h>
#include <imgui.h>

bool ImGuiHook::m_hooked = false;
bool ImGuiHook::m_initialized = false;
TCRenderNode_Present_InternalPresent* ImGuiHook::m_originalPresent = nullptr;
TCRenderGlobal_Resize* ImGuiHook::m_originalResize = nullptr;
WndProc_t ImGuiHook::m_originalWndProc = nullptr;
IDXGISwapChain4* ImGuiHook::m_swapChain = nullptr;
ID3D12CommandQueue* ImGuiHook::m_commandQueue = nullptr;
Microsoft::WRL::ComPtr<ID3D12Device> ImGuiHook::m_device{nullptr};
Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> ImGuiHook::m_rtvDescHeap{nullptr};
Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> ImGuiHook::m_srvDescHeap{nullptr};
std::vector<FrameContext> ImGuiHook::m_frameContexts;
std::mutex ImGuiHook::m_initMutex;
std::mutex ImGuiHook::m_updatePlatforms;
bool ImGuiHook::m_initializationFailed = false;
HWND ImGuiHook::m_hwnd;

constexpr UINT WM_IMGUI_PRESENT = WM_USER + 1;

// TODO: Move overlay enabled to "root" state when it gets implemented
bool ImGuiHook::m_overlayEnabled = false;
bool ImGuiHook::m_toggledInput = true;

extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

LRESULT CALLBACK ImGuiHook::OnWndProc(HWND ahWnd, UINT auMsg, WPARAM awParam, LPARAM alParam)
{
  if (auMsg == WM_IMGUI_PRESENT)
  {
    ImGui::UpdatePlatformWindows();
    ImGui::RenderPlatformWindowsDefault();
    return 1;
  }

  // TODO: eventually decide on a way to improve cet compatibility by selectively passing events through (e.g. by detecting cet overlay state)
  if (auMsg == WM_KEYDOWN && awParam == VK_INSERT)
  {
    m_overlayEnabled = !m_overlayEnabled;
    m_toggledInput = false;

    return 1;
  }

  if (!m_toggledInput)
  {
    static const RED4ext::CName res = "ImGui";
    static RED4ext::UniversalRelocFunc<void (*)(RED4ext::CBaseEngine::UnkD0* apThis, RED4ext::CName aReason, bool aShow)>
        forceCursor(WorldBuilder::Addresses::InputSystemWin32Base_ForceCursor);

    forceCursor(RED4ext::CGameEngine::Get()->unkD0, res, m_overlayEnabled);
    m_toggledInput = true;
  }

  if (m_overlayEnabled)
  {
    ImGui_ImplWin32_WndProcHandler(ahWnd, auMsg, awParam, alParam);

    if ((auMsg >= WM_MOUSEFIRST && auMsg <= WM_MOUSELAST) || (auMsg >= WM_KEYFIRST && auMsg <= WM_KEYLAST))
      return 1;

    if (auMsg == WM_INPUT)
      return 1;
  }

  return CallWindowProc(m_originalWndProc, ahWnd, auMsg, awParam, alParam);
}

void ImGuiHook::ResetImGui()
{
  m_initialized = false;

  ImGui_ImplDX12_InvalidateDeviceObjects();
  ImGui_ImplDX12_Shutdown();
  ImGui_ImplWin32_Shutdown();

  ImGui::DestroyContext();

  m_frameContexts.clear();
  m_rtvDescHeap.Reset();
  m_srvDescHeap.Reset();
  m_device.Reset();
  m_commandQueue = nullptr;
  m_swapChain = nullptr;
  m_hwnd = nullptr;
}


void ImGuiHook::InitializeImGui()
{
  try
  {
    DXGI_SWAP_CHAIN_DESC sdesc;
    if (FAILED(m_swapChain->GetDesc(&sdesc)))
    {
      gSdk->logger->Error(gHandle, "Failed to get swap chain desc");
      m_initializationFailed = true;
      return;
    }

    const HWND hWnd = sdesc.OutputWindow;
    if (!hWnd || !IsWindow(hWnd))
    {
      gSdk->logger->Error(gHandle, "Invalid window handle");
      m_initializationFailed = true;
      return;
    }

    m_hwnd = hWnd;
    if (m_originalWndProc == nullptr)
      m_originalWndProc = (WndProc_t)SetWindowLongPtr(hWnd, GWLP_WNDPROC, (LONG_PTR)&ImGuiHook::OnWndProc);

    if (!m_originalWndProc)
    {
      gSdk->logger->Error(gHandle, ("SetWindowLongPtr failed: " + std::to_string(GetLastError())).c_str());
      return;
    }

    if (FAILED(m_swapChain->GetDevice(IID_PPV_ARGS(&m_device))))
    {
      gSdk->logger->Error(gHandle, "Failed to get device");
      m_initializationFailed = true;
      return;
    }

    D3D12_DESCRIPTOR_HEAP_DESC srvdesc = {};
    srvdesc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
    srvdesc.NumDescriptors = 200;
    srvdesc.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
    if (FAILED(m_device->CreateDescriptorHeap(&srvdesc, IID_PPV_ARGS(&m_srvDescHeap))))
    {
      gSdk->logger->Error(gHandle, "Failed to create SRV descriptor heap");
      m_initializationFailed = true;
      return;
    }

    D3D12_DESCRIPTOR_HEAP_DESC rtvdesc = {};
    rtvdesc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    rtvdesc.NumDescriptors = 3;
    rtvdesc.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_NONE;
    rtvdesc.NodeMask = 1;
    if (FAILED(m_device->CreateDescriptorHeap(&rtvdesc, IID_PPV_ARGS(&m_rtvDescHeap))))
    {
      gSdk->logger->Error(gHandle, "Failed to create RTV descriptor heap");
      m_initializationFailed = true;
      return;
    }

    const auto buffCount = std::min(sdesc.BufferCount, 3u);
    m_frameContexts.resize(buffCount);
    const SIZE_T rtvDescriptorSize = m_device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
    D3D12_CPU_DESCRIPTOR_HANDLE rtvHandle = m_rtvDescHeap->GetCPUDescriptorHandleForHeapStart();

    for (UINT i = 0; i < buffCount; i++)
    {
      auto& context = m_frameContexts[i];
      context.MainRenderTargetDescriptor = rtvHandle;
      if (FAILED(m_swapChain->GetBuffer(i, IID_PPV_ARGS(&context.BackBuffer))))
      {
        gSdk->logger->Error(gHandle, "Failed to get back buffer");
        m_initializationFailed = true;
        return;
      }
      m_device->CreateRenderTargetView(context.BackBuffer.Get(), nullptr, context.MainRenderTargetDescriptor);
      rtvHandle.ptr += rtvDescriptorSize;
    }

    for (auto& context : m_frameContexts)
    {
      if (FAILED(m_device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&context.CommandAllocator))))
      {
        gSdk->logger->Error(gHandle, "Failed to create command allocator");
        m_initializationFailed = true;
        return;
      }
      if (FAILED(m_device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, context.CommandAllocator.Get(), nullptr, IID_PPV_ARGS(&context.CommandList))))
      {
        gSdk->logger->Error(gHandle, "Failed to create command list");
        m_initializationFailed = true;
        return;
      }
      context.CommandList->Close();
    }

    IMGUI_CHECKVERSION();
    ImGuiContext* ctx = ImGui::CreateContext();
    if (!ctx)
    {
      gSdk->logger->Error(gHandle, "Failed to create ImGui context");
      m_initializationFailed = true;
      return;
    }

    ImGui::SetCurrentContext(ctx);

    ImGuiIO& io = ImGui::GetIO();

    io.IniFilename = R"(..\..\red4ext\plugins\WorldBuilder\imgui.ini)";

    // TODO: Crashes with Fullscreen -> add option with warning, default to non crashing behavior
    io.ConfigViewportsNoDefaultParent = false;

    io.DisplaySize = ImVec2((float)sdesc.BufferDesc.Width, (float)sdesc.BufferDesc.Height);
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;
    io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;

    ImGui_ImplWin32_EnableDpiAwareness();

    ImGui::StyleColorsDark();

    gSdk->logger->Info(gHandle, "Initializing Win32 backend...");
    if (!ImGui_ImplWin32_Init(hWnd))
    {
      gSdk->logger->Error(gHandle, "Failed to initialize ImGui Win32 backend");
      m_initializationFailed = true;
      return;
    }

    gSdk->logger->Info(gHandle, "Initializing DX12 backend...");
    if (!ImGui_ImplDX12_Init(m_device.Get(), buffCount, DXGI_FORMAT_R8G8B8A8_UNORM,
                             m_srvDescHeap.Get(),
                             m_srvDescHeap->GetCPUDescriptorHandleForHeapStart(),
                             m_srvDescHeap->GetGPUDescriptorHandleForHeapStart()))
    {
      gSdk->logger->Error(gHandle, "Failed to initialize ImGui DX12 backend");
      m_initializationFailed = true;
      return;
    }

    gSdk->logger->Info(gHandle, "Creating device objects...");
    if (!ImGui_ImplDX12_CreateDeviceObjects())
    {
      gSdk->logger->Error(gHandle, "Failed to create DX12 device objects");
      m_initializationFailed = true;
      return;
    }

    gSdk->logger->Info(gHandle, "ImGui initialization complete");
  }
  catch (...)
  {
    gSdk->logger->Error(gHandle, "Exception during ImGui initialization");
    m_initializationFailed = true;
  }
}

void ImGuiHook::DrawImGuiFrame()
{

  if (!ImGui::GetCurrentContext())
  {
    gSdk->logger->Error(gHandle, "No ImGui context!");
    return;
  }

  try
  {
    ImGui_ImplDX12_NewFrame();

    ImGui_ImplWin32_NewFrame();

    ImGuiIO& io = ImGui::GetIO();

    if (!io.Fonts || io.Fonts->Fonts.Size == 0)
    {
      gSdk->logger->Error(gHandle, "Fonts not loaded!");
      io.Fonts->AddFontDefault();
      io.Fonts->Build();
    }

    ImGui::NewFrame();

    if (m_overlayEnabled)
    {
      WorldBuilder::UI::WindowManager::Draw();
    }

    ImGui::Render();

    const auto backBufferIndex = m_swapChain->GetCurrentBackBufferIndex();
    if (backBufferIndex >= m_frameContexts.size())
    {
      gSdk->logger->Error(gHandle, "Invalid back buffer index!");
      return;
    }

    auto& frameContext = m_frameContexts[backBufferIndex];

    frameContext.CommandAllocator->Reset();

    D3D12_RESOURCE_BARRIER barrier = {};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Flags = D3D12_RESOURCE_BARRIER_FLAG_NONE;
    barrier.Transition.pResource = frameContext.BackBuffer.Get();
    barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;

    ID3D12DescriptorHeap* heaps[] = {m_srvDescHeap.Get()};

    frameContext.CommandList->Reset(frameContext.CommandAllocator.Get(), nullptr);
    frameContext.CommandList->ResourceBarrier(1, &barrier);
    frameContext.CommandList->SetDescriptorHeaps(1, heaps);
    frameContext.CommandList->OMSetRenderTargets(1, &frameContext.MainRenderTargetDescriptor, FALSE, nullptr);

    ImGui_ImplDX12_RenderDrawData(ImGui::GetDrawData(), frameContext.CommandList.Get());

    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
    frameContext.CommandList->ResourceBarrier(1, &barrier);
    frameContext.CommandList->Close();

    ID3D12CommandList* commandLists[] = {frameContext.CommandList.Get()};
    m_commandQueue->ExecuteCommandLists(1, commandLists);
  }
  catch (...)
  {
    gSdk->logger->Error(gHandle, "Exception during frame draw");
  }
}

void* ImGuiHook::PresentHooked(int32_t* apDeviceIndex, uint8_t aSomeSync, UINT aSyncInterval)
{
  const auto* pContext = RenderContext::GetInstance();

  if (!m_initialized && !m_initializationFailed)
  {
    std::lock_guard<std::mutex> lock(m_initMutex);
    gSdk->logger->Info(gHandle, "Initializing ImGui...");

    m_swapChain = pContext->devices[*apDeviceIndex - 1].pSwapChain;
    m_commandQueue = pContext->pDirectQueue;

    InitializeImGui();

    if (!m_initializationFailed)
    {
      m_initialized = true;
      gSdk->logger->Info(gHandle, "ImGui Initialized Successfully");
    }
    else
    {
      gSdk->logger->Error(gHandle, "ImGui Initialization Failed");
    }
  }

  if (m_initialized && !m_initializationFailed)
  {
    DrawImGuiFrame();
    SendMessage(m_hwnd, WM_IMGUI_PRESENT, 0, 0);
  }

  return m_originalPresent(apDeviceIndex, aSomeSync, aSyncInterval);
}

void* ImGuiHook::ResizeHooked(uint32_t a1, uint32_t a2, uint32_t a3, uint8_t a4, int32_t* a5)
{
  if (m_initialized && !m_initializationFailed)
    ResetImGui();
  return m_originalResize(a1, a2, a3, a4, a5);
}

void ImGuiHook::Hook()
{
  if (m_hooked)
    return;

  gSdk->logger->Info(gHandle, "Hooking Present Method...");

  MH_Initialize();

  const Red::UniversalRelocPtr<void> presentInternal(WorldBuilder::Addresses::CRenderNode_Present_DoInternal);
  const Red::UniversalRelocPtr<void> resizeInternal(WorldBuilder::Addresses::CRenderGlobal_Resize);

  MH_CreateHook(presentInternal.GetAddr(), reinterpret_cast<void*>(&ImGuiHook::PresentHooked), reinterpret_cast<void**>(&m_originalPresent));
  MH_EnableHook(presentInternal.GetAddr());

  MH_CreateHook(resizeInternal.GetAddr(), reinterpret_cast<void*>(&ImGuiHook::ResizeHooked), reinterpret_cast<void**>(&m_originalResize));
  MH_EnableHook(resizeInternal.GetAddr());

  m_hooked = true;
  gSdk->logger->Info(gHandle, "Hooked Present Method");
}
