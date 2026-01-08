//
// Created by zweit on 13/12/2025.
//

#include "WorldBuilder/UI/ConfigWindow.h"

#include "../../include/WorldBuilder/State/Config/Config.h"
#include "WorldBuilder/ImGuiHooks/ImGuiHook.h"
#include "WorldBuilder/WorldBuilderGlobal.h"
#include "imgui.h"


namespace WorldBuilder::UI {

void ConfigWindow::Draw()
{
  ImGui::Begin("Config");

  if (ImGui::BeginTabBar("##ConfigTabBar"))
  {
    if (ImGui::BeginTabItem("Global"))
    {
      WorldBuilderGlobal::Config.Draw();

      ImGui::EndTabItem();
    }
    if (ImGui::BeginTabItem("Project"))
    {
      WorldBuilderGlobal::ActiveProject->config.Draw();
      ImGui::EndTabItem();
    }
    ImGui::EndTabBar();
  }

  ImGui::End();
}


} // namespace WorldBuilder::UI
