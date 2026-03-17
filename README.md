# Skin Weight Locker（3ds Max）

这是一个 **3ds Max MaxScript 插件**，用于在 `Skin` 编辑流程中锁定选中骨骼权重，防止在编辑其它骨骼时误改已锁定骨骼的权重。

## 功能

- 选择带 `Skin` 修改器的模型作为目标。
- 在场景中选择骨骼（或在 Skin 面板选择当前骨骼）。
- 一键记录并锁定这些骨骼在所有顶点上的权重快照。
- 开启“自动持续约束”后，每 250ms 自动校正，确保锁定骨骼权重不变。
- 支持手动执行一次约束与清除锁定。

## 安装

1. 将 `SkinWeightLocker.ms` 拷贝到 3ds Max 脚本目录（例如 `scripts/startup`），重启 3ds Max；
2. 或者通过 `Scripting > Run Script...` 手动运行。

运行后可在 `Customize > Customize User Interface` 中找到：

- Category: `RiggingTools`
- Action: `SkinWeightLocker`

可将其拖到工具栏或绑定快捷键。

## 使用步骤

1. 选择一个带 `Skin` 的模型；
2. 点击 **设置当前目标模型**；
3. 开启 Skin 编辑（如 `Edit Envelopes`/`Paint Weights`）；
4. 选择需要锁定的骨骼；
5. 点击 **锁定当前选中骨骼权重**；
6. 建议勾选 **自动持续约束**。

## 实现说明

- 脚本会记录“锁定骨骼”在每个顶点上的权重快照；
- 在约束执行时：
  - 锁定骨骼恢复为快照权重；
  - 非锁定骨骼按比例缩放，保持相对分布并保证总权重为 1。

## 注意事项

- 该工具仅作用于当前设置的 `Skin` 修改器。
- 大模型高频编辑时可适当关闭自动模式，改用“手动执行一次约束”以提高交互流畅性。
