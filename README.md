# Nook Chess / 自己下国际象棋

SwiftUI 单机国际象棋练习应用。ChessKit 负责棋规，轻量引擎和 Stockfish 17 提供不同难度的电脑对手，Stockfish 同时负责提示。

## 构建

首次构建前执行：

```sh
bash scripts/download_stockfish_networks.sh
```

随后用 Xcode 打开 `ichess/ichess.xcodeproj`，运行 `ichess` scheme。
两份 Stockfish NNUE 文件约 75 MiB，下载后校验 SHA-256，由 Xcode 随应用打包；不提交到 Git，使用提示时无需联网。

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
