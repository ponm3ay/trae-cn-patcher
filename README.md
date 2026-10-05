# trae-cn-patcher

Trae CN IDE 微插件：一键屏蔽「工作区位于安装文件夹，可能被误删」的顶部告警横幅，并同步 IDE 完整性校验（避免弹「安装似乎损坏」提示）。

零依赖，纯 PowerShell，不需要管理员权限。

## 为什么需要它

Trae（基于 VS Code）检测到工作区目录位于安装目录内时，会在窗口顶部显示一条无法关闭的告警横幅（`appRootWarning.banner`），该横幅没有任何官方开关。手动改掉核心文件后，IDE 的完整性校验（`product.json` 中的 SHA-256 校验表）又会判定安装损坏并弹出「安装似乎损坏」提示。

本插件把这两件事一次做完：

1. 按正则定位并中和横幅调用（替换为 `void 0`，不破坏语法）
2. 修改前自动备份原文件为 `.bak`
3. 重算被改文件的 SHA-256（base64 去尾 `=`）并回写 `product.json` 校验表，让完整性校验保持通过

## 使用

双击 `apply.cmd`（或命令行）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\trae-patcher.ps1 apply
```

安装目录自动探测（见 `manifest.json` 的 `installDirs`），探测不到时显式指定：

```powershell
.\scripts\trae-patcher.ps1 apply -InstallDir "D:\Trae CN"
```

三个动作：

| 命令 | 作用 |
|------|------|
| `apply`   | 打补丁 + 备份 + 同步校验（幂等，重复执行安全） |
| `status`  | 查看每个补丁的状态与校验是否同步 |
| `restore` | 从 `.bak` 还原 + 同步校验（彻底回到原版） |

执行后重启 Trae（或重新加载窗口）生效。

## 文件结构

```
trae-cn-patcher/
├── manifest.json          # 补丁定义：目标文件、匹配正则、替换内容、校验同步配置
├── apply.cmd / status.cmd / restore.cmd   # 双击入口
└── scripts/
    └── trae-patcher.ps1   # 核心脚本
```

## IDE 升级后

IDE 版本更新会覆盖被修改的文件（横幅和「安装损坏」提示都会复发）。重新执行一次 `apply` 即可。若新版本压缩混淆导致匹配正则失效，`apply` 会安全地跳过并提示，不会改坏文件——此时需要按新版本的产物更新 `manifest.json` 中的正则。

## 添加新补丁

在 `manifest.json` 的 `patches` 数组里追加一条即可，脚本会自动循环处理所有条目：

```json
{
  "id": "another-patch",
  "description": "...",
  "target": "out/vs/xxx.js",
  "matchRegex": "...",
  "replace": "...",
  "expectedOccurrences": 1,
  "checksumSync": { "productJson": "product.json", "checksumKey": "out/vs/xxx.js 对应校验键" }
}
```

注意：正则必须足够精确，`expectedOccurrences` 不匹配时脚本会中止操作以策安全。

## 免责声明

本插件直接修改 IDE 安装目录内的文件（修改前自动备份），仅限本人自担风险使用；与本插件相关的修改不属于官方支持范围，IDE 升级或重装后请自行重新 apply 或改回官方版本。
