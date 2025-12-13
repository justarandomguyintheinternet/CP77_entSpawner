#pragma once
#include "State/Config.h"
#include "State/Project.h"

#include <memory>
#include <vector>

class WorldBuilderGlobal {
  public:
  WorldBuilderGlobal() = delete;
  static std::shared_ptr<Project> ActiveProject;
  static std::vector<std::shared_ptr<Project>> Projects;

  static WorldBuilder::Config::Config Config;
};


