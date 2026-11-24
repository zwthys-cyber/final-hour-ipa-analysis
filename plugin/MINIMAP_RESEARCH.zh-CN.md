# 小地图敌人标记：0.2.10 静态核对

当前源码实现单开关的原生小地图持续标记实验版；尚未真机验证。
静态反汇编在 GitHub Actions 执行：
https://github.com/zwthys-cyber/final-hour-ipa-analysis/actions/runs/45400215668

主程序 UUID 与现有插件一致。原生 `AFHHud::DrawMinimap()` 位于
`0x107a9ef48`，函数长度 17128 字节；用于复核的小段机器码保存在
`evidence/minimap/`。这不是完整游戏程序。

已确认的调用及条件：

- `0x107aa0b18` 调用 `UFHBodyRegistry::Gather(UWorld const*, TArray<AFHCharacterBase*>&)` 收集角色。
- `0x107aa0d8c` 调用 `FHDamage::IsBodyAlive(AActor const*)`，排除非存活角色。
- `0x107aa0de0` 调用 `FHTeam::IsFriendly(AActor const*, AActor const*)` 区分敌我。
- 非友方分支在 `0x107aa0e7c` 读取角色 `+0xbe8` 的 double 时间戳。
  小于零即跳过；随后用世界时间减去该时间戳。
- `0x107aa0e98` 读取全局 `0x10eb2439c` 的 float（文件初值 3.0），
  若已过去的时间超过该值则跳过；后续以这个时间差计算标记透明度。

以上支持“原生红点有时间窗口”的结论；时间戳具体写入来源尚未完整追踪，
该时间戳的所有写入来源仍需进一步核对。不能把延长窗口称为所有敌人持续显示；
从未有有效时间戳的角色仍会被前面的条件排除。

目前未验证该版本在实际对局是否向客户端提供所有敌人的坐标，
也未做真机注入或地图旋转/缩放测试。不能据静态反汇编宣称功能可用。

## 实现

`Minimap.hpp` 使用指定 AFHHud 的实例虚表副本替换 DrawHUD 虚方法。
静态原虚表从 `0x10e02e268` 开始，长度 `0x800`（含两个 ABI 头项），
第 252 项是 `AFHHud::DrawHUD`（`0x107a82154`）；对象中的虚表指针指向头项之后。
只接受与原虚表地址完全一致的 HUD，不修改可执行页面。虚表副本为进程期静态存储，
换图复用；关闭后包装函数直接调用原 DrawHUD。

安装使用 `GWorld`（`0x10ec5b818`）、`UWorld::GetFirstPlayerController`
（`0x10414c414`），以及已核对的 PlayerController `+0x380` HUD 字段。
绘制回调由游戏自己的线程调用；仅在回调内调用 `AActor::GetWorld`
（`0x102e43cb0`）和原生 `UFHBodyRegistry::Gather`。
Gather 的 16 项 inline TArray 大小为 144，heap/num/cap 位于 +128/+136/+140；
溢出分配使用游戏自己的 `FMemory::Free`（`0x10067d710`）释放。

每帧在原 DrawHUD 之前，为已收集角色临时写入当前世界时间（UWorld +0x9d0）
到角色 +0xbe8。原生地图继续处理存活、敌我、坐标投影、范围、透明度与地图旋转。
绘制结束立即以 compare-and-swap 恢复原位模式；若值已变化则保留新的值。
不缓存角色指针跨帧。读写有内存保护、对齐和数值检查；超过 512 个角色则该帧不修改。

这会在 DrawHUD 调用期间短暂改变角色的标记时间戳，范围覆盖整个 HUD 绘制，
并非只覆盖 DrawMinimap；其他读取该字段的 HUD 分支或并发读者可能看到临时值。
compare-and-swap 无法识别并发写入了相同位模式的情况。这些边界尚需真机验证，
不能承诺对其他逻辑完全无影响。原生地图范围外、服务器未同步的位置不会凭空显示。

`RadarStampTests.cpp` 检查无效时间戳的恢复、绘制期间的新值保留、过期写入被拒绝，
以及连续帧恢复。测试与编译只在 GitHub 执行；本地仅静态读取与编辑。
