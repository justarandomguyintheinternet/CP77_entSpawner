#include "WorldBuilder/State/Project.h"


 Project::Project() {
   config = WorldBuilder::State::Config::Config();
   config.SetGlobalReference();
 }
