#include "../include/WorldBuilder/WorldBuilderGlobal.h"

std::shared_ptr<Project> WorldBuilderGlobal::ActiveProject = nullptr;
std::vector<std::shared_ptr<Project>> WorldBuilderGlobal::Projects;

WorldBuilder::Config::Config WorldBuilderGlobal::Config;