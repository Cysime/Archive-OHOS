# Archive for HarmonyOS NEXT

[Aerunox/Archive](https://github.com/Aerunox/Archive) 的 HarmonyOS NEXT 原生 ArkTS / ArkUI（Stage 模型）移植版。

## 目录隔离与上游同步

本工程完全位于 `harmonyos/` 目录内，**不修改上游 Android 项目的任何文件**（`bundleName: com.archive.app.ohos`，避免与原版冲突）。
同步上游更新时执行：

```bash
git fetch upstream
git merge upstream/main
```

详见 [UPSTREAM_SYNC.md](UPSTREAM_SYNC.md)。

## 本地构建与检查

```bash
export TOOL_HOME="$HOME/Library/Huawei/command-line-tools"
export DEVECO_SDK_HOME="$TOOL_HOME/sdk"
export PATH="$TOOL_HOME/bin:$PATH"

cd harmonyos
ohpm install
hvigorw --mode module -p module=entry@default assembleHap
codelinter .
```

## 开源协议

继承上游项目 [GNU GPL-3.0](../LICENSE)。
