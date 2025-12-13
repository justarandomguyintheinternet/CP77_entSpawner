#pragma once
#include <map>
#include <string>

class Project {
public:
  Project();
  ~Project();

  std::string name;
  std::map<std::string, bool> WindowStates;
};
