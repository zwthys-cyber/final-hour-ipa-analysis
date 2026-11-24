#pragma once
#include <cstddef>
#include <initializer_list>
namespace aim {
enum class Part { Off,Head,Body };
enum class Bone { Head,UpperChest,Chest,LowerChest,None };
inline Part toggle(Part current,Part requested) { return current==requested?Part::Off:requested; }
inline Part forAutoFire(Part current) { return current==Part::Off?Part::Head:current; }
inline const char *boneName(Bone bone) {
    switch(bone) {
        case Bone::Head:return "head";
        case Bone::UpperChest:return "spine_03";
        case Bone::Chest:return "spine_02";
        case Bone::LowerChest:return "spine_01";
        case Bone::None:return nullptr;
    }
    return nullptr;
}
template<class Exists> Bone selectBone(Part part,Exists exists) {
    if(part==Part::Head) return exists(Bone::Head)?Bone::Head:Bone::None;
    if(part==Part::Body)
        for(Bone b:{Bone::UpperChest,Bone::Chest,Bone::LowerChest}) if(exists(b)) return b;
    return Bone::None;
}
}
