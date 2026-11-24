#pragma once
#include <cstdint>
namespace radar {
inline bool beginStamp(uint64_t *slot,uint64_t before,uint64_t stamp) {
    return __atomic_compare_exchange_n(slot,&before,stamp,false,__ATOMIC_RELAXED,__ATOMIC_RELAXED);
}
inline bool restoreStamp(uint64_t *slot,uint64_t stamp,uint64_t before) {
    return __atomic_compare_exchange_n(slot,&stamp,before,false,__ATOMIC_RELAXED,__ATOMIC_RELAXED);
}
}
