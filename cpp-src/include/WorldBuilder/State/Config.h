#pragma once

namespace WorldBuilder {
namespace Config {

struct Config
{
  int FileVersion = 1;

  bool EnableViewports = false; // can crash the game in exclusive full screen

};

}
}
