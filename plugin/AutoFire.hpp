// Included inside radar, with native helper definitions already available.
static std::atomic<bool> fireEnabled{false},fireOwned{false};
static uint64_t fireWeak=0;
static firepolicy::Gate fireGate;
static void updateFire(uintptr_t desired) {
    uintptr_t previous=fireWeak?function<uintptr_t(*)(uint64_t *)>(0x01088aa4)(&fireWeak):0;
    if(previous && previous!=desired) function<void(*)(uintptr_t)>(0x075623ac)(previous);
    if(previous!=desired) fireWeak=0;
    fireOwned.store(previous && previous==desired,std::memory_order_relaxed);
    if(!desired || previous==desired) return;
    uint8_t pressed=0;
    if(!read(desired+0x218,pressed) || pressed) return; // Do not take ownership of manual fire.
    function<void(*)(uint64_t *,const uintptr_t *)>(0x0108881c)(&fireWeak,&desired);
    function<void(*)(uintptr_t)>(0x07562104)(desired);
    uint8_t accepted=0;
    bool held=read(desired+0x218,accepted) && accepted;
    if(!held) fireWeak=0;
    fireOwned.store(held,std::memory_order_relaxed);
}
struct FireFrame {
    uintptr_t component=0;bool gateEvaluated=false;
    ~FireFrame() {
        if(!gateEvaluated) fireGate.update(false,0,0);
        updateFire(fireEnabled.load(std::memory_order_relaxed)?component:0);
    }
};
