<p align="center">
  <img src="docs/assets/logo.png" alt="Sparekey logo" width="160">
</p>

<h1 align="center">Sparekey</h1>

<p align="center">
  <strong>给 AI 代理使用的 Mac 备用钥匙。</strong><br>
  解锁屏幕，完成工作，然后重新锁定。
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black.svg" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange.svg" alt="Swift 5.9+">
</p>

[English](README.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · 简体中文 · [Español](README.es.md)

---

Mac 一旦锁定，需要操作电脑或浏览器的代理就无法继续工作。Sparekey 是一个小型 macOS CLI，让代理使用保存在本机的密码解锁**您自己的、已经登录的**会话，完成任务后再将其锁定。

```sh
sparekey unlock   # let the agent get to work; cover the physical displays
sparekey lock     # restore the lock when it is done
```

借助随附的代理技能，您无需专门交代这些步骤。只需让代理在锁定的 Mac 上完成普通 GUI 任务，它就会自行检查锁定状态、解锁、工作，并在结束后重新锁屏。

> **状态：**早期阶段（0.1）。在搭载 Apple silicon 的 macOS 27.2 上，两次未经额外提示的代理运行都成功完成了解锁、工作和重新锁定。其他 macOS 版本尚未测试。本工具依赖锁屏界面的 Accessibility 布局，而不是公开的解锁 API。

## 不适用的场景

Sparekey 不是密码绕过工具、恢复工具或远程访问服务。它无法在启动时解锁 FileVault，也无法解锁已退出登录的会话、其他用户的账户，或无法连接到的睡眠中的 Mac。

## 工作原理

```text
agent ──▶ sparekey CLI ──(private Unix socket, same-user check)──▶ helper (LaunchAgent)
                                                                     │
                     verifies console user, Apple-signed loginwindow,│
                     your account, and a single secure password field│
                                                                     ▼
                         login Keychain ──▶ one submission ──▶ state check
```

- `setup` 将二进制文件复制到固定位置，使用本地代码签名身份为其签名，并将其作为当前用户的后台 helper 运行。
- 密码存储在登录 Keychain 中，只有已签名的该 helper 能读取。
- helper 只会在经过验证的单个密码输入框中填写密码，且**最多提交一次**。遇到其他账户、对话框、恢复界面或布局变化等异常情况时会安全停止。
- 提交密码前，会在锁屏界面下方放置黑色遮罩。解锁后，遮罩会遮住实体显示器，但不会出现在屏幕截图中。代理的点击和输入可以穿过遮罩。点击遮罩上的 Lock Mac 按钮即可锁屏。使用 `sparekey unlock --no-cover` 可跳过遮罩。
- 持续生效的 30 秒频率限制和熔断机制可避免旧密码导致登录失败次数不断累积。

## 系统要求

- macOS 13 或更新版本，且已有登录的桌面会话
- 包含 Swift 5.9 或更新版本的 Xcode Command Line Tools
- 用于初次设置的 Mac 本地终端

无需 Apple Developer 账户。

## 安装

通过 Homebrew 安装（在您的 Mac 上从源码构建）：

```sh
brew install yoonpooh/tap/sparekey
sparekey setup --skill codex   # or: --skill claude, --skill claude,codex, --no-skill
```

或者自行构建：

```sh
git clone https://github.com/yoonpooh/sparekey.git
cd sparekey
swift build -c release
.build/release/sparekey setup --skill codex
```

请在 Mac 已解锁时从本地终端运行 setup，不要通过 SSH 运行。它会：

1. 在登录 Keychain 中创建 `sparekey local signing` 身份（仅首次运行）。
2. 为 helper 签名并安装到 `~/Library/Application Support/sparekey/bin/sparekey`。
   - 如果 macOS 询问是否允许使用签名密钥，请点击 **Allow**，不要点击 **Always Allow**。
3. 要求您输入两次登录密码。输入内容不会显示，并由 macOS 验证。
   - 切勿将密码粘贴到聊天、命令参数或环境变量中。
4. 启动后台 helper 并安装所选的代理技能。
5. 引导您为 helper 开启 **Accessibility**。它会打开设置面板、在 Finder 中显示文件并复制路径，然后在您启用权限后再次检查。

如果您从源码构建，请将 `sparekey` 加入 `PATH`：

```sh
ln -s "$HOME/Library/Application Support/sparekey/bin/sparekey" ~/.local/bin/sparekey
sparekey doctor
```

运行 `brew upgrade sparekey` 或重新构建后，请再次运行 `sparekey setup`。除非 helper 已无法读取密码，否则它会在不重新询问密码的情况下更新已签名的 helper。

## 代理技能

setup 可以为 **Codex**（`~/.agents/skills/sparekey`）和 **Claude Code**（`~/.claude/skills/sparekey`）安装技能。您也可以稍后安装：

```sh
sparekey skill install --agent codex
```

该技能会指示代理：

- 在开始 GUI 工作前，或一旦无法访问应用或窗口，就检查锁定状态；
- 只解锁一次，确认成功后再完成任务；
- 工作结束后，只有在它自己解锁了 Mac 的情况下才重新锁定，即使任务失败也是如此；
- 遇到错误时停止并报告，不反复重试。

请求 GUI 工作即表示允许代理为该任务解锁。如果希望任务结束后 Mac 保持锁定或保持解锁，请告知代理。

## 命令

| 命令 | 作用 |
| --- | --- |
| `sparekey unlock [--no-cover]` | 解锁一次并确认状态；默认遮住实体显示器，并使显示器保持唤醒，直到运行 `lock` 或经过 60 分钟。 |
| `sparekey lock` | 锁定并确认；已经锁定时不执行任何操作。 |
| `sparekey status` | 输出 `locked` 或 `unlocked`。 |
| `sparekey probe` | 唤醒显示器并检查密码输入框，不读取密码。 |
| `sparekey setup` | 安装或更新 helper、凭据和技能。 |
| `sparekey doctor` | 检查安装、签名、helper、Accessibility、凭据和技能。 |
| `sparekey skill install` | 安装代理技能。 |
| `sparekey uninstall` | 移除 helper、凭据、LaunchAgent 和 Sparekey 写入的技能。 |

不带参数运行 `sparekey` 只会显示帮助，绝不会解锁。

<details>
<summary><strong>JSON 输出、退出码和错误码</strong></summary>

`unlock`、`lock`、`status`、`probe` 和 `doctor` 支持 `--json`：

```json
{"ok":true,"command":"status","state":"locked","message":"locked"}
{"ok":false,"command":"unlock","error":{"code":"rate_limited","message":"..."}}
```

退出码：`0` 表示成功，`1` 表示操作失败，`2` 表示用法错误。`status` 报告任一状态都可能成功，因此请查看 `state`。

错误码：`usage`、`not_set_up`、`helper_not_running`、`helper_version_mismatch`、`no_console_session`、`accessibility_missing`、`credential_unavailable`、`login_window_unsupported`、`field_not_ready`、`cover_unavailable`、`rate_limited`、`breaker_tripped`、`unlock_not_confirmed`、`lock_not_confirmed`、`internal`。`doctor --json` 还可能报告 `skill_outdated`，并附上逐项检查结果的 `statuses` 映射（`ok`、`warn`、`fail`、`skip`）。

</details>

## 故障排查

先运行 `sparekey doctor`。每个失败的检查项都会显示修复方法。

- **缺少 Accessibility 权限：**在系统设置 → 隐私与安全性 → 辅助功能中启用 `~/Library/Application Support/sparekey/bin/sparekey`。如果刚启用，请再次运行 `setup`，或使用 `launchctl kickstart -k "gui/$(id -u)/io.github.yoonpooh.sparekey.helper"` 重启 helper。
- **`breaker_tripped` 或 `unlock_not_confirmed`：**保存的密码可能不正确，例如您修改密码之后。请在本机运行 `sparekey setup --reset-password`。
- **升级后出现 `credential_unavailable`：**再次运行 `sparekey setup`，并在提示时输入密码。
- **`rate_limited`：**过去 30 秒内已有一次尝试。请勿循环重试。

## 安全性

安装前请阅读 [SECURITY.md](SECURITY.md)。简要来说：

- **以您的用户身份运行的任何进程都可以请求 helper 解锁。** Sparekey 适用于可信的个人账户，无法防御已经以您身份运行的恶意软件。
- 默认遮罩会在代理工作期间遮住实体显示器。屏幕截图不会包含遮罩，代理仍能操作其下方的应用。
- helper 使用强化运行时，只监听私有本地套接字，绝不通过网络监听。
- 签名密钥无法导出，且没有任何应用被预先信任可使用它。点击 **Always Allow** 会改变这一点。

请通过 GitHub 安全公告私下报告漏洞。

## 卸载

```sh
sparekey uninstall
```

这会移除保存的凭据、helper、LaunchAgent、运行时文件以及 Sparekey 写入的技能文件。以下内容不会移除：

- `sparekey local signing` 身份（如有需要，可在 Keychain Access 中删除）；
- Accessibility 条目（可在系统设置中移除）；
- `~/.local/bin/sparekey` 链接。

## 致谢

锁屏交互方式参考了 Cindy 的 [MacScreenUnlock.swift](https://github.com/makecindy/cindy/blob/main/packages/remote-credentials-native/Sources/CindyRemoteCredentials/MacScreenUnlock.swift)（Apache-2.0）。Sparekey 是独立实现。设计说明见 [docs/DESIGN.md](docs/DESIGN.md)。

## 许可证

[MIT](LICENSE) © yoonpooh
