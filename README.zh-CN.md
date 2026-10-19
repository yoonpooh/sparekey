# Sparekey

让 AI 代理解锁您已登录的 Mac 会话，并在任务结束后重新锁定的 macOS 命令行工具。

[![MIT 许可证](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · 简体中文 · [Español](README.es.md)

![Mac 显示器上的 Sparekey 遮罩](docs/assets/cover.png)

## 主要功能

- 使用登录钥匙串中的密码解锁您自己的已登录会话。
- 验证控制台账户和安全密码框，每次尝试最多提交一次密码。
- 默认遮住实体显示器，代理仍可操作和截取下方的应用画面。
- 最多保持显示器唤醒 60 分钟，重新锁定或通过认证接管后结束保持。
- 提供任务重新锁定令牌、Codex 和 Claude Code 技能，以及 JSON 输出。

工具依赖锁屏界面的 Accessibility 布局。软件包的 macOS 13 及以上部署目标不代表已验证所有系统版本的实际兼容性。

## 环境要求

- macOS 13 或更高版本，且已登录您自己的桌面会话。
- 源码构建需要包含 Swift 5.9 或更高版本的 Xcode Command Line Tools。Homebrew formula 也从源码构建。
- 已解锁 Mac 上的本地交互式终端，用于 setup 和 uninstall。使用普通用户运行，不要使用 `sudo`。
- 已安装 helper 的辅助功能权限，以及登录钥匙串访问权限。
- 使用 Homebrew 安装方式时需要 Homebrew。

不需要 Apple Developer 账户。无法解锁启动时的 FileVault、已退出登录的会话或其他账户，也不提供远程访问功能。

## 安装

```sh
brew install yoonpooh/tap/sparekey
```

也可以从源码构建：

```sh
git clone https://github.com/yoonpooh/sparekey.git
cd sparekey
swift build -c release
.build/release/sparekey setup --skill codex
```

源码安装后的 `PATH` 设置见[英文安装说明](README.md#installation)。
仓库中的 formula 是带有发布校验和占位符的模板，不要直接将该文件作为发布版 formula 安装。

## 快速开始与使用

Homebrew 安装后，在您自己的 Mac 本地终端中设置：

```sh
sparekey setup --skill codex
```

也可选择 `--skill claude`、`--skill claude,codex` 或 `--no-skill`。省略选择选项时会交互询问。
setup 创建或复用本地签名身份，为 helper 签名，按需保存登录密码，并启动用户级 LaunchAgent。
密码只在终端隐藏提示中输入。macOS 询问签名密钥使用权限时，选择 **Allow**，不要选择 **Always Allow**。按提示启用 helper 的辅助功能权限。

```sh
sparekey doctor
sparekey status --json
```

安装或更新技能后，开启新的代理会话。技能会指导状态检查、probe、解锁和任务清理。
手动在锁定的 Mac 上操作时，逐步检查每个命令的结果：

```sh
sparekey probe --json
sparekey unlock --json
```

`probe` 唤醒显示器并验证密码框，不读取或提交密码。
如果在密码宽限期内唤醒后返回 `unlocked` 和 `lockToken`，请保留该令牌并跳过 `unlock`。
否则保留成功解锁后返回的令牌。清理任务时仅使用本任务获得的令牌：

```sh
sparekey lock --lock-token "$TASK_LOCK_TOKEN" --json
```

`TASK_LOCK_TOKEN` 是存放返回令牌的示例 shell 变量，不是 Sparekey 配置变量。
原本已解锁的会话不会获得新的重新锁定权限。出现 `relock_revoked` 时保持当前状态，不要用 `--force` 绕过任务清理限制。

## 配置

使用 CLI 选项配置，没有用户配置文件。完整路径见[英文配置说明](README.md#configuration)。

- helper 安装在 `~/Library/Application Support/sparekey/bin/sparekey`。
- Codex 技能位于 `~/.agents/skills/sparekey/SKILL.md`，Claude Code 技能位于 `~/.claude/skills/sparekey/SKILL.md`。
- `setup --identity NAME` 选择已有签名身份；`setup --reset-password` 替换保存的密码。
- `unlock --no-cover` 跳过本次解锁的默认遮罩。
- 可稍后运行 `sparekey skill install --agent codex` 或 `--agent claude` 安装技能。

替换修改过的技能需要确认或 `skill install --force`，并备份为 `SKILL.md.bak`。已有备份不会被覆盖。
只有迁移旧 Sparekey 插件时需要 Codex CLI，确认移除后才写入技能。全新安装不需要 Codex CLI。

升级或重新构建后，在本地运行 `sparekey setup` 更新 helper 和技能；只要仍可读取，就复用保存的密码。
在本地交互式终端运行 `sparekey uninstall` 可移除管理的安装内容及匹配的技能。
签名身份、辅助功能条目、修改过的技能、自建链接和 Homebrew CLI 需要另行移除。

## CLI 参考

```sh
sparekey --help
sparekey help unlock
sparekey --version
```

[CLI 参考](docs/CLI.md)集中列出了公开命令的实际语法、选项、JSON 字段、退出码和令牌规则。不带参数运行时显示帮助。
`--json` 适用于 `unlock`、`lock`、`status`、`probe` 和 `doctor`。退出码为成功 `0`、操作失败 `1`、用法错误 `2`。

## 工作原理

CLI 通过私有 Unix 套接字向用户级签名 helper 发送请求，双方检查对方的用户 ID。
helper 验证控制台会话、Apple 签名的 `loginwindow`、账户标签和密码框后，才使用登录钥匙串中的密码。
持久化的 30 秒尝试限制，以及提交后无法确认解锁时的熔断器，会限制后续尝试。

默认遮罩在密码提交前放到锁屏下方。通过 **Unlock Mac** 完成 macOS 认证后显示画面，并撤销任务的重新锁定权限。
系统锁定事件、唤醒保持结束或 helper 重启也会使令牌失效。60 分钟是唤醒保持上限，不是自动锁定计划。
详情见[设计说明](docs/DESIGN.md)和[代理技能](skills/sparekey/SKILL.md)。

## 安全注意事项

安装前请阅读[安全政策](SECURITY.md)。

- 以同一用户身份运行的任何进程都能请求解锁。请在可信的个人账户中使用。
- 遮罩不会锁定 Mac，也无法防止不看屏幕的物理输入。截图不会包含遮罩。
- helper 监听本地套接字而非网络，无法防御已经以您的身份运行的恶意软件。
- 不要把密码放进聊天、命令参数、环境变量或文档，也不要把令牌保存到日志或报告。
- 不要循环尝试失败的解锁或绕过账户、密码框验证。请按安全政策私下报告漏洞。

## 故障排除

先检查 `sparekey doctor`。检查成功不代表当前锁屏布局或实际解锁已经验证。

- `not_set_up`、`helper_not_running`、`helper_version_mismatch`：在本地运行 `sparekey setup`。
- `accessibility_missing`：在系统设置 > 隐私与安全性 > 辅助功能中启用 helper，再运行 setup。
- `credential_unavailable`：重新运行 setup；密码已过期时使用 `sparekey setup --reset-password`。
- `breaker_tripped`、`unlock_not_confirmed`、`rate_limited`：停止重复尝试，先检查原因。
- 账户或密码框验证错误：不要向未经验证的字段输入。`relock_revoked` 时保持当前状态。
- `display_sleep_not_confirmed`：可能已经锁定。下一步操作前先读取 `status`。

残留的“强制退出应用程序”窗口可能使布局不受支持，有限恢复步骤见[技能](skills/sparekey/SKILL.md)。probe 失败并不表示提交过密码。

## 开发

在仓库根目录运行：

```sh
swift build
swift test
swift build -c release
python3 scripts/embed-agent-assets.py --check
```

`Package.swift` 定义可执行文件、`SparekeyCore` 以及 core 和 transport 测试。资源检查验证技能源文件和生成的 Swift 文件是否一致。
[Shimmer 渲染工具](scripts/render-shimmer/README.md)无需操作 helper 即可生成图像。
[本地签名实验](scripts/spike/README.md)会修改 Keychain 和 LaunchAgent 状态，请有意运行。
发布记录见[更新日志](CHANGELOG.md)。锁屏交互方式参考了 [Cindy](https://github.com/makecindy/cindy)，Sparekey 是独立实现。

## 许可证

[MIT](LICENSE)，版权所有 yoonpooh。
