<p align="center">
  <img src="docs/assets/logo.png" alt="Sparekey logo" width="140">
</p>

<h1 align="center">Sparekey</h1>

<p align="center">
  <strong>交给 AI 代理的一把 Mac 备用钥匙。</strong><br>
  解锁屏幕，完成工作，再重新锁上。
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black.svg" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange.svg" alt="Swift 5.9+">
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.ko.md">한국어</a> · <a href="README.ja.md">日本語</a> · 简体中文 · <a href="README.es.md">Español</a>
</p>

<p align="center">
  <sub>最新版本：<strong>0.2.1</strong>，解锁后 macOS 立即关闭屏幕时会重新唤醒。详见<a href="CHANGELOG.md">更新日志</a>。</sub>
</p>

<p align="center">
  <img src="docs/assets/cover.png" alt="Mac 显示器上的 Sparekey 屏幕遮罩" width="720">
</p>

## 为什么需要 Sparekey

Mac 一锁屏，操作电脑和浏览器的代理就会停下来。结果要么让 Mac 连续几个小时保持解锁，要么回来才发现任务根本没跑。

Sparekey 是一个小巧的 macOS 命令行工具。它让代理使用您保存在本机的密码，解锁**您自己的、已经登录的**会话，完成任务后再恢复锁定。代理工作期间，一块黑色遮罩会挡住实体显示器，旁人看不到屏幕内容。

```sh
sparekey unlock   # let the agent get to work; cover the physical displays
sparekey lock     # restore the lock when it is done
```

装好随附的代理技能后，这些步骤都不用再交代。只要让代理在锁定的 Mac 上做一件普通的 GUI 任务，它就会自己检查锁定状态、解锁、干活，最后重新锁屏。

### 它不做什么

Sparekey 不是密码绕过工具、恢复工具，也不是远程访问服务。它无法在启动时解锁 FileVault，也无法解锁已退出登录的会话、其他用户的账户，或无法连接到的睡眠中的 Mac。

> [!WARNING]
> **状态：早期阶段（0.2.1）。** 在搭载 Apple silicon 的 macOS 27.2 上可以正常工作：两次未经额外提示的代理运行都成功完成了解锁、工作和重新锁定。其他 macOS 版本尚未测试。它依赖锁屏界面的 Accessibility 布局，而不是公开的解锁 API。

## 快速开始

您需要：macOS 13 或更高版本并已登录桌面会话；包含 Swift 5.9 或更高版本的 Xcode Command Line Tools；用于一次性设置的 Mac 本地终端。不需要 Apple Developer 账户。

**1. 安装**：使用 Homebrew（在您的 Mac 上从源码构建）。

```sh
brew install yoonpooh/tap/sparekey
```

**2. 设置**：在 Mac 已解锁时，于本地终端（而不是通过 SSH）运行。

```sh
sparekey setup --skill codex   # or: --skill claude, --skill claude,codex, --no-skill
```

当 macOS 询问是否允许使用签名密钥时，请点击 **Allow**，不要点击 **Always Allow**。登录密码请直接在不回显的提示中输入。

**3. 使用**：让代理执行 GUI 任务，或者自己试一试。

```sh
sparekey status   # locked or unlocked
sparekey doctor   # check the install
```

**交给代理来做。** 把下面这段话粘贴给 Codex、Claude Code 等代理。代理会完成安装，只把需要输入密码的 setup 步骤交给你，因为密码必须在你自己的终端里输入。

```text
Install Sparekey on this Mac: https://github.com/yoonpooh/sparekey
1. Run `brew install yoonpooh/tap/sparekey`.
2. Setup asks for my login password, so don't run `sparekey setup` yourself.
   Tell me the exact command to run in my own terminal, with the --skill
   option for the agent you are, and wait until I say it's done.
3. Run `sparekey doctor` and report the result.
Never ask me for the password.
```

<details>
<summary><strong>改为从源码构建</strong></summary>

```sh
git clone https://github.com/yoonpooh/sparekey.git
cd sparekey
swift build -c release
.build/release/sparekey setup --skill codex
```

然后把 `sparekey` 加入 `PATH`：

```sh
ln -s "$HOME/Library/Application Support/sparekey/bin/sparekey" ~/.local/bin/sparekey
sparekey doctor
```

</details>

<details>
<summary><strong>setup 会做什么</strong></summary>

1. 在登录钥匙串中创建 `sparekey local signing` 身份（仅首次运行）。
2. 为 helper 签名，并安装到 `~/Library/Application Support/sparekey/bin/sparekey`。
   - 当 macOS 询问是否允许使用签名密钥时，请点击 **Allow**，不要点击 **Always Allow**。
3. 要求输入两次登录密码。输入内容不会显示，并由 macOS 进行校验。
   - 切勿把密码粘贴到聊天、命令参数或环境变量中。
