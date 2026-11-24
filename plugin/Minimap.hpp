#pragma once
#include <atomic>
#include "RadarStamp.hpp"
#include "HeadMath.hpp"
#include "AimMode.hpp"
#include "FirePolicy.hpp"
#include <cmath>
#include <cstdint>
#include <cstring>

namespace radar {
// Exact 0.2.10 ABI, verified against the native HUD's Gather call.
struct Bodies {
    uintptr_t local[16]{};
    uintptr_t heap=0;
    int32_t count=0, capacity=16;
};
static_assert(sizeof(Bodies)==144);
static uintptr_t base=0;
static uintptr_t shadow[256]{};
static std::atomic<bool> enabled{false};
static std::atomic<aim::Part> aimPart{aim::Part::Off};
static thread_local bool drawing=false;

template<class T> static bool read(uintptr_t address,T &value) {
    if(!address || !Readable(address,sizeof(T),false)) return false;
    std::memcpy(&value,reinterpret_cast<void *>(address),sizeof(T));return true;
}
template<class T> static T function(uintptr_t offset) { return reinterpret_cast<T>(base+offset); }

#include "AutoFire.hpp"
#include "HeadAim.hpp"
#include "MapZoom.hpp"

static void draw(uintptr_t hud) {
    auto original=function<void(*)(uintptr_t)>(0x07a82154);
    if(drawing) { original(hud);return; }
    hudFrames.fetch_add(1,std::memory_order_relaxed);
    if(!enabled.load() && aimPart.load()==aim::Part::Off && !fireOwned.load() && !zoomOut.load()) { original(hud);return; }
    drawing=true;
    // Executed by the game's virtual DrawHUD call, on the game's own drawing thread.
    uintptr_t world=function<uintptr_t(*)(uintptr_t)>(0x02e43cb0)(hud);
    double now=0;
    if(!read(world+0x9d0,now) || !std::isfinite(now) || now<0) {
        nativeDraw(hud);fireGate.update(false,0,0);updateFire(0);drawing=false;return;
    }
    if(!enabled.load(std::memory_order_relaxed)) {
        nativeDraw(hud);lockAim(world);drawing=false;return;
    }
    Bodies bodies;
    function<void(*)(uintptr_t,Bodies *)>(0x07442a7c)(world,&bodies);
    struct Saved { uintptr_t address; uint64_t before; } saved[512];
    size_t count=0;
    uint64_t stamp=0;std::memcpy(&stamp,&now,sizeof(stamp));
    uintptr_t data=bodies.heap?bodies.heap:reinterpret_cast<uintptr_t>(bodies.local);
    if(bodies.count>=0 && bodies.count<=512 && bodies.capacity>=bodies.count &&
       Readable(data,static_cast<size_t>(bodies.count)*sizeof(uintptr_t),false)) {
        for(int32_t i=0;i<bodies.count;++i) {
            uintptr_t actor=0;
            if(!read(data+i*sizeof(uintptr_t),actor) || !actor || actor>UINTPTR_MAX-0xbe8) continue;
            uintptr_t field=actor+0xbe8;
            if(field%alignof(uint64_t) || !Readable(field,sizeof(uint64_t),true)) continue;
            auto slot=reinterpret_cast<uint64_t *>(field);
            uint64_t before=__atomic_load_n(slot,__ATOMIC_RELAXED);
            double prior;std::memcpy(&prior,&before,sizeof(prior));
            if(!std::isfinite(prior)) continue;
            // Preserve concurrent changes rather than overwriting a newer shot timestamp.
            if(beginStamp(slot,before,stamp))
                saved[count++]={field,before};
        }
    }
    // Native rendering retains its own alive/team/range/rotation/coordinate rules.
    nativeDraw(hud);
    for(size_t i=0;i<count;++i) {
        if(!Readable(saved[i].address,sizeof(uint64_t),true)) continue;
        restoreStamp(reinterpret_cast<uint64_t *>(saved[i].address),stamp,saved[i].before);
    }
    if(bodies.heap) function<void(*)(uintptr_t)>(0x0067d710)(bodies.heap);
    lockAim(world);drawing=false;
}

static bool attach() {
    if(!base) return false;
    uintptr_t world=0;
    if(!read(base+0x0ec5b818,world) || !world || !Readable(world,0x340,false)) return false;
    uintptr_t pc=function<uintptr_t(*)(uintptr_t)>(0x0414c414)(world);
    uintptr_t hud=0,table=0;
    if(!pc || !read(pc+0x380,hud) || !hud || !read(hud,table)) return false;
    uintptr_t replacement=reinterpret_cast<uintptr_t>(shadow+2);
    if(table==replacement) return true;
    const uintptr_t expectedTable=base+0x0e02e268+16;
    if(table!=expectedTable || !Readable(hud,sizeof(uintptr_t),true)) return false;
    if(!shadow[252]) {
        if(!Readable(expectedTable-16,sizeof(shadow),false)) return false;
        std::memcpy(shadow,reinterpret_cast<void *>(expectedTable-16),sizeof(shadow));
        if(shadow[252]!=base+0x07a82154) { std::memset(shadow,0,sizeof(shadow));return false; }
        shadow[252]=reinterpret_cast<uintptr_t>(&draw);
    }
    return __atomic_compare_exchange_n(reinterpret_cast<uintptr_t *>(hud),&table,replacement,
        false,__ATOMIC_RELEASE,__ATOMIC_RELAXED);
}
} // namespace radar
