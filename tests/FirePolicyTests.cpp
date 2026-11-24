#include "../plugin/FirePolicy.hpp"
#include <cassert>
#include <limits>
static bool sample(firepolicy::Gate &g,double t,bool clear=true,double error=.1,unsigned mode=1) {
    return g.update(true,42,error,mode,t,.2,clear);
}
static void acquire(firepolicy::Gate &g,double t,unsigned mode=1) {
    assert(!sample(g,t,true,.1,mode));
    assert(!sample(g,t+.05,true,.1,mode));
    assert(!sample(g,t+.10,true,.1,mode));
    assert(sample(g,t+.16,true,.1,mode));
}
int main() {
    firepolicy::Gate g;
    assert(!g.update(true,42,.1)); // No direct hit proof: fail closed.
    acquire(g,1);
    assert(!sample(g,1.17,false)); // Occlusion must stop immediately, even while already firing.
    acquire(g,1.18);
    assert(!sample(g,1.35,true,.1,2)); // Same actor, different body part: restart dwell.
    assert(!sample(g,1.40,true,.1,2));
    assert(!sample(g,1.45,true,.1,2));
    assert(sample(g,1.51,true,.1,2));
    assert(!sample(g,1.52,true,.3,2)); // Outside the distance-adjusted angular limit.
    acquire(g,1.53,2);
    assert(!sample(g,1.70,true,std::numeric_limits<double>::quiet_NaN(),2));
    acquire(g,1.71,2);
    assert(!sample(g,2.2,true,.1,2)); // A stalled HUD cannot reuse the old confirmation.
    assert(!sample(g,2.1,true,.1,2)); // Time moving backwards also restarts dwell.
    assert(!g.update(false,42,.1,2,2.15,.2,true));
    assert(!g.update(true,0,.1,2,2.2,.2,true));
    assert(!g.update(true,42,.1,2,2.2,1,true)); // No widening the cap back to one degree.
    assert(!g.update(true,42,.1,2,2.2,0,true));
    assert(!g.update(true,42,.1,2,std::numeric_limits<double>::infinity(),.2,true));
    firepolicy::Gate retarget;
    acquire(retarget,3);
    assert(!retarget.update(true,43,.1,1,3.17,.2,true));
    assert(!retarget.update(true,43,.1,1,3.22,.2,true));
    assert(!retarget.update(true,43,.1,1,3.27,.2,true));
    assert(retarget.update(true,43,.1,1,3.33,.2,true));
    firepolicy::Pulse pulse;
    assert(!pulse.due(false,10));
    assert(pulse.due(true,10));
    assert(!pulse.due(true,10));assert(!pulse.due(true,10.1));
    assert(pulse.due(true,10.201));
    assert(!pulse.due(false,10.5));assert(pulse.due(true,10.5));
    assert(!pulse.due(true,10));assert(!pulse.due(true,10.05));
    assert(!pulse.due(true,std::numeric_limits<double>::quiet_NaN()));
    assert(pulse.due(true,10.21));
}
