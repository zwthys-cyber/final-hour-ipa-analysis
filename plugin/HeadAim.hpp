// Included inside namespace radar, after the verified native read/function helpers.
static std::atomic<bool> headEnabled{false};
static void lockHead(uintptr_t world) {
    using headmath::Vector;using headmath::Rotation;
    if(!headEnabled.load(std::memory_order_relaxed)) return;
    uintptr_t pc=function<uintptr_t(*)(uintptr_t)>(0x0414c414)(world);
    uintptr_t pawn=0,camera=0,cameraTable=0,cameraLocation=0;
    Rotation view{};
    if(!pc || !read(pc+0x308,pawn) || !pawn || !read(pc+0x348,view) ||
       !read(pc+0x388,camera) || !camera || !read(camera,cameraTable) ||
       !read(cameraTable+0x838,cameraLocation) || !Readable(cameraLocation,4,false)) return;
    auto alive=function<bool(*)(uintptr_t)>(0x075aab38);
    if(!alive(pawn)) return;
    Vector eye=reinterpret_cast<Vector(*)(uintptr_t)>(cameraLocation)(camera);
    if(!headmath::finite(eye)) return;
    static uint64_t headName=0;
    if(!headName) function<void(*)(uint64_t *,const char *)>(0x00969eec)(&headName,"head");
    uintptr_t meshClass=function<uintptr_t(*)()>(0x02f12858)();
    if(!meshClass || !headName) return;
    Bodies bodies;
    function<void(*)(uintptr_t,Bodies *)>(0x07442a7c)(world,&bodies);
    uintptr_t data=bodies.heap?bodies.heap:reinterpret_cast<uintptr_t>(bodies.local);
    Rotation best{};double bestError=13;bool found=false;
    if(bodies.count>=0 && bodies.count<=512 && bodies.capacity>=bodies.count &&
       Readable(data,static_cast<size_t>(bodies.count)*sizeof(uintptr_t),false)) {
        for(int32_t i=0;i<bodies.count;++i) {
            uintptr_t actor=0;
            if(!read(data+i*sizeof(uintptr_t),actor) || !actor || actor==pawn || !Readable(actor,0x20,false)) continue;
            if(!alive(actor) || function<bool(*)(uintptr_t,uintptr_t)>(0x0793b324)(pawn,actor)) continue;
            uintptr_t mesh=function<uintptr_t(*)(uintptr_t,const uintptr_t *)>(0x02e524d0)(actor,&meshClass);
            if(!mesh || !Readable(mesh,0x20,false)) continue;
            if(function<int32_t(*)(uintptr_t,uint64_t)>(0x03314660)(mesh,headName)<0) continue;
            Vector head=function<Vector(*)(uintptr_t,uint64_t)>(0x032ef66c)(mesh,headName);
            Rotation target{};double error=0;
            if(!headmath::solve(eye,head,view,target,error) || error>=bestError) continue;
            if(!function<bool(*)(uintptr_t,uintptr_t,Vector,bool)>(0x0338dd10)(pc,actor,eye,false)) continue;
            best=target;bestError=error;found=true;
        }
    }
    if(bodies.heap) function<void(*)(uintptr_t)>(0x0067d710)(bodies.heap);
    // Recheck the independent switch immediately before changing the view.
    if(found && headEnabled.load(std::memory_order_relaxed))
        function<void(*)(uintptr_t,const Rotation *)>(0x0338d870)(pc,&best);
}
