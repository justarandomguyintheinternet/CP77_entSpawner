#pragma once
#include "ConfigValue.h"


namespace WorldBuilder::State::Config {

struct Config
{
  Config();

  int FileVersion = 1;
  bool isGlobal = false;

  ConfigValue<bool> EnableMultiViewports;

  void SetGlobalReference();
  void Draw();
  void OnGlobalConfigChanged();
};

}

