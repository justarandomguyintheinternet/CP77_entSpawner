//
// Created by zweit on 13/12/2025.
//

#include "WorldBuilder/UI/ConfigWindow.h"

#include "WorldBuilder/ImGuiHooks/ImGuiHook.h"
#include "WorldBuilder/State/Config.h"
#include "WorldBuilder/WorldBuilderGlobal.h"
#include "imgui.h"

namespace WorldBuilder {
namespace UI {

void DrawConfig(bool global)
{
  // TODO: Use project config when projects are implemented
  Config::Config& active = global ? WorldBuilderGlobal::Config : WorldBuilderGlobal::Config;

  ImGui::Text("General");
  ImGui::Separator();
  ImGui::NewLine();

  if (global)
  {
    ImGui::Text("Enable Viewport");
    ImGui::SameLine();
    if (ImGui::Checkbox("##EnableViewports", &active.EnableViewports))
      ImGuiHook::RequestReset();
    ImGui::TextColored(ImVec4(255, 165, 0, 255), "Causes crashes in combination with exclusive fullscreen, consider using windowed fullscreen.");
  }
}

void ConfigWindow::Draw()
{
  ImGui::Begin("Config");

  ImGui::BeginTabBar("##Configs");

  if (ImGui::BeginTabItem("Global"))
  {
    DrawConfig(true);
    ImGui::EndTabItem();
  }

  if (ImGui::BeginTabItem("Project"))
  {
    DrawConfig(false);
    ImGui::EndTabItem();
  }

  ImGui::EndTabBar();

  ImGui::End();
}


} // namespace UI
} // namespace WorldBuilder