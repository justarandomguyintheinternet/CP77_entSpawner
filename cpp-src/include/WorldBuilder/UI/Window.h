#pragma once
#include <string>

class Window {
public:
  virtual ~Window() = default;
  std::string Name;
  virtual void Draw() = 0;
};