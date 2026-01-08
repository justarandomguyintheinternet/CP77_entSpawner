#include "WorldBuilder/State/Config/Config.h"

#include "WorldBuilder/WorldBuilderGlobal.h"

namespace WorldBuilder::State::Config
{
Config::Config() {

  EnableMultiViewports = State::Config::ConfigValue<bool> {
    .value = false,
    .name = "Enable Multi-Viewports",
    .description = "Allows ImGui windows to draw outside of the game window. This will cause crashes in combination with exclusive fullscreen.",
    .descColor = ImVec4(1.0f, 0.8f, 0.0f, 1.0f)
  };

}

void Config::SetGlobalReference() {
  Config& cfg = WorldBuilderGlobal::Config;

  cfg.isGlobal = true;

  EnableMultiViewports.globalValue = &cfg.EnableMultiViewports.value;
}

void Config::Draw() {

  auto configChanged = false;

  configChanged = EnableMultiViewports.Draw() or configChanged;

  if (configChanged)
  {
    for (auto& proj : WorldBuilderGlobal::Projects)
      proj->config.OnGlobalConfigChanged();
  }
}

void Config::OnGlobalConfigChanged() {
  EnableMultiViewports.SyncGlobal();
}


}