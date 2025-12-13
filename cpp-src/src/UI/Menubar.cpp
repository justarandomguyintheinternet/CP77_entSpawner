#include "../include/WorldBuilder/UI/Menubar.h"
#include <imgui.h>

ImGuiWindowFlags window_flags =
  ImGuiWindowFlags_NoResize |
  ImGuiWindowFlags_MenuBar |
  ImGuiWindowFlags_NoMove |
  ImGuiWindowFlags_NoTitleBar |
  ImGuiWindowFlags_NoDocking |
  ImGuiWindowFlags_NoDecoration |
  ImGuiWindowFlags_NoScrollbar |
  ImGuiWindowFlags_NoScrollWithMouse;

void Menubar::Draw() {
  if (ImGui::BeginMainMenuBar()) {

    ImGui::Text("WorldBuilder");

    ImGui::SameLine();

    if (ImGui::BeginMenu("Project"))
    {
      if (ImGui::MenuItem("New")) { /* action */ }
      if (ImGui::MenuItem("Open")) { /* action */ }
      if (ImGui::MenuItem("Save")) { /* action */ }
      ImGui::EndMenu();
    }

    ImGui::SameLine();

    if (ImGui::BeginMenu("Edit"))
    {
      if (ImGui::MenuItem("Undo")) { /* action */ }
      if (ImGui::MenuItem("Redo")) { /* action */ }
      ImGui::EndMenu();
    }

    ImGui::SameLine();

    if (ImGui::BeginMenu("Windows"))
    {
      if (ImGui::MenuItem("Undo")) { /* action */ }
      if (ImGui::MenuItem("Redo")) { /* action */ }
      ImGui::EndMenu();
    }

    ImGui::EndMainMenuBar();
  }
}