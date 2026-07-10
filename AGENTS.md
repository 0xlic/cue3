# AGENTS.md

本文档定义 AI agent 和自动化工具在本仓库中的工作约束。

## 项目结构

- `Sources/` 存放 Mac 应用源码。
- `Tests/` 存放 Mac 应用测试。
- `image/icon.png` 是最高分辨率的源图标，只用于生成其他尺寸图片，不直接作为应用或文档展示资源引用。
- `image/icon-readme.png` 是 README 专用的低分辨率展示图。
- `Assets.xcassets/` 存放 Mac 应用图标资源。
- `Cue3.xcodeproj/` 存放 Xcode 工程配置和 App 打包入口。
- `.github/workflows/` 存放 GitHub Actions workflow 文件。

## 文档规则

- Markdown 文档必须使用中文编写。
- 路径、命令、版本号、tag、代码标识符、配置字段等可以保留英文。
- 如果后续补充仓库文档，产品相关文档放在 `docs/product/`。
- 如果后续补充仓库文档，架构和数据模型文档放在 `docs/architecture/`。
- 如果后续补充仓库文档，技术决策放在 `docs/decisions/`。
- 如果后续补充仓库文档，版本与发布文档放在 `docs/releases/`。
- 不要把未支持平台的实现细节写进公共文档。

## 开发命令

稳定命令：

- Debug 构建：`xcodebuild -project Cue3.xcodeproj -scheme Cue3 -configuration Debug build`
- XCTest：`xcodebuild -project Cue3.xcodeproj -scheme Cue3 -configuration Debug -destination "platform=macOS" test`
- Release 构建：`xcodebuild -project Cue3.xcodeproj -scheme Cue3 -configuration Release build`
- CI 无签名构建：`xcodebuild -project Cue3.xcodeproj -scheme Cue3 -configuration Release build CODE_SIGNING_ALLOWED=NO`

## 测试

当前 XCTest 已接入 `Cue3.xcodeproj` 的 `Cue3Tests` target 和共享 scheme，应使用 `xcodebuild test` 运行，避免与 App 实际构建链路分离。

## CI

GitHub Actions 文件位于 `.github/workflows/`。

当前 workflow 分工如下：

- `ci.yml`：用于 `pull_request` 和 `main` 分支提交校验，执行 `xcodebuild` Debug 构建、XCTest 和 Release 构建。
- `release.yml`：用于发布打包，仅在推送 `vX.Y.Z` tag 时触发。

发布 workflow 使用标准语义版本 tag：

- `vX.Y.Z`：Mac 应用发布。

应用版本使用标准 `X.Y.Z` 语义版本号，对外发布 tag 使用 `vX.Y.Z`。

## 发版流程

- 发版前先确保本地通过 `xcodebuild -project Cue3.xcodeproj -scheme Cue3 -configuration Debug build` 和 `xcodebuild -project Cue3.xcodeproj -scheme Cue3 -configuration Release build`。
- 使用小写 `v` 前缀创建并推送 tag，例如 `v0.1.0`。
- `release.yml` 会在 `macos-26` runner 上使用 Xcode 26.5 自动执行归档和打包，不需要手工上传产物。
- workflow 会把 tag 中的 `X.Y.Z` 写入 `MARKETING_VERSION`，把 GitHub Actions 运行号写入 `CURRENT_PROJECT_VERSION`。
- 发布 workflow 在五项 Apple Secrets 全部存在时使用 Developer ID 签名、公证并 stapling；完全未配置时回退为 ad-hoc 签名，部分配置会阻止发布。
- 签名与公证配置见 `docs/releases/signing-and-notarization.md`。
- macOS zip 包命名格式为 `Cue3-vX.Y.Z-macOS.zip`。
- workflow 会同时生成 `Cue3-vX.Y.Z-macOS.sha256.txt` 校验文件，并上传到 GitHub Release。
- ad-hoc 发布时用户首次打开可能需要按 README 指引处理 Gatekeeper；Developer ID 公证包应直接通过 Gatekeeper 验证。

## 构建原则

- 本仓库是纯 macOS 应用，CI、发布和日常构建应以 `Cue3.xcodeproj` 为唯一主路径。
- 不把 `swift build`、`swift test` 作为主要验收标准，避免 SwiftPM 构建结果与 Xcode App 构建结果不一致。

## 变更约束

- 修改代码前先阅读相关 README 和仓库内现有说明文档。
- 文档更新应贴近它描述的功能或架构变更。
- 优先保持变更小而聚焦。
- 只调整仓库结构时，不要实现产品行为。

## 禁止事项
- 不要提交生成的构建产物或依赖目录。
