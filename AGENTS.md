# AGENTS.md — Nook Chess 项目说明（给 AI 编码助手）

Nook Chess（中文名「自己下国际象棋」）是作者**个人自用**的 SwiftUI 国际象棋练习 App，面向新手，不上架。一个 Xcode target 同时出 iOS / iPadOS / macOS。仓库是**公开的**，这一点决定了下面的素材规则。

## 目录

- `ichess/ichess.xcodeproj`：Xcode 工程，scheme `ichess`。使用 file-system-synchronized groups，`ichess/ichess/` 下新增的 `.swift` 文件会自动加入工程，不用改 pbxproj。
- `ichess/ichess/`：全部源码和资源（`Localizable.xcstrings`、`PieceSets/`、`AppIcon.icon`）。
- `scripts/`：`download_stockfish_networks.sh`（首次构建前必须跑）、`release_mac.sh`（macOS 打包发布）、`pack_piece_sets.mjs`（SVG 棋子转 PNG 并写 catalog）。
- `artwork/`：原创棋子 SVG 源文件（`nook-*`）、生成器 `piece-lab/`、App 图标源文件 `app-icon/`。
- `docs/`：发布前检查、Stockfish 许可排查等记录。

## 构建

```sh
bash scripts/download_stockfish_networks.sh   # 下载两份 NNUE（约 75 MiB，gitignore）
xcodebuild -project ichess/ichess.xcodeproj -scheme ichess -configuration Release \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ichess/ichess.xcodeproj -scheme ichess -configuration Release \
  -destination 'platform=macOS' -allowProvisioningUpdates build
```

- 最低系统：macOS 14.0，iOS 26.5。macOS 版是 x86_64 + arm64 通用二进制（作者有一台旧 Intel Mac）。
- 依赖：ChessKit（chesskit-swift，棋规）和 ChessKitEngine（Stockfish 17，从源码编译进 App）。
- 已知且可忽略的警告：`ChessGameStore.swift` 里调用 `SimpleChessEngine.chooseMove` 的 Swift 6 actor 隔离警告。

## 素材与许可（重要）

- **Chess.com 棋子只能留在本机**：37 套 Chess.com 棋子 PNG 和 `ichess/ichess/PieceSets/catalog.local.json` 被 `.gitignore` 忽略。它们没有再分发授权，**绝不能 `git add`、取消忽略、上传或放进给别人的安装包**。`PieceSet.swift` 会在本地文件存在时把它们追加到棋子列表；没有这些文件时 App 照常运行。
- 仓库里的棋子都可以分发：原创的 Nook Flat 和五套 `nook_*`（SVG 源在 `artwork/`），以及许可明确的 Lichess 款式。许可说明在 `ichess/ichess/PieceArtworkLicenses.txt`。
- Stockfish 是 GPL-3.0，链接进了 App。把 App 发给别人就算分发，要附上源码地址（公开版打包脚本会自动附说明）。详细的许可排查（链接方式、App Store 兼容性、可选路线）见 `docs/stockfish-distribution-review.md`。仓库目前没有 LICENSE 文件，要不要按 GPL-3.0 补上，由作者决定。

## 发布 macOS（`scripts/release_mac.sh`）

```sh
scripts/release_mac.sh                      # public：干净 worktree 编 main，断言不含 Chess.com 素材，可以分享
scripts/release_mac.sh --variant personal   # personal：用当前工作区编，带 Chess.com 棋子，只给作者自己的 Mac
```

- 流程：通用架构 Archive → Developer ID 导出（团队 `Z852QM89N4`）→ 校验（lipo、codesign、hardened runtime、minos）→ `notarytool` 公证 → staple → zip。
- 最终 zip 输出到 `~/Downloads`（环境变量 `OUTPUT_DIR` 可改），中间产物在 `dist/`（gitignore）。
- 公证凭证存在本机钥匙串，profile 名 `nook-notary`（环境变量 `NOTARY_PROFILE` 可改）。缺凭证时脚本签完名就停，并打印 `xcrun notarytool store-credentials` 命令。
- personal 版只能装到作者自己的机器。作者本机 `/Applications/Nook Chess.app` 装的就是 personal 版。
- iOS 真机：用 `-destination 'id=<UDID>' -allowProvisioningUpdates` 编译，再 `xcrun devicectl device install app` 安装（开发证书签名，不需要公证）。

