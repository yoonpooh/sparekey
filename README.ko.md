<p align="center">
  <img src="docs/assets/logo.png" alt="Sparekey logo" width="160">
</p>

<h1 align="center">Sparekey</h1>

<p align="center">
  <strong>AI 에이전트를 위한 Mac의 예비 열쇠.</strong><br>
  화면 잠금을 풀고, 작업을 마친 뒤, 다시 잠급니다.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black.svg" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange.svg" alt="Swift 5.9+">
</p>

<p align="center">
  <a href="README.md">English</a> · 한국어 · <a href="README.ja.md">日本語</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.es.md">Español</a>
</p>

---

Mac이 잠기는 순간 컴퓨터와 브라우저를 조작하는 에이전트의 작업도 멈춥니다. Sparekey는 Mac에 로컬로 저장한 암호를 사용해 에이전트가 **본인의 이미 로그인된** 세션 잠금을 풀고, 작업을 마친 뒤 다시 잠글 수 있게 하는 작은 macOS CLI입니다.

```sh
sparekey unlock   # let the agent get to work; cover the physical displays
sparekey lock     # restore the lock when it is done
```

함께 제공되는 에이전트 스킬을 사용하면 이런 과정을 일일이 지시할 필요가 없습니다. 잠긴 Mac에서 일반적인 GUI 작업을 요청하면 에이전트가 잠금 상태를 확인하고, 잠금을 풀어 작업한 다음, 스스로 화면을 다시 잠급니다.

## 0.2.0의 새로운 기능

Codex의 Locked Computer Use에서 영감을 받아, 에이전트가 작업하는 동안 실제 디스플레이를 가리는 기능을 추가했습니다. 검은 가림막에는 Sparekey 로고와 “Your agent is using this Mac” 문구, **Lock Mac** 버튼이 표시되어 주변 사람이 작업 내용을 볼 수 없습니다.

<p align="center">
  <img src="docs/assets/cover.png" alt="Mac 디스플레이에 표시된 Sparekey 화면 가림막" width="720">
</p>

- 암호를 제출하기 **전에** 잠금 화면 아래에 가림막을 배치해 데스크톱이 잠깐 노출되는 일도 막습니다. 스크린샷과 화면 녹화에는 가림막이 잡히지 않아 에이전트는 실제 화면을 볼 수 있고, 클릭과 입력도 그대로 전달됩니다. **Lock Mac**을 한 번 클릭하면 Mac이 잠깁니다. `sparekey unlock --no-cover`로 가림막을 생략할 수 있으며, `sparekey lock` 또는 다른 방법으로 다시 잠그면 가림막이 제거됩니다. 가림막은 화면을 숨길 뿐 Mac을 잠그지는 않습니다.
- 잠긴 화면이 깨어 있지만 계정 대신 배경화면과 시계만 표시되면, 디스플레이를 한 번 잠자기 상태로 전환했다가 깨워 계정을 다시 표시합니다. 확인되지 않은 화면에는 여전히 암호를 입력하지 않습니다.
- `brew upgrade sparekey` 후에는 `sparekey setup`을 다시 실행하세요. 그 전까지 새 CLI는 `helper_version_mismatch`를 보고합니다.

> **상태:** 초기 단계(0.2.0). Apple silicon의 macOS 27.2에서 에이전트가 별도 지시 없이 잠금을 풀고 작업한 뒤 다시 잠그는 과정이 두 차례 성공했습니다. 다른 macOS 버전은 시험하지 않았습니다. 공개된 잠금 해제 API가 아닌 잠금 화면의 Accessibility 레이아웃에 의존합니다.

## 할 수 없는 일

Sparekey는 암호 우회 도구, 복구 도구 또는 원격 접속 서비스가 아닙니다. 시동 시 FileVault 잠금, 로그아웃된 세션, 다른 사용자 계정, 접근할 수 없는 잠자기 상태의 Mac은 잠금 해제할 수 없습니다.

## 작동 방식

```text
agent ──▶ sparekey CLI ──(private Unix socket, same-user check)──▶ helper (LaunchAgent)
                                                                     │
                     verifies console user, Apple-signed loginwindow,│
                     your account, and a single secure password field│
                                                                     ▼
                         login Keychain ──▶ one submission ──▶ state check
```

