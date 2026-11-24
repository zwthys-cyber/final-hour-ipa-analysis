// Included inside radar, with native helper definitions already available.
enum class FireStatus { Off,Waiting,Panel,Cooldown,Manual,Requested };
static std::atomic<bool> fireEnabled{false};
static std::atomic<FireStatus> fireStatus{FireStatus::Off};
static std::atomic<uint64_t> shotRequests{0};
static firepolicy::Gate fireGate;
static firepolicy::Pulse firePulse;
struct FireFrame {
    uintptr_t component=0;bool gateEvaluated=false;double now=0;
    aim::Part part=aim::Part::Off;
    ~FireFrame() {
        if(!gateEvaluated) fireGate.update(false,0,0);
        if(!fireEnabled.load(std::memory_order_relaxed)) { fireStatus.store(FireStatus::Off);return; }
        if(overlayOpen.load()) { fireStatus.store(FireStatus::Panel);return; }
        if(aimPart.load(std::memory_order_relaxed)!=part || !component) { fireStatus.store(FireStatus::Waiting);return; }
        uint8_t pressed=0;
        if(!read(component+0x218,pressed) || pressed) { fireStatus.store(FireStatus::Manual);return; }
        if(!firePulse.due(true,now)) { fireStatus.store(FireStatus::Cooldown);return; }
        // A single native attempt. Never call HandleFirePressed or hold an automatic input between frames.
        function<void(*)(uintptr_t)>(0x0756ee0c)(component);
        shotRequests.fetch_add(1,std::memory_order_relaxed);fireStatus.store(FireStatus::Requested);
    }
};
