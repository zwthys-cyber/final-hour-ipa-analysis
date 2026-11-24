#pragma once
#include <cstdint>
#include <cmath>
namespace firepolicy {
struct Gate {
    uint64_t target=0;unsigned frames=0;uint32_t mode=0;
    double acquiredAt=0,lastTime=-1;
    bool update(bool enabled,uint64_t candidate,double error,uint32_t requestedMode=0,
                double now=0,double tolerance=.25,bool directHit=false) {
        if(mode!=requestedMode) { target=0;frames=0;lastTime=-1;mode=requestedMode; }
        if(!enabled || !candidate || !directHit || !std::isfinite(error) || error<0 ||
           !std::isfinite(tolerance) || tolerance<=0 || tolerance>.35 || error>tolerance ||
           !std::isfinite(now) || now<0) {
            target=0;frames=0;lastTime=-1;return false;
        }
        if(candidate!=target || lastTime<0 || now<lastTime || now-lastTime>.1) {
            target=candidate;frames=1;acquiredAt=now;lastTime=now;return false;
        }
        lastTime=now;
        if(frames<2) ++frames;
        return frames>=2 && now-acquiredAt>=.15;
    }
};
struct Pulse {
    double last=-1;
    bool due(bool allowed,double now) {
        if(!allowed || !std::isfinite(now) || now<0) return false;
        if(last>=0 && now<last) { last=now;return false; }
        if(last<0 || now-last>=.2) { last=now;return true; }
        return false;
    }
};
}
