# Nook Chess / 自己下国际象棋

SwiftUI 单机国际象棋练习应用。ChessKit 负责棋规，轻量引擎和 Stockfish 17 提供不同难度的电脑对手，Stockfish 同时负责提示。

支持英文和简体中文，跟随系统的语言偏好，未支持的语言回退到英文。界面文案集中在 `ichess/ichess/Localizable.xcstrings`，应用名称分别为 Nook Chess 和自己下国际象棋。

## 构建

首次构建前执行：

```sh
bash scripts/download_stockfish_networks.sh
```

随后用 Xcode 打开 `ichess/ichess.xcodeproj`，运行 `ichess` scheme。
两份 Stockfish NNUE 文件约 75 MiB，下载后校验 SHA-256，由 Xcode 随应用打包；不提交到 Git，使用提示时无需联网。

## 发布（macOS）

`scripts/release_mac.sh` 一条命令完成通用二进制（x86_64 + arm64）归档、Developer ID 签名、公证、装订并打包为 zip，产物位于 `dist/`（已被 .gitignore 忽略）。

```sh
scripts/release_mac.sh                       # public：默认，从干净的 main 构建，可分享
scripts/release_mac.sh --variant public --ref <分支或标签>
scripts/release_mac.sh --variant personal    # personal：从当前工作目录构建，含本地 Chess.com 素材
scripts/release_mac.sh --skip-notarize       # 只签名不公证
```

- public：通过临时 `git worktree` 构建指定 ref，从本机复制被忽略的 `.nnue`（缺失时报错，先执行 `scripts/download_stockfish_networks.sh`），并断言应用包内没有 Chess.com 素材或 `catalog.local.json`。输出 `dist/NookChess-<版本>-<构建号>.zip`，内含应用与中英文 GPL-3.0 / 第三方说明 README。
- personal：包含本地 Chess.com 素材，仅供自己的机器使用，**绝不可分享、上传或发布**。输出 `dist/NookChess-<版本>-<构建号>-personal.zip`。

首次公证前需一次性保存凭据（使用 appleid.apple.com 生成的 App 专用密码）：

```sh
xcrun notarytool store-credentials nook-notary --apple-id <邮箱> --team-id Z852QM89N4
```

可用环境变量 `NOTARY_PROFILE` 指定其他 profile 名。凭据缺失时脚本在签名后停止，已签名未公证的应用留在 `dist/<variant>/export/`。

## 提示

通过 [ChessKitEngine](https://github.com/chesskit-app/chesskit-engine) 调用 Stockfish 17，固定最大深度 15、搜索时间上限 1000 ms、单线程，不随玩家积分降低强度。引擎初始化另需时间。提示显示推荐走法的起点和终点，不提供送子警告或文字解释。

分析期间仍可操作棋盘；局面变化后丢弃旧结果，同一时间只运行一次提示分析。

## 难度

首次启动选择水平，之后通过棋盘上方的“难度”修改。开局前立即生效；对局中修改只影响下一盘。当前对局难度随存档恢复，偏好单独保存。

| 档位 | 电脑对手 |
| --- | --- |
| 新手 | 轻量引擎，1 层搜索，随机窗口 90 |
| 入门 | 轻量引擎，2 层搜索，随机窗口 35 |
| 熟练 | Stockfish，UCI_Elo 1400 |
| 进阶 | Stockfish，UCI_Elo 1800 |
| 高手 | Stockfish，UCI_Elo 2200 |
| 大师挑战 | Stockfish，UCI_Elo 2600 |

Stockfish 对手使用内置限强参数，最大深度 15、搜索时间 1000 ms。参数不是 FIDE 真人等级分；低档轻量引擎没有校准 Elo。练习积分只记录成长，不控制难度。提示始终关闭限强，提示和对手请求串行执行。

## 第三方组件

- [ChessKit](https://github.com/chesskit-app/chesskit-swift)：MIT。
- [ChessKitEngine](https://github.com/chesskit-app/chesskit-engine)：MIT；固定源码 revision，见 Xcode 项目。
- [Stockfish](https://github.com/chesskit-app/Stockfish/tree/23f320bac6b554f6470d51f10b96613a7cd7b03d)：GPL-3.0；通过 ChessKitEngine 编译进应用。
- NNUE 文件来源：[Stockfish 测试服务器](https://tests.stockfishchess.org/)，版本与 SHA-256 固定在下载脚本中。

分发包含 Stockfish 的构建时，须遵守其 GPL-3.0 许可证；包装库的 MIT 许可证不替代引擎许可证。

## 棋子素材

棋子库提供原创 Nook Flat（默认）、圆润几何 Soft Geometry、锐角切面 Crisp Facets、厚重积木 Bold Blocks、单线轮廓 Monoline、圆徽章 Badge Discs、Clay 3D，以及 Spatial、RhosGFX、Celtic、Chessnut、Fantasy 共 12 套。原创矢量源文件保存在 `artwork/nook-flat/` 与 `artwork/nook-{soft,crisp,block,mono,badge}/`，后五套的生成脚本在 `artwork/piece-lab/`；`node scripts/pack_piece_sets.mjs --originals-only` 可重新栅格化原创款式并合并进 catalog.json。第三方素材的作者、许可与 SVG 转 PNG 的修改说明位于随应用打包的 `PieceArtworkLicenses.txt`。

已移除未取得独立再分发授权的 Chess.com 素材，以及带非商业限制、授权不明或尚未完成许可处理的 Lichess 素材。Geometric 实际由 Cburnett 改色生成，不作为原创保留。导入脚本仅允许已核实的保留款式。本地开发时可能另有未入库的 Chess.com 素材（被 .gitignore 忽略、只放在本机 `catalog.local.json`），它们不属于仓库，也不随发布版本提供。
