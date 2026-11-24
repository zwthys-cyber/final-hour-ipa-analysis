// Included inside namespace radar, after the verified native read/function helpers.
static std::atomic<aim::Part> reportedPart{aim::Part::Off};
static std::atomic<unsigned> headState{0},enemyCount{0},boneCount{0},angleCount{0},visibleCount{0};
static std::atomic<unsigned> cameraErrorMilliDegrees{0};
static std::atomic<uint64_t> hudFrames{0},viewWrites{0};
struct Components {
    uintptr_t data=0;int32_t count=0,capacity=0;
    ~Components() { if(data) function<void(*)(uintptr_t)>(0x0067d710)(data); }
};
static void lockAim(uintptr_t world) {
    using headmath::Vector;using headmath::Rotation;
    FireFrame fire;
    const aim::Part part=aimPart.load(std::memory_order_relaxed);
    fire.part=part;reportedPart.store(part);
    static aim::Part lastPart=aim::Part::Off;
    if(part!=lastPart) {
        fireGate.update(false,0,0);lastPart=part;
    }
    if(part==aim::Part::Off) {
        fireGate.update(false,0,0);headState.store(0);return;
    }
    enemyCount.store(0);boneCount.store(0);angleCount.store(0);visibleCount.store(0);headState.store(1);
    uintptr_t pc=function<uintptr_t(*)(uintptr_t)>(0x0414c414)(world);
    uintptr_t pawn=pc?function<uintptr_t(*)(uintptr_t)>(0x03b7e114)(pc):0;
    uintptr_t camera=0,cameraTable=0,cameraLocation=0;
    Rotation view{};
    if(!pc || !pawn || !Readable(pawn,0x20,false)) { headState.store(2);return; }
    if(!read(pc+0x388,camera) || !camera || !read(camera,cameraTable) ||
       !read(cameraTable+0x838,cameraLocation) || !Readable(cameraLocation,4,false)) { headState.store(3);return; }
    auto alive=function<bool(*)(uintptr_t)>(0x075aab38);
    if(!alive(pawn)) { headState.store(4);return; }
    Vector eye=reinterpret_cast<Vector(*)(uintptr_t)>(cameraLocation)(camera);
    view=function<Rotation(*)(uintptr_t)>(0x03b83608)(camera);
    if(!std::isfinite(view.pitch) || !std::isfinite(view.yaw)) { headState.store(3);return; }
    if(!headmath::finite(eye)) { headState.store(3);return; }
    static uint64_t names[4]{};
    for(size_t i=0;i<4;++i)
        if(!names[i]) function<void(*)(uint64_t *,const char *)>(0x00969eec)(&names[i],aim::boneName(static_cast<aim::Bone>(i)));
    uintptr_t meshClass=function<uintptr_t(*)()>(0x02f12858)();
    if(!meshClass) { headState.store(5);return; }
    Bodies bodies;
    function<void(*)(uintptr_t,Bodies *)>(0x07442a7c)(world,&bodies);
    uintptr_t data=bodies.heap?bodies.heap:reinterpret_cast<uintptr_t>(bodies.local);
    Rotation best{};Vector bestPoint{};double bestError=61;uintptr_t targetActor=0;
    unsigned enemies=0,bones=0,angles=0,visible=0;
    if(bodies.count>=0 && bodies.count<=512 && bodies.capacity>=bodies.count &&
       Readable(data,static_cast<size_t>(bodies.count)*sizeof(uintptr_t),false)) {
        for(int32_t i=0;i<bodies.count;++i) {
            uintptr_t actor=0;
            if(!read(data+i*sizeof(uintptr_t),actor) || !actor || actor==pawn || !Readable(actor,0x20,false)) continue;
            if(!alive(actor) || function<bool(*)(uintptr_t,uintptr_t)>(0x0793b324)(pawn,actor)) continue;
            ++enemies;
            Components meshes;
            // Same class-filtered native iterator used by execK2_GetComponentsByClass.
            // Include child actors and inspect every skeletal mesh, not just the first arms mesh.
            function<void(*)(uintptr_t,const uintptr_t *,bool,Components *)>(0x02e7f4c8)(actor,&meshClass,true,&meshes);
            if(meshes.count<0 || meshes.count>64 || meshes.capacity<meshes.count ||
               !Readable(meshes.data,static_cast<size_t>(meshes.count)*8,false)) continue;
            bool counted=false;
            for(int32_t j=0;j<meshes.count;++j) {
                uintptr_t mesh=0;
                if(!read(meshes.data+j*8,mesh) || !mesh || !Readable(mesh,0x20,false)) continue;
                aim::Bone selected=aim::selectBone(part,[&](aim::Bone bone) {
                    uint64_t name=names[static_cast<size_t>(bone)];
                    return name && function<int32_t(*)(uintptr_t,uint64_t)>(0x03314660)(mesh,name)>=0;
                });
                if(selected==aim::Bone::None) continue;
                uint64_t name=names[static_cast<size_t>(selected)];
                if(!counted) { ++bones;counted=true; }
                Vector point=function<Vector(*)(uintptr_t,uint64_t)>(0x032ef66c)(mesh,name);
                Rotation candidate{};double error=0;
                if(!headmath::solve(eye,point,view,candidate,error)) continue;
                ++angles;
                if(!function<bool(*)(uintptr_t,uintptr_t,Vector,bool)>(0x0338dd10)(pc,actor,eye,false)) continue;
                ++visible;
                if(error<bestError) { best=candidate;bestPoint=point;bestError=error;targetActor=actor; }
            }
        }
    }
    if(bodies.heap) function<void(*)(uintptr_t)>(0x0067d710)(bodies.heap);
    enemyCount.store(enemies);boneCount.store(bones);angleCount.store(angles);visibleCount.store(visible);
    headState.store(!enemies?6:(!bones?7:(!angles?8:(!targetActor?9:10))));
    // Do not apply a candidate selected for a mode the user has just changed.
    if(aimPart.load(std::memory_order_relaxed)!=part) return;
    cameraErrorMilliDegrees.store(targetActor?static_cast<unsigned>(std::round(bestError*1000)):0);
    if(overlayOpen.load()) { headState.store(13);return; }
    if(targetActor) {
        function<void(*)(uintptr_t,const Rotation *)>(0x0338d870)(pc,&best);
        Rotation after{};
        if(read(pc+0x348,after) && std::abs(headmath::wrap(after.pitch-best.pitch))<.01 &&
           std::abs(headmath::wrap(after.yaw-best.yaw))<.01) viewWrites.fetch_add(1);
        else { headState.store(11);fireGate.update(false,0,0);return; }
    }
    uint64_t key=0;
    if(targetActor) function<void(*)(uint64_t *,const uintptr_t *)>(0x0108881c)(&key,&targetActor);
    double tolerance=firegeometry::tolerance(eye,bestPoint,part);
    bool requested=fireEnabled.load() && aimPart.load()==part && !overlayOpen.load();
    bool exact=requested && targetActor && bestError<=tolerance &&
        traceShot(world,pawn,targetActor,eye,view,bestPoint,part);
    fire.now=std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
    fire.gateEvaluated=true;
    bool ready=fireGate.update(requested,key,bestError,static_cast<uint32_t>(part),fire.now,tolerance,exact);
    if(ready) {
        uintptr_t combatClass=function<uintptr_t(*)(int)>(0x07357440)(0);
        if(combatClass) fire.component=function<uintptr_t(*)(uintptr_t,const uintptr_t *)>(0x02e524d0)(pawn,&combatClass);
        if(!fire.component) headState.store(12);
    }
}