4. 启动后台 helper，并安装您选择的代理技能。
5. 引导您为 helper 开启 **Accessibility** 权限：打开设置面板、在 Finder 中显示该文件并复制其路径，开启后再次检查。

</details>

### 升级

执行 `brew upgrade sparekey` 或重新构建后，请再次运行 `sparekey setup`。在此之前，新版 CLI 会报告 `helper_version_mismatch`。只要 helper 仍能读取密码，setup 就只会刷新已签名的 helper，不会再次询问密码。

## 主要功能

- **带确认的解锁与锁定。** `unlock` 只提交一次密码，并确认状态已改变；`lock` 锁定后同样会确认，已经锁定时不做任何操作。
- **屏幕遮罩。** 灵感来自 Codex 的 Locked Computer Use。代理工作时，一块显示 Sparekey 标志、“Your agent is using this Mac”字样和 **Lock Mac** 按钮的黑色遮罩会挡住实体显示器。
  - 遮罩在提交密码**之前**就已铺在锁屏界面下方，桌面一瞬间也不会露出来。
  - 屏幕截图和录屏都不会捕获遮罩，因此代理看到的是真实屏幕，点击和键盘输入也会正常传到下面的应用。
  - 点击一次 **Lock Mac** 即可锁定 Mac。运行 `sparekey lock` 或以其他方式重新锁定时，遮罩会被移除。
  - 使用 `sparekey unlock --no-cover` 可以不显示遮罩。遮罩只是挡住屏幕，并不会锁定 Mac。
- **保持唤醒。** 确认解锁后，显示器会一直保持唤醒，直到运行 `sparekey lock`、以其他方式重新锁定，或满 60 分钟，避免任务进行到一半因闲置睡眠而重新锁定。
- **锁屏恢复。** 如果锁屏界面亮着，却只显示壁纸和时钟而看不到账户，Sparekey 会让显示器休眠→唤醒一次，把账户重新调出来。它绝不会在未经验证的界面上输入。
- **异常即停止。** 最多提交一次密码，30 秒尝试限制，解锁未能确认时触发熔断器。
- 提供面向 Codex 和 Claude Code 的**代理技能**，以及供脚本使用的 `--json` 输出。

## 工作原理

```text
agent ──▶ sparekey CLI ──(private Unix socket, same-user check)──▶ helper (LaunchAgent)
                                                                     │
                     verifies console user, Apple-signed loginwindow,│
                     your account, and a single secure password field│
                                                                     ▼
                         login Keychain ──▶ one submission ──▶ state check
```

- `setup` 会把二进制文件复制到固定位置，用本地代码签名身份签名，并作为每个用户独立的后台 helper 运行。
- 密码保存在您的登录钥匙串中，只有这个已签名的 helper 能读取。
- helper 只会填写经过验证的密码框，并且**最多提交一次**。遇到其他账户、对话框、恢复界面或布局变化等意外情况时，会以安全方式中止。
- 持久化的 30 秒限制和熔断器，可以防止过期密码导致登录失败不断累积。

设计说明见 [docs/DESIGN.md](docs/DESIGN.md)。

## 代理技能

setup 可以为 **Codex**（`~/.agents/skills/sparekey`）和 **Claude Code**（`~/.claude/skills/sparekey`）安装技能，也可以之后再安装：

```sh
sparekey skill install --agent codex   # or: --agent claude
```

该技能会要求代理：

- 在执行 GUI 操作之前，或一旦无法访问应用或窗口，就先检查锁定状态；
- 只解锁一次，确认解锁后再执行任务；
- 即使任务失败，也只在自己解锁了 Mac 的情况下，于结束后重新锁定；
- 不重试，而是停下来报告错误。

请求执行 GUI 任务，即视为允许代理为该任务解锁。如果希望任务结束后 Mac 保持锁定或保持解锁，请告诉代理。

### 在代理指令中预先授权

在多代理协作的配置中，编排代理可能会让下属代理不要动锁屏，代理也可能先停下来征求许可。为避免这种情况，请把下面这段话加入 `CLAUDE.md`、`AGENTS.md` 或编排代理的系统提示词：

```text
Screen lock: I pre-authorize unlocking this Mac with the sparekey skill
for any task that needs the screen. Use it without asking, and never
restrict this when delegating to other agents.
```

即使没有这段话，只要你请求 GUI 任务，技能仍会解锁。这段话的作用是防止这项授权在中途被去掉或被再次确认。

## 命令

