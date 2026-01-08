#pragma once
#include "imgui.h"

#include <format>
#include <type_traits>

namespace WorldBuilder::State::Config {

template<typename T>
struct ConfigValue {
  T value;
  T* globalValue = nullptr;

  bool syncGlobalEnabled = true;

  const char* name{};
  const char* description{};
  ImVec4 descColor = ImVec4(0.9f, 0.9f, 0.9f, 1.0f);

  void SyncGlobal();
  bool Draw();
};

template <typename T>
void ConfigValue<T>::SyncGlobal()
{
  if (globalValue == nullptr || !syncGlobalEnabled)
    return;

  value = T(*globalValue);
}

// @returns Value Changed
template <typename T>
bool ConfigValue<T>::Draw()
{
  ImGui::Text(name);
  ImGui::SameLine();

  auto valueChanged = false;

  if constexpr (std::is_same_v<T, bool>)
    valueChanged = ImGui::Checkbox(std::format("##{}", name).c_str(), &value);

  if (valueChanged)
    syncGlobalEnabled = false;

  if (globalValue != nullptr)
  {
    ImGui::SameLine();
    ImGui::SetCursorPosX(ImGui::GetCursorPosX() + ImGui::GetWindowWidth() / 2);
    ImGui::Text("Sync with Global");
    ImGui::SameLine();
    if (ImGui::Checkbox(std::format("##{}_globalCheck", name).c_str(), &syncGlobalEnabled) && syncGlobalEnabled)
      SyncGlobal();
  }
  ImGui::TextColored(descColor, description);

  return valueChanged;
}

} // namespace WorldBuilder::State::Config

