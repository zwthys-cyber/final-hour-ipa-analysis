#include "../plugin/HeadMath.hpp"
#include <cassert>
#include <limits>
int main() {
    using namespace headmath;
    Rotation result{};double error=0;
    assert(solve({0,0,0},{1000,0,100},{0,0,0},result,error));
    assert(std::abs(result.pitch-5.7105931375)<1e-8 && result.yaw==0);
    assert(solve({0,0,0},{-1000,-1,0},{0,179,0},result,error));
    assert(error<2); // Crossing the yaw seam must not rotate almost a full turn.
    assert(!solve({0,0,0},{0,1000,0},{0,0,0},result,error));
    assert(!solve({0,0,0},{15001,0,0},{0,0,0},result,error));
    assert(!solve({0,0,0},{0,0,0},{0,0,0},result,error));
    assert(!solve({0,0,0},{std::numeric_limits<double>::quiet_NaN(),0,0},{0,0,0},result,error));
    assert(!solve({0,0,0},{1000,0,0},{std::numeric_limits<double>::infinity(),0,0},result,error));
}