## 架构速览

- `ChessGameStore`：唯一的游戏状态（`@MainActor ObservableObject`），负责走子、悔棋、模式、提示、试走、演示、存档。玩家固定执白。
- 模式 `GameMode`：练习（悔棋、提示、风险标记、试走、走后点评、自动提醒、对方威胁、候选对比、逐步演示）/ 对战（无辅助，计积分）。「显示胜率」是独立开关，两种模式都能开，对战开着照常计分。
- 引擎：`StockfishHintEngine` 是串行化的 actor，所有搜索（电脑走棋、提示、分析、MultiPV）都经过它；每次搜索前先 `isready` 清掉上一次的残留输出，每次请求设置 MultiPV，并有前台/后台优先级。`EngineAnalysis` 解析 `info` 行，分数以**轮到走的一方**为视角。
- 规则分析（不依赖引擎）：`ThreatAnalyzer`（静态交换 SEE、挂子、危险落点）、`TacticsDetector`（捉双、牵制、串击、将杀威胁）、`CoachExplainer`（排序后的提醒句子）、`MoveWhy`（一步棋的理由）。
- 判定：`MoveClassifier` 用 Lichess 胜率公式，胜率下降 7 / 13 / 20 分别为不够精确 / 失误 / 大漏着；准确率用 Lichess 的单步公式。
- 对局记录：`MoveRecord` / `GameRecord`；`GameArchive*` 每盘一个 JSON（Application Support/nookchess/games/，最多 200 盘）；`PostGameAnalyzer` 在后台补全分析。
- 界面：`ContentView`（顶部按钮、齿轮菜单、页面切换）、`ChessBoardView`（棋盘、箭头、坐标、走子动画）、`CoachPanelView`、`ReviewView`（铺满窗口，宽屏两栏）、`StaticBoardView`、`WinChanceViews`、`LineDemo*`。

## 约定与坑

- **本地化**：代码里的字符串一律 `String(localized: "...", bundle: .localized)`（App 内可切换语言，见 `LanguageStore`）；SwiftUI 的 `Text("key")` 依赖根视图的 `.environment(\.locale, ...)`。macOS 的 sheet 不继承这个 locale，所以页面尽量在窗口内切换，不用 sheet。
- **`Localizable.xcstrings` 格式**：必须能被 `json.dumps(d, ensure_ascii=False, indent=2) + "\n"` 原样写回；新 key 追加在末尾，不要重新排序；每个新 key 都要有 zh-Hans 翻译。
- **macOS 按钮**：自己画了胶囊背景的 `Button` 必须加 `.buttonStyle(.plain)`，否则 macOS 会再叠一层系统灰底。
- **NNUE 路径**：App 名带空格（`Nook Chess.app`），ChessKitEngine 用 `URL.path()` 传路径会把空格编码成 `%20`，Stockfish 找不到文件就直接 `exit()`。`StockfishHintEngine` 在引擎就绪后用未编码路径重设 `EvalFile`，这段不要删。
- **调试预设**：DEBUG 构建支持 `-nookchess.debugPreset <名字>`（如 `keypoint`、`threat`、`demo1`、`review-history`、`multipv-probe`）和 `-nookchess.debugSheet <名字>`，用来直接进入某个界面状态截图。只放在 `#if DEBUG` 里。
- **测试**：没有 XCTest target。纯逻辑用临时 SwiftPM 包测试：依赖本地 chesskit-swift checkout（在 DerivedData 的 `SourcePackages/checkouts/` 下），把要测的源文件拷进去或软链接。界面用模拟器和 `xcrun simctl io <sim> screenshot` 截图检查；macOS 窗口可以用 `screencapture -l <windowID>` 截图。
- 代码风格：注释用中文，简短、少写；沿用周围代码的命名和 SwiftUI 写法。
- Git：在分支上开发，PR 用 squash 合并到 `main`；提交信息用英文，PR 标题和描述用中文。
