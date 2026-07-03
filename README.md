# Cue3

<p align="center">
  <img src="image/icon-readme.png" alt="Cue3 图标" width="160">
</p>

<p align="center">一个轻量的 macOS AI 对话注意力中转站。</p>

## 简介

当 AI 一次输出很长内容时，后续很难继续围绕某一句、某一段或某个观点展开。

Cue3 用来临时保存这些值得继续追问的片段，并附上你的批注，让下一轮对话更聚焦。

它不是笔记本、收藏夹或知识库，而是一个只服务当前注意力的轻量工具。

## 特点

- `macOS` 原生应用，基于 `SwiftUI`、`AppKit` 和 `SwiftData`
- 菜单栏常驻，围绕当前正在追问的 `Cue` 快速切换
- 只强调最近 `3` 个 Cue，避免注意力被过度分散
- 历史 Cue 自动保留 `24` 小时，适合临时上下文管理
- 本地优先，不引入额外服务依赖，便于自行构建和修改
- 仓库结构简洁，便于自行构建、修改和持续迭代

## 快速开始

开发环境：

- `macOS 14+`
- `Xcode 15.4+`
- `Swift 5.10`

使用 Xcode 打开 `Cue3.xcodeproj`，选择 `Cue3` scheme 运行。

如果涉及系统级捕获、全局快捷键和辅助功能权限，请授权 Xcode 构建出的 `Cue3.app`，不要授权 `.build/debug/Cue3` 裸二进制。

常用命令：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Cue3.xcodeproj -scheme Cue3 -configuration Debug build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Cue3.xcodeproj -scheme Cue3 -configuration Release build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Cue3.xcodeproj -scheme Cue3 -configuration Release build CODE_SIGNING_ALLOWED=NO
```

本仓库的 CI 和发布都以 `Cue3.xcodeproj` 为准，不把 `swift build` / `swift test` 作为主要验收路径。

## 下载与打开

如果你是从 GitHub Release 下载应用，请先将 `Cue3.app` 拖到 `Applications`。

当前公开发布包可能未经过 Apple Developer 签名与公证，macOS Gatekeeper 可能会阻止直接打开。遇到这种情况时，可以按下面步骤处理：

1. 在 `Applications` 中找到 `Cue3.app`
2. 右键应用，选择 `打开`
3. 在系统弹窗中再次点击 `打开`

如果仍然被拦截，可以到 `系统设置 > 隐私与安全性`，在安全提示区域手动允许打开 `Cue3`。

首次使用涉及选中文本捕获、全局快捷键等能力时，系统还可能要求你授予辅助功能等权限。

## 仓库结构

```text
.
├── image/            # 源图标和 README 展示图
├── Sources/          # 应用入口、业务规则、存储和界面
├── Tests/            # XCTest 测试
├── Assets.xcassets/  # 应用图标资源
├── Cue3.xcodeproj/
├── AGENTS.md         # 仓库协作约束
├── LICENSE           # MIT 许可证
├── Package.swift
└── .github/workflows/
```

## 开源说明

- 当前仓库已经具备典型开源项目的基础结构：源码、测试、CI workflow 和可复用图标资源
- 当前仓库采用 `MIT License`
- 许可证全文见根目录 `LICENSE`
