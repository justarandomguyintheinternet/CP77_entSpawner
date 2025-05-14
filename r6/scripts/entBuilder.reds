@if(ModuleExists("Codeware"))
public class EntityBuilder extends ScriptableService {
    private func Initialize() {
        GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Initialize", this, n"OnAssemble");
        GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Attached", this, n"OnAttached");
    }

    private func RegisterResourceCallback(token: ref<ResourceToken>) {
        token.RegisterCallback(this, n"OnResourceReady");
    }

    private cb func OnAttached(event: ref<EntityLifecycleEvent>) {}
    private cb func OnAssemble(event: ref<EntityLifecycleEvent>) {}
    private cb func OnResourceReady(token: ref<ResourceToken>) {}
}