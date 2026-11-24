#pragma once
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>

namespace fh {
constexpr uintptr_t kSettingsOffset = 0x0eb22430;
constexpr std::array<uint8_t, 16> kUUID = {0xc1,0x80,0xd5,0xc9,0x19,0xa5,0x3a,0x9d,0x9f,0x63,0x54,0x36,0x07,0xfd,0xf1,0x75};
// Actual scalar storage read by this build, not an inferred Unreal object layout.
constexpr std::array<size_t, 7> kWordIndices = {0,2,3,4,5,6,10};
using Words = std::array<uint32_t, 11>;
inline uint32_t bits(float f) { uint32_t b; std::memcpy(&b,&f,4); return b; }
inline float number(uint32_t b) { float f; std::memcpy(&f,&b,4); return f; }
inline float clamp(float f,float lo,float hi,float fallback) {
    return std::isfinite(f) ? (f<lo ? lo : (f>hi ? hi : f)) : fallback;
}
struct Options {
    bool adsOnly = true;
    float follow = 1.0f;
    float rangeMeters = 80.0f;
    float paddingCm = 80.0f;
};
inline bool plausible(const Words& w) {
    if (w[0]>1 || w[4]>1 || w[6]>1) return false;
    const float slow=number(w[2]),pad=number(w[3]),follow=number(w[5]),range=number(w[10]);
    return std::isfinite(slow) && slow>=0 && slow<=1 &&
        std::isfinite(pad) && pad>=0 && pad<=10000 &&
        std::isfinite(follow) && follow>=0 && follow<=100 &&
        std::isfinite(range) && range>=100 && range<=1000000;
}
struct Session {
    Words original{}, last{};
    bool active=false;
    bool begin(const Words& current) {
        if (active) return true;
        if (!plausible(current)) return false;
        original=current;last=current;active=true;return true;
    }
    Words desired(const Words& current,const Options& opt) {
        Words w=current;
        w[0]=1; w[2]=bits(0.25f);
        w[3]=bits(clamp(opt.paddingCm,20,200,80));
        w[4]=opt.adsOnly?1:0;
        w[5]=bits(clamp(opt.follow,0.5f,2.0f,1.0f));
        w[6]=1;
        w[10]=bits(clamp(opt.rangeMeters,20,150,80)*100.0f);
        last=w;return w;
    }
    // Restore only values that are still ours; preserve subsequent external changes.
    Words restored(const Words& current) const {
        Words w=current;
        for (size_t i:kWordIndices) if (w[i]==last[i]) w[i]=original[i];
        return w;
    }
};
}
