#include <memory>

#include "../include/WorldBuilder/WorldBuilderGlobal.h"

std::shared_ptr<Project> WorldBuilderGlobal::ActiveProject = nullptr;
std::vector<std::shared_ptr<Project>> WorldBuilderGlobal::Projects;

WorldBuilder::State::Config::Config WorldBuilderGlobal::Config;
bool WorldBuilderGlobal::initialized = false;

void WorldBuilderGlobal::Initialize()
{
  if (initialized)
    return;

  Projects.push_back(std::make_shared<Project>());
  ActiveProject = Projects.back();

  initialized = true;
}
