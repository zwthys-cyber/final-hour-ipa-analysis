#pragma once
#include <cmath>
namespace headmath {
struct Vector { double x,y,z; };
struct Rotation { double pitch,yaw,roll; };
static_assert(sizeof(Vector)==24 && sizeof(Rotation)==24);
inline bool finite(Vector p) { return std::isfinite(p.x)&&std::isfinite(p.y)&&std::isfinite(p.z); }
inline double wrap(double d) { return std::remainder(d,360.0); }
inline bool solve(Vector eye,Vector head,Rotation current,Rotation &result,double &error) {
    if(!finite(eye)||!finite(head)||!std::isfinite(current.pitch)||!std::isfinite(current.yaw)) return false;
    double x=head.x-eye.x,y=head.y-eye.y,z=head.z-eye.z;
    double horizontal=std::hypot(x,y),distance=std::hypot(horizontal,z);
    if(!std::isfinite(distance)||distance<1||distance>15000) return false;
    constexpr double degrees=57.29577951308232;
    result={std::atan2(z,horizontal)*degrees,std::atan2(y,x)*degrees,0};
    if(std::abs(result.pitch)>89) return false;
    error=std::hypot(wrap(result.pitch-current.pitch),wrap(result.yaw-current.yaw));
    return error<=60;
}
}
