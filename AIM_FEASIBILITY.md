# 瞄准辅助修改：可行性调查

用户要求：编译与游戏运行不得在当前服务器执行；所有构建放在 GitHub。

当前交付是静态分析，不是已实现的自瞄补丁。

## 需要证实的入口

1. 是否存在游戏自身的 AimAssist/AutoAim 实现，以及启用条件。
2. 玩家控制器、角色、阵营、存活状态与视角控制的实际类型和调用关系。
3. 目标可见性、骨骼位置与屏幕投影的实际接口。
4. 修改方式：原工程修改，或与本包版本匹配的原生补丁；不能仅凭通用 Unreal 函数名直接假设偏移。

字符串或符号存在仅用于定位候选入口，不证明函数可调用、布局兼容或功能已经启用。需要进一步反汇编/交叉引用确认。

## 构建边界

GitHub Actions 的 macOS runner 可承担后续原生模块构建。现有 IPA 不能直接作为 Unreal 工程重编译；完整重编译需要原工程、对应引擎与 iOS 工具链。修改后的 IPA 在设备上安装还涉及有效签名与描述文件，当前未提供这些材料。

没有添加伪造的可运行补丁、硬编码猜测偏移或声称通过测试的构建产物。

## 已找到的游戏自身实现

静态字符串和 C++ 符号中存在 `AFHPlayerController::TickAimAssist()` 与 `ApplyAimAssistFollow()`，以及控制项：

- `FH.AimAssist`
- `FH.AimAssist.AdsOnly`
- `FH.AimAssist.FollowOn` / `Follow`
- `FH.AimAssist.RangeCm`
- `FH.AimAssist.Slow`
- `FH.AimAssist.SmoothRate`
- `FH.AimAssist.PitchShare` / `FiringPitch`

还有 `AimAssistTarget`、`AimAssistBlocked`、`AimAssistLastBlocker` 等字段。这表明游戏自身包含瞄准辅助实现，是后续定位的直接依据；不证明当前默认值、修改可达性、控制项是否被 Shipping 构建限制或能够实现强制锁头。

原始关键词上下文留在本地，仓库仅保存筛选后的相关符号 `evidence/aim-symbols.txt`。下一步需要定位函数体及控制变量注册/读取位置，才能决定采用参数修改还是原生补丁。本次没有构建或测试自瞄功能。
