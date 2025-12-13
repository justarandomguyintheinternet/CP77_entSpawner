//
// Created by zweit on 11/12/2025.
//

#include "../include/WorldBuilder/UI/WindowManager.h"

#include "../../include/WorldBuilder/UI/Menubar.h"
#include "../include/WorldBuilder/WorldBuilderGlobal.h"
#include "imgui.h"

using namespace WorldBuilder::UI;

bool WindowManager::m_initialized = false;
std::vector <std::unique_ptr<Window>> WindowManager::m_windows;
Menubar WindowManager::m_menubar;

void WindowManager::Initialize()
{
  m_initialized = true;
}

void WindowManager::Draw()
{
  if (!m_initialized)
    Initialize();

  ImGui::DockSpaceOverViewport(0, ImGui::GetMainViewport(), ImGuiDockNodeFlags_PassthruCentralNode);

  m_menubar.Draw();

  ImGui::Begin("Hello, world!");
  ImGui::Text("Hello, world!");
  ImGui::End();

  ImGui::ShowDemoWindow();
  ImGui::ShowAboutWindow();
}

