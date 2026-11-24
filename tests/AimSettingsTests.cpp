#include "../plugin/AimSettings.hpp"
#include <cassert>
#include <limits>
int main() {
    fh::Words initial={1,fh::bits(6),fh::bits(.4f),fh::bits(40),1,fh::bits(.5f),1,fh::bits(100),fh::bits(.25f),fh::bits(15),fh::bits(5000)};
    fh::Session s; assert(s.begin(initial));
    fh::Options options; options.adsOnly=false;
    auto changed=s.desired(initial,options);
    assert(changed[4]==0 && fh::number(changed[5])==1 && fh::number(changed[10])==8000);
    for (size_t i: {1,7,8,9}) assert(changed[i]==initial[i]);
    assert(s.restored(changed)==initial);
    changed[5]=fh::bits(.8f); auto restored=s.restored(changed);
    assert(restored[5]==changed[5] && restored[10]==initial[10]);
    options.follow=std::numeric_limits<float>::quiet_NaN(); options.rangeMeters=9999; options.paddingCm=-1;
    auto bounded=s.desired(initial,options);
    assert(fh::number(bounded[5])==1 && fh::number(bounded[10])==15000 && fh::number(bounded[3])==20);
    auto bad=initial; bad[0]=99; fh::Session rejected; assert(!rejected.begin(bad) && !rejected.active);
    bad=initial;bad[10]=fh::bits(std::numeric_limits<float>::infinity());assert(!rejected.begin(bad));
    assert(s.original==initial); // Re-applying settings must not replace original snapshot.
    assert(s.begin(bounded) && s.original==initial);
}
