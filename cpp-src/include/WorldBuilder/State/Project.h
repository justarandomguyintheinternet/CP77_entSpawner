#pragma once
#include "Config/Config.h"

#include <map>
#include <string>

class Project {
public:
  Project();

  std::string name;
  std::map<std::string, bool> WindowStates;

  WorldBuilder::State::Config::Config config;
};
