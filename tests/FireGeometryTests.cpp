#include "../plugin/FireGeometry.hpp"
#include <cassert>
#include <limits>
int main() {
    using headmath::Vector;using aim::Part;
    const Vector eye{0,0,0},point{15000,0,0};
    double head=firegeometry::tolerance(eye,point,Part::Head);
    double body=firegeometry::tolerance(eye,point,Part::Body);
    assert(head>0 && head<.03 && body>head && body<.06);
    assert(firegeometry::tolerance(eye,{100,0,0},Part::Body)==.35);
    assert(firegeometry::tolerance(eye,point,Part::Off)==0);
    assert(firegeometry::tolerance(eye,eye,Part::Head)==0);
    assert(firegeometry::tolerance(eye,{15001,0,0},Part::Head)==0);
    assert(firegeometry::confirmed(42,42,true,false,{14990,0,0},point,Part::Head));
    assert(!firegeometry::confirmed(43,42,true,false,point,point,Part::Body)); // A wall/teammate/other enemy.
    assert(!firegeometry::confirmed(42,42,false,false,point,point,Part::Body));
    assert(!firegeometry::confirmed(42,42,true,true,point,point,Part::Body)); // Initial overlap is ambiguous.
    assert(!firegeometry::confirmed(42,42,true,false,{14950,0,0},point,Part::Body));
    assert(!firegeometry::confirmed(42,42,true,false,{14980,0,0},point,Part::Head));
    assert(firegeometry::confirmed(42,42,true,false,{14980,0,0},point,Part::Body));
    assert(!firegeometry::confirmed(42,42,true,false,point,point,Part::Off));
    assert(!firegeometry::confirmed(0,0,true,false,point,point,Part::Body));
    assert(!firegeometry::confirmed(42,42,true,false,{std::numeric_limits<double>::quiet_NaN(),0,0},point,Part::Body));
}
