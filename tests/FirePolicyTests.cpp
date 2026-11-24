#include "../plugin/FirePolicy.hpp"
#include <cassert>
#include <limits>
int main() {
    firepolicy::Gate gate;
    assert(!gate.update(false,12,0));
    assert(!gate.update(true,12,4));
    assert(!gate.update(true,12,.5));
    assert(gate.update(true,12,.5));
    assert(!gate.update(true,13,.5));
    assert(gate.update(true,13,.5));
    assert(!gate.update(true,0,0));
    assert(!gate.update(true,13,.5));
    assert(!gate.update(true,13,std::numeric_limits<double>::quiet_NaN()));
    assert(!gate.update(true,13,.5));
    assert(gate.update(true,13,.5));
    assert(!gate.update(false,13,.5));
    assert(!gate.update(true,13,.5));
}
