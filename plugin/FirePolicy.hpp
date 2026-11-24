#pragma once
#include <cstdint>
#include <cmath>
namespace firepolicy {
struct Gate {
    uint64_t target=0;unsigned frames=0;
    bool update(bool enabled,uint64_t candidate,double error) {
        if(!enabled || !candidate || !std::isfinite(error) || error>1.0 || error<0) {
            target=0;frames=0;return false;
        }
        if(candidate!=target) { target=candidate;frames=1;return false; }
        if(frames<2) ++frames;
        return frames>=2;
    }
};
}
