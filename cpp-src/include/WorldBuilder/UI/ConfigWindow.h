#pragma once

#include "WorldBuilder/UI/Window.h"

namespace WorldBuilder {
namespace UI {

class ConfigWindow : public Window {
public:
  ConfigWindow() { Name = "ConfigWindow"; }
  void Draw() override;
};

} // namespace UI
} // namespace WorldBuilder

