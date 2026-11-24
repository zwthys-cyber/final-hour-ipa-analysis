# 独立头部瞄准（实验实现）

适配范围与地图插件相同：指定 FINAL HOUR 0.2.10 主程序 UUID。
不把原生跟随倍率调高称作锁头：原生 TickAimAssist 计算的是胶囊范围上的候选点。
新增逻辑读取真实骨骼并直接调用原生视角设置接口，与地图开关独立。

静态核对记录：

- `FName(char const*)`，0x100969eec：通过 x0 的 this 指针写入 8 字节 FName。
- `USkeletalMeshComponent::StaticClass`，0x102f12858：跳转到原生类构造入口。
- `AActor::GetComponentByClass`，0x102e524d0：x1 指向 TSubclassOf 的类指针存储。
- `USkinnedMeshComponent::GetBoneIndex(FName)`，0x103314660：检查 head 骨骼是否存在。
- `USceneComponent::GetSocketLocation(FName)`，0x1032ef66c：通过虚表 +0x588 调用实际组件的 GetSocketTransform，
  然后以 d0/d1/d2 返回世界位置；骨骼不存在时不调用该接口，避免误用组件原点。
- `AController::LineOfSightTo`，0x10338dd10：角色在 x1，观察点经 d0/d1/d2 传入。
- `AController::SetControlRotation`，0x10338d870：旋转经 x1 指针传入，控制旋转位于控制器 +0x348。
- CameraManager 在控制器 +0x388；其虚表 +0x838 返回观察位置，沿用已核对的 ApplyAimAssistFollow 调用形式。
- 本地 Pawn 在控制器 +0x308；存活、敌我、角色收集均复用地图分析已核对的原生接口。

`HeadAim.hpp` 在 HUD 包装回调的游戏线程内执行，每帧重新选择目标，不跨帧保存对象指针。
只考虑存活的非友方；150 米以内、俯仰/偏航角差合成不超过 12 度的头骨骼候选中，
选择角差最小且通过原生视线检查的角色。不自动开火，不修改命中判定或子弹。
没有有效骨骼或目标时不写视角，关闭后不再写视角；不把关闭时的视角恢复到开启前。

视线检查针对角色整体，可能在头部被掩体遮住、身体其他部分可见时通过。
目标切换、人物骨骼命名、不同镜头偏移、原生跟瞄与后坐力之间的交互，均需真机验证。
“锁头：开”只代表功能开关和 HUD 接入状态，不代表已经找到有效目标或已验证命中。
静态证据位于 evidence/aimlock；GitHub 的数学测试覆盖角度、yaw 接缝、范围、无效值和零距离。
编译成功不证明原生接口在实际设备上的调用时机、动画骨骼和瞄准结果正确。

后续更新：FH 0.3 将角差扩大至 60 度、枚举多个网格，增加输入与状态报告，详见 AUTO_FIRE_RESEARCH.zh-CN.md；上文为首版分析记录。