- `setup`은 바이너리를 고정된 위치에 복사하고, 로컬 코드 서명 ID로 서명한 뒤, 사용자별 백그라운드 helper로 실행합니다.
- 암호는 로그인 Keychain에 저장됩니다. 서명된 해당 helper만 암호를 읽을 수 있습니다.
- helper는 확인된 암호 입력란 하나에만 암호를 입력하고 **최대 한 번만** 제출합니다. 다른 계정, 대화상자, 복구 화면, 레이아웃 변경 등 예상 밖의 상황에서는 안전하게 중단합니다.
- 지속적으로 적용되는 30초 제한과 차단 장치가 오래된 암호로 로그인 실패가 누적되는 것을 막습니다.

## 요구 사항

- macOS 13 이상 및 로그인된 데스크톱 세션
- Swift 5.9 이상이 포함된 Xcode Command Line Tools
- 최초 설정에 사용할 Mac의 로컬 터미널

Apple Developer 계정은 필요하지 않습니다.

## 설치

Homebrew로 설치(Mac에서 소스 빌드):

```sh
brew install yoonpooh/tap/sparekey
sparekey setup --skill codex   # or: --skill claude, --skill claude,codex, --no-skill
```

직접 빌드할 수도 있습니다.

```sh
git clone https://github.com/yoonpooh/sparekey.git
cd sparekey
swift build -c release
.build/release/sparekey setup --skill codex
```

Mac이 잠금 해제된 상태에서 SSH가 아닌 로컬 터미널로 setup을 실행하세요. setup은 다음 작업을 수행합니다.

1. 로그인 Keychain에 `sparekey local signing` ID를 만듭니다(첫 실행 시에만).
2. helper를 서명하고 `~/Library/Application Support/sparekey/bin/sparekey`에 설치합니다.
   - macOS에서 서명 키 사용을 묻는 메시지가 나오면 **Always Allow**가 아닌 **Allow**를 클릭하세요.
3. 로그인 암호를 두 번 입력받습니다. 입력 내용은 표시되지 않으며 macOS를 통해 확인합니다.
   - 암호를 채팅, 명령 인수 또는 환경 변수에 붙여 넣지 마세요.
4. 백그라운드 helper를 시작하고 선택한 에이전트 스킬을 설치합니다.
5. helper의 **Accessibility** 권한을 켜도록 안내합니다. 설정 창을 열고 Finder에서 파일을 표시하며 경로를 복사한 다음, 권한을 켠 후 다시 확인합니다.

소스에서 빌드했다면 `sparekey`를 `PATH`에 추가하세요.

```sh
ln -s "$HOME/Library/Application Support/sparekey/bin/sparekey" ~/.local/bin/sparekey
sparekey doctor
```

`brew upgrade sparekey`를 실행하거나 다시 빌드한 뒤에는 `sparekey setup`을 다시 실행하세요. helper가 암호를 더 이상 읽지 못하는 경우가 아니면 암호를 다시 묻지 않고 서명된 helper를 갱신합니다.

## 에이전트 스킬

setup은 **Codex**(`~/.agents/skills/sparekey`)와 **Claude Code**(`~/.claude/skills/sparekey`)용 스킬을 설치할 수 있습니다. 나중에 설치할 수도 있습니다.

```sh
sparekey skill install --agent codex
```

스킬은 에이전트에 다음을 지시합니다.

- GUI 작업 전에, 또는 앱이나 창에 접근하지 못하는 즉시 잠금 상태를 확인합니다.
- 한 번 잠금을 풀고 이를 확인한 뒤 작업합니다.
- 작업이 실패해도 자신이 Mac의 잠금을 풀었을 때만 작업 후 다시 잠급니다.
- 재시도하지 않고 오류를 보고합니다.

GUI 작업 요청은 해당 작업을 위해 잠금을 풀어도 된다는 허가로 간주됩니다. 작업 후 Mac을 잠긴 상태 또는 잠금 해제된 상태로 두고 싶다면 에이전트에게 알려 주세요.

## 명령

| 명령 | 기능 |
| --- | --- |
| `sparekey unlock [--no-cover]` | 한 번 잠금을 풀고 상태를 확인합니다. 기본적으로 실제 디스플레이를 가리고 `lock` 명령 실행 또는 60분 경과까지 디스플레이가 잠들지 않게 합니다. |
| `sparekey lock` | 화면을 잠그고 확인합니다. 이미 잠겨 있으면 아무 작업도 하지 않습니다. |
| `sparekey status` | `locked` 또는 `unlocked`를 출력합니다. |
| `sparekey probe` | 암호를 읽지 않고 디스플레이를 깨워 암호 입력란을 확인합니다. |
| `sparekey setup` | helper, 자격 증명 및 스킬을 설치하거나 갱신합니다. |
| `sparekey doctor` | 설치, 서명, helper, Accessibility, 자격 증명 및 스킬을 점검합니다. |
| `sparekey skill install` | 에이전트 스킬을 설치합니다. |
| `sparekey uninstall` | helper, 자격 증명, LaunchAgent 및 Sparekey가 작성한 스킬을 제거합니다. |