| 命令 | 作用 |
| --- | --- |
| `sparekey unlock [--no-cover]` | 解锁一次并确认状态；默认遮住实体显示器，并在 `lock` 或满 60 分钟前保持显示器唤醒 |
| `sparekey lock` | 锁定并确认；已锁定时不做任何操作 |
| `sparekey status` | 输出 `locked` 或 `unlocked` |
| `sparekey probe` | 在不读取密码的情况下唤醒显示器并检查密码框 |
| `sparekey setup` | 安装或刷新 helper、凭据和技能。选项：`--skill`、`--no-skill`、`--reset-password`、`--identity NAME` |
| `sparekey doctor` | 检查安装、签名、helper、Accessibility、凭据和技能 |
| `sparekey skill install` | 安装代理技能。选项：`--agent claude\|codex`、`--force` |
| `sparekey uninstall` | 移除 helper、凭据、LaunchAgent 以及 Sparekey 写入的技能 |
| `sparekey help [command]` | 显示帮助 |
| `sparekey version` | 输出版本号 |

不带参数运行 `sparekey` 只会显示帮助，绝不会解锁。

<details>
<summary><strong>JSON 输出、退出码和错误码</strong></summary>

`unlock`、`lock`、`status`、`probe` 和 `doctor` 支持 `--json`：

```json
{"ok":true,"command":"status","state":"locked","message":"locked"}
{"ok":false,"command":"unlock","error":{"code":"rate_limited","message":"..."}}
```

退出码：`0` 成功，`1` 操作失败，`2` 用法错误。`status` 无论报告哪种状态都算成功，请检查 `state`。

错误码：`usage`、`not_set_up`、`helper_not_running`、`helper_version_mismatch`、`no_console_session`、`accessibility_missing`、`credential_unavailable`、`login_window_unsupported`、`field_not_ready`、`cover_unavailable`、`rate_limited`、`breaker_tripped`、`unlock_not_confirmed`、`lock_not_confirmed`、`internal`。`doctor --json` 还可能报告 `skill_outdated`，并附带按检查项列出的 `statuses` 映射（`ok`、`warn`、`fail`、`skip`）。

</details>

## 常见问题与故障排除

请先运行 `sparekey doctor`。每个失败项都会给出修复方法。

**遮罩会锁定我的 Mac 吗？**
不会。它只挡住屏幕，并不锁定。请点击遮罩上的 **Lock Mac**，或运行 `sparekey lock`。

**为什么代理的截图里看不到遮罩？**
这是有意设计的。屏幕截图和录屏会排除遮罩，所以代理看到的是真实屏幕。

**锁屏界面只显示壁纸和时钟。**
Sparekey 会让显示器休眠→唤醒一次，把账户重新调出来。它绝不会在未经验证的界面上输入。

**`helper_version_mismatch`**
CLI 已升级或重新构建，但 helper 还是旧版本。请再次运行 `sparekey setup`。

**缺少 Accessibility 权限**
在“系统设置”→“隐私与安全性”→“辅助功能”中启用 `~/Library/Application Support/sparekey/bin/sparekey`。如果刚刚启用，请再次运行 `setup`，或重启 helper：

```sh
launchctl kickstart -k "gui/$(id -u)/io.github.yoonpooh.sparekey.helper"
```

**`breaker_tripped` 或 `unlock_not_confirmed`**
保存的密码可能已失效，例如您修改过密码。请在本地运行 `sparekey setup --reset-password`。

**升级后出现 `credential_unavailable`**
再次运行 `sparekey setup`，并在提示时输入密码。

**`rate_limited`**
过去 30 秒内已经尝试过一次。不要循环重试。

## 安全

安装前请先阅读 [SECURITY.md](SECURITY.md)。简要来说：

- **以您的用户身份运行的任何进程，都可以请求 helper 解锁。** Sparekey 面向可信的个人账户，无法防御已经以您的身份运行的恶意软件。
- 默认遮罩会在代理工作期间挡住实体显示器。截图中不会出现遮罩，代理仍可操作其下方的应用。
- helper 启用了强化运行时（hardened runtime），只在私有的本地套接字上监听，从不监听网络。
- 签名密钥无法导出，也没有任何应用被预先信任使用它。点击 **Always Allow** 会改变这一点。
- 切勿把登录密码粘贴到聊天、命令参数或环境变量中，只在 setup 的隐藏输入提示中输入。

请通过 GitHub 安全公告（security advisories）私下报告漏洞。

## 卸载

```sh
sparekey uninstall
```

这会移除已保存的凭据、helper、LaunchAgent、运行时文件，以及 Sparekey 写入的技能文件。以下内容不会被移除：

- `sparekey local signing` 身份（如有需要，请在“钥匙串访问”中删除）；
- Accessibility 条目（请在“系统设置”中移除）；
- `~/.local/bin/sparekey` 链接。

## 致谢

锁屏交互方式参考了 Cindy 的 [MacScreenUnlock.swift](https://github.com/makecindy/cindy/blob/main/packages/remote-credentials-native/Sources/CindyRemoteCredentials/MacScreenUnlock.swift)（Apache-2.0）。Sparekey 是独立实现。

## 许可证

[MIT](LICENSE) © yoonpooh
