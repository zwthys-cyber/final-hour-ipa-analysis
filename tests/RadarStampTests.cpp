#include "../plugin/RadarStamp.hpp"
#include <cassert>
int main() {
    // An enemy with no previous reveal receives a temporary stamp and returns to its sentinel.
    uint64_t slot=UINT64_MAX;
    assert(radar::beginStamp(&slot,UINT64_MAX,100));
    assert(slot==100);
    assert(radar::restoreStamp(&slot,100,UINT64_MAX));
    assert(slot==UINT64_MAX);
    // A real shot arriving during drawing must survive restoration.
    slot=10;
    assert(radar::beginStamp(&slot,10,100));
    __atomic_store_n(&slot,uint64_t(101),__ATOMIC_RELAXED);
    assert(!radar::restoreStamp(&slot,100,10));
    assert(slot==101);
    // A newer value arriving before the override must not be lost either.
    assert(!radar::beginStamp(&slot,10,100));
    assert(slot==101);
    // Consecutive frames never accumulate a persistent timestamp.
    for(int i=0;i<10000;++i) {
        assert(radar::beginStamp(&slot,101,200));
        assert(radar::restoreStamp(&slot,200,101));
    }
}
