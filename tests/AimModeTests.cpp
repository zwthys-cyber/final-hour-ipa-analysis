#include "../plugin/AimMode.hpp"
#include <cassert>
#include "../plugin/FirePolicy.hpp"
int main() {
    using namespace aim;
    auto part=toggle(Part::Off,Part::Head);
    assert(part==Part::Head);
    part=toggle(part,Part::Body);assert(part==Part::Body);
    assert(forAutoFire(part)==Part::Body); // Auto-fire must not silently select head.
    part=toggle(part,Part::Body);assert(part==Part::Off);
    assert(forAutoFire(part)==Part::Head);
    assert(toggle(Part::Body,Part::Head)==Part::Head);
    assert(toggle(Part::Head,Part::Head)==Part::Off);
    auto all=[](Bone){return true;};
    assert(selectBone(Part::Head,all)==Bone::Head);
    assert(selectBone(Part::Body,all)==Bone::UpperChest);
    assert(selectBone(Part::Body,[](Bone b){return b==Bone::Chest;})==Bone::Chest);
    assert(selectBone(Part::Body,[](Bone b){return b==Bone::LowerChest;})==Bone::LowerChest);
    assert(selectBone(Part::Body,[](Bone b){return b==Bone::Head;})==Bone::None);
    assert(selectBone(Part::Head,[](Bone b){return b==Bone::Chest;})==Bone::None);
    firepolicy::Gate gate;
    assert(!gate.update(true,99,.2,static_cast<uint32_t>(Part::Head)));
    assert(gate.update(true,99,.2,static_cast<uint32_t>(Part::Head)));
    // Same enemy, different body part: reacquire instead of firing at the old alignment.
    assert(!gate.update(true,99,.2,static_cast<uint32_t>(Part::Body)));
    assert(gate.update(true,99,.2,static_cast<uint32_t>(Part::Body)));
    assert(!gate.update(true,99,.2,static_cast<uint32_t>(Part::Head)));
    bool queried=false;
    assert(selectBone(Part::Off,[&](Bone){queried=true;return true;})==Bone::None);
    assert(!queried);
}
