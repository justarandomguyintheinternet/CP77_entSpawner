#pragma once
#include <RedLib/RedLib.hpp>
#include "RED4ext/Api/EMainReason.hpp"

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(Red::PluginHandle aHandle,
                                        Red::EMainReason aReason,
                                        const Red::Sdk* aSdk);