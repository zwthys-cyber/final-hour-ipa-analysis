// Included inside radar. Exact 0.2.10 ABI, checked against native trace and BreakHitResult.
enum class RayState { None,Clear,NoBlock,OtherActor,WrongPart,Unavailable };
static std::atomic<RayState> lastRay{RayState::None};
static bool traceShot(uintptr_t world,uintptr_t pawn,uintptr_t target,headmath::Vector eye,
                      headmath::Rotation view,headmath::Vector point,aim::Part part) {
    using headmath::Vector;
    constexpr double radians=.017453292519943295;
    double pitch=view.pitch*radians,yaw=view.yaw*radians;
    Vector end{eye.x+15000*std::cos(pitch)*std::cos(yaw),
               eye.y+15000*std::cos(pitch)*std::sin(yaw),eye.z+15000*std::sin(pitch)};
    if(!world || !pawn || !target || !headmath::finite(eye) || !headmath::finite(end)) {
        lastRay.store(RayState::Unavailable);return false;
    }
    // Convert Visibility (3) using this game's channel mapping rather than assuming a TraceTypeQuery index.
    int32_t channel=function<int32_t(*)(int32_t)>(0x034ee468)(3);
    if(channel<0 || channel>=32) { lastRay.store(RayState::Unavailable);return false; }
    struct IgnoreArray { uintptr_t *data;int32_t count,capacity; } ignore{&pawn,1,1};
    struct Color { float r,g,b,a; };
    static_assert(sizeof(IgnoreArray)==16 && sizeof(Color)==16);
    alignas(16) uint8_t hit[512]{};
    using Trace=bool(*)(uintptr_t,Vector,Vector,int32_t,bool,const IgnoreArray *,int32_t,
                        void *,bool,Color,Color,float);
    bool result=function<Trace>(0x0370de68)(world,eye,end,channel,true,&ignore,0,hit,true,
                                           Color{0,0,0,0},Color{0,0,0,0},0);
    // BreakHitResult verifies blocking/overlap at +0xad, impact at +0x28 and actor handle at +0xb8.
    bool blocking=(hit[0xad]&1)!=0,overlap=(hit[0xad]&2)!=0;
    if(!result || !blocking || overlap) { lastRay.store(RayState::NoBlock);return false; }
    // Character actors already have a weak actor in the handle. Fail closed for lazy instance handles;
    // do not ask FetchActor to spawn an actor for instanced scenery.
    uintptr_t hitActor=function<uintptr_t(*)(const void *)>(0x01088aa4)(hit+0xb8);
    if(hitActor!=target) { lastRay.store(RayState::OtherActor);return false; }
    Vector impact{};std::memcpy(&impact,hit+0x28,sizeof(impact));
    bool exact=firegeometry::confirmed(hitActor,target,blocking,overlap,impact,point,part);
    lastRay.store(exact?RayState::Clear:RayState::WrongPart);return exact;
}
