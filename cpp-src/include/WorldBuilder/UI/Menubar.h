#pragma once
#include "../include/WorldBuilder/UI/Window.h"

class Menubar final : public Window
{
public:
  Menubar() { Name = "MenubarWindow"; }
  void Draw() override;
};

