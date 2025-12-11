#include "../../include/WorldBuilder/reverse/Addresses.h"

#include "../../include/WorldBuilder/reverse/RenderContext.h"
#include "RedLib/RedLib.hpp"

// From CyberEngineTweaks under MIT license

struct RenderContext;
RenderContext * RenderContext::GetInstance() noexcept
{
  static Red::UniversalRelocPtr<RenderContext*> s_instance(WorldBuilder::Addresses::CRenderGlobal_InstanceOffset);
  return *s_instance.GetAddr();
}