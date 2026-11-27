# 上游同步记录（Upstream Sync Tracker）

- **上游仓库**：`https://github.com/Aerunox/Archive.git`（remote: `upstream`）
- **Fork 仓库**：`https://github.com/Cysime/Archive-OHOS.git`（remote: `origin`）
- **移植分支**：`ohos`（Fork 仓库默认分支）
- **当前对齐上游基线**：`v1.0.4`（commit `76cf29b`）

## 移植进度矩阵

| Phase | 范围 | 状态 |
|---|---|---|
| Phase 1 | 工程脚手架、设计系统（PurrColors + App* + 40 Lucide SVG）、Core 基础设施（ApiClient/rcp、CloudflareManager/ArkWeb、RDB v1、AssetStore/Session/Settings、ImageLoader、HtmlParser、AgeGate + 4-Tab + Navigation 根壳） | ✅ 已完成（HAP 构建 + CodeLinter 0 Error + 7 项核心单测通过） |
| Phase 2 | 内容浏览（首页/发现 96k 创作者/作者详情/帖子详情/收藏多账号与离线全文归档/历史/屏蔽管理） | ✅ 已完成（HAP 构建 0 Error + CodeLinter 0 Error + 8 项单测通过） |
| Phase 3 | 媒体查看器（缩放/原图回退）、AVPlayer HLS/MP4/音频播放、下载中心（Range 续传/并发 1-5/通知/导出/下载规则） | ✅ 已完成（HAP 构建 0 Error + CodeLinter 0 Error + 9 项单测通过） |
| Phase 4 | 全站搜索（含哈希反查）、AI 翻译与识图（多供应商/哨兵契约）、CoreVisionKit 端上 OCR | ✅ 已完成（HAP 构建 0 Error + CodeLinter 0 Error + 11 项单测通过） |
| Phase 5 | 订阅与通知中心、JSON v1 备份恢复、12 语言 + RTL、设置/存储/关于与更新检查（指向 `Cysime/Archive-OHOS`） | ✅ 已完成（全量 15 路由无占位 + HAP 构建 0 Error + CodeLinter 0 Error + 12 项单测通过） |

## 上游同步操作流

```bash
git fetch upstream
git log --oneline 76cf29b..upstream/main
git merge upstream/main
```

如有新增 Lucide 图标或应用图标变更，可重新执行：

```bash
python3 harmonyos/tools/sync_icons.py
```
