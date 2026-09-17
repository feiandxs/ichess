# 首次商店发布检查

检查日期：2026-09-17。基线：ad71709；本分支仅按用户要求清理棋子授权问题。未登录 App Store Connect、创建证书或提交审核。

## 检查结果

| 项目 | 结果及剩余工作 |
| --- | --- |
| 图标 | iOS 1024×1024，macOS 16/32/64/128/256/512/1024 尺寸齐全，全部为 8-bit、不透明 PNG；已查看图像，没有旧名称。视觉/格式通过；仓库未记录原始创作来源，不能仅凭图像确认授权。深色和 tinted 使用同一张图，属于展示优化项。 |
| 平台范围 | 声明 iPhone、iPad、macOS、visionOS。最低版本均为 26.5；需决定首发范围和最低系统版本。没有 visionOS 专用图标资源，未验证 visionOS 构建及运行。 |
| 设备适配 | 本轮验证 iPad A16 / iPadOS 26.5 的难度弹窗、棋盘横竖屏，无明显遮挡。此前验证 iPhone 17 Pro 模拟器中英文界面。尚未完成小屏、大字体、iPad 分屏、iPhone 横屏及真机全流程验收。 |
| 构建 | 基线 iOS Release 无签名 Archive 成功；清理后另做 iOS Simulator Debug 和 macOS Release clean build。无签名产物不是可提交的商店包。 |
| 签名 | 配置 Automatic signing 和开发团队，标识 sc2l.nookchess，版本 1.0(1)。本机只发现 Apple Development 和 Developer ID Application，有效的商店分发签名身份未发现；未检查云端证书、会员状态或 App Store Connect 应用记录。Developer ID 用于 Mac 商店外分发。 |
| 隐私清单 | 源码使用 UserDefaults 保存主题、棋子、难度和积分，仓库及基线归档均无 PrivacyInfo.xcprivacy。应声明实际使用的 required-reason APIs，并审计引擎依赖；离线应用也不能省略这一步。隐私政策页面及应用内入口尚未准备。 |
| Stockfish 与依赖 | README 记录 GPL-3.0 和固定 revision，但应用包缺少相应许可/源码获取说明，仓库没有整体应用许可证。引擎通过库链接进入应用，不能把 wrapper 的 MIT 当成 Stockfish 的授权。应核对完整对应源码、构建方式、整体分发许可与 App Store 条款兼容性，再决定是否沿用当前引擎方案。ChessKitEngine 的 target 还包含 lc0/Eigen 等代码，需按最终链接产物整理完整第三方声明。 |
| 警告 | SimpleChessEngine 存在 actor 隔离编译警告，Swift 6 下会成为错误；当前 Swift 5 构建可过，正式发布前应修正。基线 Neo PNG 位深警告对应的素材已随本次清理删除。 |

## 本次已处理的棋子素材

原有 77 套：Chess.com 37 套、Lichess 38 套、标为自绘 2 套。

- 删除 Chess.com 37 套：项目未提供独立再分发授权。
- Lichess 只保留 Spatial/Fantasy/Celtic（MIT）、Chessnut（Apache 2.0）、RhosGFX（CC0）。其他款式因非商业限制、授权不明或尚未完成许可处理暂不发布，不等于认定全部侵权。
- 删除 Geometric：打包脚本表明它由 Cburnett 改色、加粗得到，原“自绘 SVG”标注不准确。
- 保留 Clay 3D：项目标记为原创；生成或创作过程未在本轮独立验证。
- 共保留 6 套、72 张 PNG，默认 Spatial。旧偏好若指向被移除的款式，现有启动逻辑会回退到默认款式。
- 删除资源本体并限制打包脚本的导入范围。作者、许可全文和转换说明随 PieceArtworkLicenses.txt 打包。

## 下一步顺序

1. 处理 Stockfish/整体应用分发许可和第三方声明。
2. 补 PrivacyInfo.xcprivacy，修正 actor 隔离警告，确定最低系统及首发平台范围。
3. 完成正式签名归档、导出校验和真机验证。
4. 再准备商店介绍、隐私政策/支持页面、截图和 TestFlight。

## 官方资料

- Lichess 素材许可清单：https://github.com/lichess-org/lila/blob/master/COPYING.md
- Maurizio Monge 棋子许可：https://github.com/maurimo/chess-art/blob/main/LICENSE
- Chessnut 许可：https://github.com/LexLuengas/chessnut-pieces/blob/master/LICENSE.txt
- Chess.com 使用条款：https://www.chess.com/legal/user-agreement
- Stockfish 分发要求：https://stockfishchess.org/about/
- GPL 链接说明：https://www.gnu.org/licenses/gpl-faq.en.html#GPLStaticVsDynamic
- Apple UserDefaults 声明要求：https://developer.apple.com/documentation/foundation/userdefaults
- Apple 证书类型：https://developer.apple.com/help/account/create-certificates/certificates-overview

## 后续原创棋子

按用户要求新增原创 Nook Flat 平面几何棋子，并设为默认。现有 7 套、84 张 PNG。原始 SVG 保留在 artwork/nook-flat，没有复用第三方棋子路径；导入脚本包含对应渲染步骤。