인수 없이 `sparekey`를 실행하면 도움말이 표시되며 잠금은 해제되지 않습니다.

<details>
<summary><strong>JSON 출력, 종료 코드 및 오류 코드</strong></summary>

`unlock`, `lock`, `status`, `probe`, `doctor`는 `--json`을 지원합니다.

```json
{"ok":true,"command":"status","state":"locked","message":"locked"}
{"ok":false,"command":"unlock","error":{"code":"rate_limited","message":"..."}}
```

종료 코드: 성공 `0`, 작업 실패 `1`, 사용법 오류 `2`. `status`는 두 상태 중 어느 쪽을 보고해도 성공이므로 `state`를 확인하세요.

오류 코드: `usage`, `not_set_up`, `helper_not_running`, `helper_version_mismatch`, `no_console_session`, `accessibility_missing`, `credential_unavailable`, `login_window_unsupported`, `field_not_ready`, `cover_unavailable`, `rate_limited`, `breaker_tripped`, `unlock_not_confirmed`, `lock_not_confirmed`, `internal`. `doctor --json`은 `skill_outdated`도 보고할 수 있으며 각 검사 결과가 담긴 `statuses` 맵(`ok`, `warn`, `fail`, `skip`)을 추가합니다.

</details>

## 문제 해결

먼저 `sparekey doctor`를 실행하세요. 실패한 각 항목에 해결 방법이 표시됩니다.

- **Accessibility 권한 없음:** 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 `~/Library/Application Support/sparekey/bin/sparekey`를 허용하세요. 방금 허용했다면 `setup`을 다시 실행하거나 `launchctl kickstart -k "gui/$(id -u)/io.github.yoonpooh.sparekey.helper"`로 helper를 재시작하세요.
- **`breaker_tripped` 또는 `unlock_not_confirmed`:** 암호를 변경했다면 저장된 암호가 틀렸을 수 있습니다. 로컬에서 `sparekey setup --reset-password`를 실행하세요.
- **업그레이드 후 `credential_unavailable`:** `sparekey setup`을 다시 실행하고 요청 시 암호를 입력하세요.
- **`rate_limited`:** 최근 30초 안에 시도가 있었습니다. 반복해서 시도하지 마세요.

## 보안

설치 전에 [SECURITY.md](SECURITY.md)를 읽어 주세요. 요약하면 다음과 같습니다.

- **사용자 계정으로 실행되는 모든 프로세스가 helper에 잠금 해제를 요청할 수 있습니다.** Sparekey는 신뢰할 수 있는 개인 계정을 위한 도구이며, 이미 해당 사용자 권한으로 실행 중인 악성코드로부터 보호하지 않습니다.
- 기본 가림막은 에이전트가 작업하는 동안 실제 디스플레이를 가립니다. 스크린샷에는 가림막이 나타나지 않으며 에이전트는 그 아래의 앱을 계속 조작할 수 있습니다.
- helper는 강화된 런타임을 사용하며 네트워크가 아닌 비공개 로컬 소켓에서만 요청을 받습니다.
- 서명 키는 내보낼 수 없고, 이를 사용하도록 미리 신뢰된 앱도 없습니다. **Always Allow**를 클릭하면 이 상태가 바뀝니다.

취약점은 GitHub 보안 권고를 통해 비공개로 알려 주세요.

## 제거

```sh
sparekey uninstall
```

저장된 자격 증명, helper, LaunchAgent, 런타임 파일, Sparekey가 작성한 스킬 파일을 제거합니다. 다음 항목은 제거하지 않습니다.

- `sparekey local signing` ID(원하면 Keychain Access에서 삭제하세요)
- Accessibility 항목(시스템 설정에서 제거하세요)
- `~/.local/bin/sparekey` 링크

## 크레디트

잠금 화면과 상호 작용하는 방식은 Cindy의 [MacScreenUnlock.swift](https://github.com/makecindy/cindy/blob/main/packages/remote-credentials-native/Sources/CindyRemoteCredentials/MacScreenUnlock.swift)(Apache-2.0)에서 참고했습니다. Sparekey는 독립적으로 구현되었습니다. 설계 기록은 [docs/DESIGN.md](docs/DESIGN.md)에 있습니다.

## 라이선스

[MIT](LICENSE) © yoonpooh
