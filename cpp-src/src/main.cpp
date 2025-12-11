#include "../include/WorldBuilder/main.h"

#include "../include/WorldBuilder/ImGuiHooks/ImGuiHook.h"
#include "../include/WorldBuilder/globals.h"
#include "RED4ext/Api/Runtime.hpp"
#include <ImGUi/imgui.h>
#include <Redlib/RedLib.hpp>

Red::PluginHandle gHandle = nullptr;
const Red::Sdk* gSdk = nullptr;

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(Red::PluginHandle aHandle,
                                        Red::EMainReason aReason,
                                        const Red::Sdk* aSdk) {
    switch (aReason)  {
        case RED4ext::EMainReason::Load: {
            gHandle = aHandle;
            gSdk = aSdk;
            Red::TypeInfoRegistrar::RegisterDiscovered();
            aSdk->logger->Info(aHandle, "WorldBuilder Entry Method Called");
            ImGuiHook::Hook();
            break;
        }
        case RED4ext::EMainReason::Unload: {
            break;
        }
    }
    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::PluginInfo* aInfo)
{
    aInfo->name = L"WorldBuilder";
    aInfo->author = L"keanuwheeze, sprt_";
    aInfo->version = RED4EXT_SEMVER(1, 0, 0);
    aInfo->runtime = RED4EXT_RUNTIME_LATEST;
    aInfo->sdk = RED4EXT_SDK_LATEST;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_LATEST;
}