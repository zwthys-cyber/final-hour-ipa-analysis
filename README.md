# FINAL HOUR 0.2.10 — 静态分析与注入插件

当前源码为 FH 0.4 实验版：界面默认收起为可拖动的半透明 FH 小按钮，点击展开，支持一键收起并记住位置。
保留原生小地图常显，增加默认 2 倍地图距离范围、
可复制的运行状态报告、扩大范围的头部搜敌，以及对准后自动开火开关。
用户已反馈旧版地图有效但锁头没有感知到效果，本次修正仍需设备复验。
地图常显、锁头、自动开火默认关，地图内容默认缩小；不调整人物移动速度。
旧版 v0.1.0 release 是跟瞄插件，不能当作新版下载。

- 新版构建：[GitHub Actions](https://github.com/zwthys-cyber/final-hour-ipa-analysis/actions/workflows/build-plugin.yml)，下载最新提交对应的 `FHAssist-0.2.10-arm64` artifact。
- [使用与状态报告说明](plugin/INSTALL.zh-CN.md)。
- [本次诊断、开火输入和地图缩放依据](plugin/AUTO_FIRE_RESEARCH.zh-CN.md)。
- 所有反汇编、测试、编译及签名检查在 GitHub runner 执行；当前服务器不编译或运行游戏/插件。

## 结论

样本是《FINAL HOUR》的 iOS ARM64 发行包，标识符 `com.aggames.finalhour`。从自身游戏资源和界面命名判断，是现代军事题材、支持多人组队的射击游戏，具有明显的 FPS 资源结构。不能仅凭包名认定开发商的法律主体，也不能从资源名确认线上功能是否开放。

## 身份和技术

| 项目 | 静态结果 |
|---|---|
| 文件 | `FINAL HOUR_0.2.10.ipa` |
| 显示名称 | FINAL HOUR |
| 版本 / 构建 | 0.2.10 / 0.4172 |
| EpicAppVersion 字段 | 0.4171 11-23 11:28（与构建号不同，原样记录） |
| 包标识 | com.aggames.finalhour |
| 可执行文件 | FinalHour，Mach-O 64-bit arm64 |
| 系统要求 | iOS 17.0+，arm64、Metal，iPhone/iPad，横屏 |
| 引擎 | Unreal Engine；`.uproject`、UE 插件、IoStore `.utoc/.ucas` 和 `.pak` |
| 联网组件 | EOSSDK.framework（Epic Online Services） |
| 其他组件 | MarketplaceKitWrapper.framework |

`com.Epic.Unreal` 是 URL 类型配置中的引擎默认名称，不能作为 Epic 开发了该游戏的证据。MarketplaceKit 组件本身也不能证明实际分发渠道。

## 玩法线索

自身目录 `FinalHour/Content/FH/` 比第三方模板目录更能反映游戏设计：

- 模式卡：`UI_ModeCard_TDM`、`SND`、`HP`、`FFA`、`DUEL`、`SBR`、`RBR`。TDM 通常指团队死斗，SND 指搜索与摧毁/爆破，HP 指据点，FFA 指自由混战；SBR/RBR 的准确含义尚未确认。
- 爆破操作按钮：`bomb_plant`、`bomb_drop`、`bomb_defuse`、`bomb_cancel`。
- 连杀奖励音效：Mortar、Heli、Airstrike，即迫击炮、直升机和空袭。
- 地图：`L_StadiumUE`、`L_Range`、`L_LobbyStatic`、`L_HuoGang`、`L_HuoGang_V2`、`L_DesertTown`、`L_DesertOutpost`、`L_CargoYard`、`L_Duel_Kamar`、`L_FH_Armory`。
- 包含 FPSAnimationPack、DEFINITIVE_FPS_KIT、ShooterStarter、BattleRoyaleStarterKit 等插件/素材目录。第三方模板中的 Zombies 资源不能用来断言游戏有僵尸模式。
- 自身目录存在 `AP_BattleRoyale` 音频资源，另有大逃杀模板与模式卡线索；尚未确认大逃杀是否可玩、玩家人数或地图规模。

这些内容支持“多人军事射击游戏”的判断。无法凭这些路径确认第一/第三人称切换、完整规则、服务器在线状态、开发者身份或素材授权来源。

## 网络与权限配置

Info.plist 的本地网络说明写明会直接连接队友，包括同一 Wi-Fi 的玩家。结合 EOSSDK，可确认包内有多人联网组件和相应配置，不能据此证明当前服务器可连接。

相机和麦克风用途说明均声称游戏不使用这些功能；本次未做动态验证。ATS 配置允许任意加载及本地网络，属于配置事实，不能据此断言恶意行为。

## 方法与边界

仅解析 ZIP、plist、文件清单和 Mach-O/字符串；没有在当前服务器编译、安装、启动 IPA 或执行其附带脚本，也没有连接游戏后端。不是完整源码还原或动态玩法测试。

当前服务器约 1GB 内存；首次尝试整文件字符串提取后用户报告服务器卡死，原因未独立确认。后续改为 1MiB 分块关键词检索、96MiB 地址空间和 20 秒 CPU 上限、低优先级读取。扫描脚本位于 `tools/scan_binary.py`，没有任何加载或运行目标二进制的逻辑。

仓库保存分析文档、插件源码、工具和静态证据，不上传完整 IPA、完整游戏二进制、视频或美术资源；静态证据中仅包含用于核对的小段函数机器码。无需构建即可阅读，未创建自动运行游戏的工作流。

## 证据

- `evidence/info.json`：应用主 Info.plist 的 JSON 转写。
- `evidence/archive.json`：ZIP 条目及大小。
- `evidence/Manifest_UFSFiles_IOS.txt`：包内原始资源清单。
- `evidence/gameplay-paths.txt`：玩法相关路径摘录。
- `evidence/uecommandline.txt`：UE 启动参数文本（未执行）。

主程序 LC_ENCRYPTION_INFO_64 的 cryptid 为 0（offset=16384，size=221872128），未标记为 FairPlay 代码加密；这不等于资源容器一定未加密。
