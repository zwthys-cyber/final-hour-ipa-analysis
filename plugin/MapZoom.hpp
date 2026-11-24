// Native minimap ranges are metres, shared by map base and marker projection.
static std::atomic<bool> zoomOut{true};
struct MapZoomScope {
    struct Slot { uint32_t *address=nullptr;uint32_t before=0,written=0; } slots[2];
    MapZoomScope() {
        if(!zoomOut.load(std::memory_order_relaxed)) return;
        for(size_t i=0;i<2;++i) {
            uintptr_t a=base+0x0eb24400+i*4;
            if(!Readable(a,4,true)) continue;
            auto p=reinterpret_cast<uint32_t *>(a);
            uint32_t before=__atomic_load_n(p,__ATOMIC_RELAXED);float value;
            std::memcpy(&value,&before,4);
            if(!std::isfinite(value)||value<5||value>10000) continue;
            value=std::min(value*2.0f,20000.0f);uint32_t written;
            std::memcpy(&written,&value,4);
            uint32_t expected=before;
            if(__atomic_compare_exchange_n(p,&expected,written,false,__ATOMIC_RELAXED,__ATOMIC_RELAXED))
                slots[i]={p,before,written};
        }
    }
    ~MapZoomScope() {
        for(auto &s:slots) if(s.address) {
            uint32_t expected=s.written;
            __atomic_compare_exchange_n(s.address,&expected,s.before,false,__ATOMIC_RELAXED,__ATOMIC_RELAXED);
        }
    }
};
static void nativeDraw(uintptr_t hud) {
    MapZoomScope zoom;
    function<void(*)(uintptr_t)>(0x07a82154)(hud);
}
