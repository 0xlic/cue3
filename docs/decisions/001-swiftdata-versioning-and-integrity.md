# 001：SwiftData 版本化与完整性策略

## 状态

已采纳。

## 背景

Cue3 的 `CueRecord`、`CueItemRecord` 和 `AppStateRecord` 已经存在公开发布版本的数据。`CueItemRecord` 当前通过 `cueID` 与 Cue 建立逻辑关联，删除与修复由 `CueStore` 统一处理。

直接把现有字段改为 SwiftData relationship 会改变持久化 schema，并需要在缺少真实历史脏数据样本的情况下执行迁移。当前数据只保留 24 小时，业务也没有跨上下文写入，因此这种迁移的收益不足以覆盖风险。

## 决策

- 当前 schema 固定为 `Cue3SchemaV1`，版本号为 `1.0.0`。
- `Cue3MigrationPlan` 是所有 App 和测试容器的统一迁移入口。
- 每个版本的模型定义嵌套在对应 `VersionedSchema` 中，避免未来修改新版本模型时意外改变旧版本定义。
- V1 继续使用 `cueID` 逻辑关联，不在本次变更中引入 relationship。
- `CueStore` 启动修复会删除找不到所属 Cue 的孤儿条目、收敛重复主状态记录，并保证最多只有一个 current Cue。
- 后续模型变化必须新增 `Cue3SchemaV2` 等新版本和明确的 `MigrationStage`，不得直接修改 V1 的持久化字段。

## 影响

优点：

- 现有未显式版本化的 `1.0.0` 存储可直接打开。
- 数据修复行为集中且有 XCTest 覆盖。
- 后续 schema 演进有稳定入口。

限制：

- 数据库层仍不提供外键和级联删除约束。
- 新增其他写入入口时，必须继续通过 `CueStore` 或补充等价的完整性校验。
- 如果未来出现跨设备同步、导入或复杂查询需求，应重新评估 relationship，并通过新 schema 版本迁移。
