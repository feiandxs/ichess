# ichess

SwiftUI 单机国际象棋练习应用。ChessKit 负责棋规，自带轻量引擎负责电脑对手，Stockfish 17 负责提示。

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

## 第三方组件

- [ChessKit](https://github.com/chesskit-app/chesskit-swift)：MIT。
- [ChessKitEngine](https://github.com/chesskit-app/chesskit-engine)：MIT；固定源码 revision，见 Xcode 项目。
- [Stockfish](https://github.com/chesskit-app/Stockfish/tree/23f320bac6b554f6470d51f10b96613a7cd7b03d)：GPL-3.0；通过 ChessKitEngine 编译进应用。
- NNUE 文件来源：[Stockfish 测试服务器](https://tests.stockfishchess.org/)，版本与 SHA-256 固定在下载脚本中。

分发包含 Stockfish 的构建时，须遵守其 GPL-3.0 许可证；包装库的 MIT 许可证不替代引擎许可证。
