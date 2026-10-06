# Stockfish 分发核查

日期：2026-09-17。基于应用提交 32bbe8f 和本机实际构建依赖。本记录是工程合规排查，不是法律意见或商店审核保证；未改变项目许可证、未提交商店。

## 已确认的技术事实

- App 的 StockfishHintEngine 导入 ChessKitEngine 并创建 Engine(type: .stockfish)。
- ChessKitEngine revision：a2b47697e5f90418623a1e06c58fd36cd3289fca。
- Package.swift 把 ChessKitEngineCore 作为库依赖；stockfish+engine.cpp 直接调用 Stockfish 的 _main。没有独立进程边界。
- Stockfish revision：23f320bac6b554f6470d51f10b96613a7cd7b03d；源码头声明 GPL-3.0-or-later。
- lc0 revision：a78b208cf19ce45cfc32ed57e651ae661dbcb5c3。macOS Release 主可执行文件的 nm 输出同时包含 Stockfish 和 lczero 符号；第三方材料必须覆盖实际链接依赖，不能只记录被界面选用的引擎。
- GitHub 仓库为 PUBLIC，但 licenseInfo 为 null，根目录没有 LICENSE。公开可读不等于明确授予 GPL 权利。
- 两份 NNUE 网络文件由脚本按固定 SHA-256 下载；源码发布材料必须记录并保留实际对应的网络文件及其许可来源。

## 许可结论与不确定性

Stockfish 维护者在 2026-04-12 的回复明确区分“独立程序调用”和“链接进宿主程序”：后者要求 GPL 宿主。当前实现属于后者。MIT 包装库不解除引擎许可义务，改用动态链接也不是可靠绕过方式。

因此，沿用当前实现的工程方案应是：明确按 GPL-3.0-or-later 分发整个组合应用，同时保留第三方各自的许可和版权声明。原创素材的授权范围也应明确。仅添加 Stockfish 链接、把仓库设为公开、或声明免费均不够。

App Store 是另一个问题。苹果当前标准 EULA 和自定义 EULA 的最低要求包含不可转让、Apple 设备范围等限制；GPL 第 10 节禁止进一步限制接收者权利。标准 EULA 对开源组件的某些逆向限制有例外，但这不能自动证明所有限制都已解决。2010 年 FSF 的 App Store 执法材料属于历史证据，不能直接代替当前判断。商店里存在 Stockfish 应用也不是我们的合规保证。

未找到覆盖当前应用组合的 App Store 特别授权。需要针对最终使用的开发者协议、EULA 和实际交付方式确认相容性，不能承诺“加 GPL LICENSE 就一定能上架”，也不能据此断言所有 GPL 应用都不能上架。

## 可执行路径

### 保留 Stockfish

先由项目所有者确定是否接受 GPL-3.0-or-later 的整体分发授权。这会允许接收者在遵守 GPL 的条件下修改、再分发和商业使用，并不是仅允许查看源码。

接受后可准备：

1. 项目 LICENSE 和清晰的原创代码/素材授权范围；第三方原有许可保持原样。
2. 应用内开源声明与源码入口，随包附许可证、版权信息。
3. 每个发布版本对应的源代码快照、依赖及子模块精确 revision、实际补丁、构建脚本、NNUE 文件与获取/校验说明。保护签名私钥与账号凭证，不将其放入源码包。
4. 核对 lc0/Eigen 等实际链接依赖的声明和源码义务；必要时再评估精简未使用引擎，不能仅凭未调用就漏报。
5. 核实当前 App Store 分发条件与 GPL 的相容性，未解决前不将该检查项标记通过。

### 不接受整体 GPL

需要换成明确允许所需分发方式的引擎，并重新验证难度档位和提示质量。不能把改成 WASM/WebView 当成已经确认的许可豁免；远程引擎会改变目前的离线产品定位。

## 原始资料

- Stockfish 维护者解释：https://github.com/official-stockfish/Stockfish/discussions/6723
- Stockfish 分发说明：https://stockfishchess.org/about/
- GPL 原文：https://www.gnu.org/licenses/gpl-3.0.en.html
- GPL 链接说明：https://www.gnu.org/licenses/gpl-faq.en.html#GPLStaticVsDynamic
- Apple 标准 EULA：https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
- Apple 开发者协议及自定义 EULA 最低要求：https://developer.apple.com/support/terms/apple-developer-program-license-agreement/
- FSF 历史材料（2010，非当前最终结论）：https://www.fsf.org/news/2010-05-app-store-compliance/
