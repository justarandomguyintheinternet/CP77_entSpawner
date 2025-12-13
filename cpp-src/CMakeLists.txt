cmake_minimum_required(VERSION 4.0)
project(WorldBuilder)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_definitions(NOMINMAX)

add_library(WorldBuilder SHARED
        src/main.cpp
        include/WorldBuilder/globals.h
        src/ImGuiHooks/ImGuiHook.cpp
        include/WorldBuilder/ImGuiHooks/ImGuiHook.h
        include/WorldBuilder/reverse/Addresses.h
        include/WorldBuilder/reverse/RenderContext.h
        src/reverse/RenderContext.cpp
        vendor/Microsoft/D3D12Downlevel.h
        include/WorldBuilder/ImGuiHooks/FrameContext.h
        src/WorldBuilderGlobal.cpp
        include/WorldBuilder/WorldBuilderGlobal.h
        src/State/Project.cpp
        include/WorldBuilder/State/Project.h
        src/UI/WindowManager.cpp
        include/WorldBuilder/UI/WindowManager.h
        include/WorldBuilder/UI/Window.h
        src/UI/Menubar.cpp
        include/WorldBuilder/UI/Menubar.h
        include/WorldBuilder/State/Config.h
        src/UI/ConfigWindow.cpp
        include/WorldBuilder/UI/ConfigWindow.h
)

set(IMGUI_DIR ${CMAKE_CURRENT_SOURCE_DIR}/vendor/ImGui)

add_library(imgui STATIC
        ${IMGUI_DIR}/imgui.cpp
        ${IMGUI_DIR}/imgui_draw.cpp
        ${IMGUI_DIR}/imgui_tables.cpp
        ${IMGUI_DIR}/imgui_widgets.cpp
        # remove demo for final release, it's quite big
        ${IMGUI_DIR}/imgui_demo.cpp
        ${IMGUI_DIR}/backends/imgui_impl_win32.cpp
        ${IMGUI_DIR}/backends/imgui_impl_dx12.cpp
)

target_include_directories(imgui PUBLIC
        ${IMGUI_DIR}
        ${IMGUI_DIR}/backends
)

target_link_libraries(imgui PUBLIC
        d3d12
        dxgi
)

add_library(MinHook STATIC
        vendor/MinHook/src/buffer.c
        vendor/MinHook/src/hook.c
        vendor/MinHook/src/trampoline.c
        vendor/MinHook/src/hde/hde32.c
        vendor/MinHook/src/hde/hde64.c
)

target_include_directories(MinHook PUBLIC vendor/MinHook/include)

target_link_libraries(WorldBuilder PRIVATE
        MinHook
        imgui
        d3d12
        dxgi
)

target_include_directories(WorldBuilder
        PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/vendor
        PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)