#pragma once
#include "HeadMath.hpp"
#include "AimMode.hpp"
#include <algorithm>
#include <cstdint>
namespace firegeometry {
inline double tolerance(headmath::Vector eye,headmath::Vector point,aim::Part part) {
    if(part==aim::Part::Off || !headmath::finite(eye) || !headmath::finite(point)) return 0;
    double distance=std::hypot(std::hypot(point.x-eye.x,point.y-eye.y),point.z-eye.z);
    if(!std::isfinite(distance) || distance<1 || distance>15000) return 0;
    double radius=part==aim::Part::Head?6.0:15.0;
    return std::min(.35,std::atan2(radius,distance)*57.29577951308232);
}
inline bool confirmed(uintptr_t hitActor,uintptr_t target,bool blocking,bool overlap,
                      headmath::Vector impact,headmath::Vector point,aim::Part part) {
    if(!target || hitActor!=target || !blocking || overlap || part==aim::Part::Off ||
       !headmath::finite(impact) || !headmath::finite(point)) return false;
    double miss=std::hypot(std::hypot(impact.x-point.x,impact.y-point.y),impact.z-point.z);
    return std::isfinite(miss) && miss<=(part==aim::Part::Head?12.0:40.0);
}
}
