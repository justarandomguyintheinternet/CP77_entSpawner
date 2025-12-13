#pragma once
#include "../include/WorldBuilder/UI/Menubar.h"
#include "Window.h"

#include <memory>
#include <vector>

namespace WorldBuilder::UI
{
class WindowManager
{
public:
  WindowManager() = delete;
  static void Initialize();
  static void Draw();
private:
  static bool m_initialized;
  static std::vector < std::unique_ptr<Window>> m_windows;

  static Menubar m_menubar;
};
}


