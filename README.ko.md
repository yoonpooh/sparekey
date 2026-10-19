# Sparekey

AI 에이전트가 로그인된 본인 Mac 세션의 잠금을 풀고 작업 후 다시 잠그도록 돕는 macOS CLI입니다.

[![MIT 라이선스](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.md) · 한국어 · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Español](README.es.md)

![Mac 디스플레이의 Sparekey 가림막](docs/assets/cover.png)

## 주요 기능

- 로그인 Keychain에 저장한 암호로 본인의 로그인된 세션을 잠금 해제합니다.
- 콘솔 계정과 보안 암호 입력란을 확인하고 시도당 최대 한 번만 암호를 제출합니다.
- 기본 가림막으로 실제 디스플레이를 가립니다. 에이전트는 가림막 아래 앱을 조작하고 화면을 캡처할 수 있습니다.
- 최대 60분 동안 화면 잠자기를 억제합니다. 재잠금이나 인증된 사용자 인계 시 유지가 끝납니다.
- 작업별 재잠금 토큰, Codex·Claude Code 스킬, JSON 출력을 제공합니다.

잠금 화면의 Accessibility 레이아웃에 의존합니다. 패키지의 macOS 13 이상 배포 대상 설정이 모든 macOS 버전에서의 실제 동작을 보장하지는 않습니다.

## 요구 사항

- macOS 13 이상과 이미 로그인된 본인의 데스크톱 세션.
- 소스 빌드용 Swift 5.9 이상의 Xcode Command Line Tools. Homebrew formula도 소스에서 빌드합니다.
- 잠금 해제된 Mac의 로컬 대화형 터미널. setup과 uninstall은 일반 사용자로 실행하며 `sudo`를 사용하지 않습니다.
- 설치된 helper의 손쉬운 사용 권한과 로그인 Keychain 접근.
- Homebrew 방식으로 설치한다면 Homebrew.

Apple Developer 계정은 필요 없습니다. 시동 시 FileVault 잠금, 로그아웃된 세션, 다른 계정은 열 수 없으며 원격 접속 기능도 제공하지 않습니다.

## 설치

Homebrew로 설치합니다.

```sh
brew install yoonpooh/tap/sparekey
```

소스에서 빌드하려면 다음을 실행합니다.

```sh
git clone https://github.com/yoonpooh/sparekey.git
cd sparekey
swift build -c release
.build/release/sparekey setup --skill codex
```

소스 설치 후 helper를 `PATH`에 추가하는 방법과 formula 템플릿의 제약은 [영문 설치 안내](README.md#installation)를 참고하세요.
저장소의 formula에는 릴리스 체크섬 자리표시자가 있으므로 해당 파일을 직접 릴리스 formula로 설치하지 마세요.

## 빠른 시작과 사용법

Homebrew 설치 후, 잠금 해제된 Mac의 본인 로컬 터미널에서 설정합니다.

```sh
sparekey setup --skill codex
```

`--skill claude`, `--skill claude,codex`, `--no-skill`도 선택할 수 있습니다. 선택 옵션을 생략하면 설치할 스킬을 묻습니다.
setup은 로컬 서명 ID를 만들거나 재사용하고, helper를 서명하고, 필요하면 로그인 암호를 저장한 뒤 사용자별 LaunchAgent를 시작합니다.
암호는 터미널의 숨김 입력란에만 입력하세요. 서명 키 사용을 묻는 macOS 창에서는 **Always Allow** 대신 **Allow**를 선택하고, helper의 손쉬운 사용 권한 안내를 따르세요.

```sh
sparekey doctor
sparekey status --json
```

설치나 스킬 갱신 후에는 에이전트의 새 대화를 시작하세요. 스킬이 상태 확인, probe, 잠금 해제, 작업 후 정리를 안내합니다.
직접 잠긴 Mac에서 작업할 때는 다음 순서로 결과를 확인합니다.

```sh
sparekey probe --json
sparekey unlock --json
```

`probe`는 화면을 깨우고 암호 입력란을 확인하지만 암호를 읽거나 제출하지 않습니다.
암호 유예 시간에 화면이 깨어나 `unlocked`와 `lockToken`을 반환하면 그 토큰을 보관하고 `unlock`은 생략합니다.
그 외에는 성공한 `unlock`의 토큰을 사용합니다. 작업이 반환받은 토큰만 정리에 사용하세요.

```sh
sparekey lock --lock-token "$TASK_LOCK_TOKEN" --json
```

`TASK_LOCK_TOKEN`은 반환된 토큰을 담는 예시 셸 변수이며 Sparekey 설정 변수가 아닙니다.
처음부터 잠금 해제된 세션에 새 재잠금 권한이 생기지는 않습니다. `relock_revoked`면 현재 상태를 유지하고, 정리 목적으로 `--force`를 사용하지 마세요.

## 설정

사용자 설정 파일 대신 CLI 옵션을 사용합니다. 경로 전체는 [영문 설정 안내](README.md#configuration)에 있습니다.

- helper는 `~/Library/Application Support/sparekey/bin/sparekey`에 설치됩니다.
- Codex 스킬은 `~/.agents/skills/sparekey/SKILL.md`, Claude Code 스킬은 `~/.claude/skills/sparekey/SKILL.md`에 설치됩니다.
- `setup --identity NAME`으로 기존 코드 서명 ID를 선택하고 `setup --reset-password`로 저장 암호를 바꿉니다.
- `unlock --no-cover`는 해당 잠금 해제의 기본 가림막을 생략합니다.
- 나중에 `sparekey skill install --agent codex` 또는 `--agent claude`로 스킬을 설치할 수 있습니다.

수정된 스킬은 확인 또는 `skill install --force`로 교체하며 `SKILL.md.bak`에 백업합니다. 기존 백업은 덮어쓰지 않습니다.
이전 Sparekey 플러그인 마이그레이션에만 Codex CLI가 필요하며, 제거를 확인한 뒤 스킬을 씁니다. 신규 설치에는 Codex CLI가 필요 없습니다.

업그레이드나 재빌드 후에는 로컬에서 `sparekey setup`으로 helper와 스킬을 갱신하세요. 저장 암호를 계속 읽을 수 있으면 재사용합니다.
로컬 대화형 터미널에서 `sparekey uninstall`을 실행하면 관리되는 설치와 내용이 일치하는 스킬을 제거합니다.
서명 ID, 손쉬운 사용 항목, 수정된 스킬, 직접 만든 심볼릭 링크와 Homebrew CLI는 별도로 제거해야 합니다.

## CLI 참조

```sh
sparekey --help
sparekey help unlock
sparekey --version
```

[CLI 참조](docs/CLI.md)에 공개 명령의 실제 옵션, JSON 필드, 종료 코드, 토큰 규칙을 모았습니다. 인수 없이 실행하면 도움말이 나옵니다.
`--json`은 `unlock`, `lock`, `status`, `probe`, `doctor`에서 지원합니다. 종료 코드는 성공 `0`, 작업 실패 `1`, 사용법 오류 `2`입니다.

## 동작 방식

CLI가 비공개 Unix 소켓으로 사용자별 서명 helper에 요청을 보냅니다. 양쪽에서 상대 사용자 ID를 확인합니다.
helper는 콘솔 세션, Apple 서명의 `loginwindow`, 계정 표시와 암호 입력란을 검증한 뒤 로그인 Keychain의 암호를 사용합니다.
30초 시도 제한과 확인되지 않은 제출 후 차단기가 반복 실패를 제한합니다.

기본 가림막은 암호 제출 전에 잠금 화면 아래에 배치됩니다. **Unlock Mac**에서 macOS 인증을 완료하면 가림막을 해제하고 작업의 재잠금 권한을 취소합니다.
시스템 잠금 이벤트, 화면 유지 종료, helper 재시작도 토큰을 무효화합니다. 60분 제한은 화면 유지 종료이며 자동 잠금 예약이 아닙니다.
[설계 문서](docs/DESIGN.md)와 [에이전트 스킬](skills/sparekey/SKILL.md)에 세부 흐름이 있습니다.

## 보안 주의 사항

설치 전에 [보안 정책](SECURITY.md)을 읽으세요.

- 같은 사용자 권한의 모든 프로세스가 helper에 잠금 해제를 요청할 수 있습니다. 신뢰할 수 있는 개인 계정에서 사용하세요.
- 가림막은 화면을 숨길 뿐 Mac을 잠그거나 보지 않고 하는 물리 입력을 막지 않습니다. 캡처에는 가림막이 빠집니다.
- helper는 네트워크가 아닌 로컬 소켓을 사용합니다. 이미 본인 권한으로 실행 중인 악성코드를 막지는 못합니다.
- 암호를 채팅, 명령 인수, 환경 변수, 문서에 넣지 마세요. 작업 토큰도 로그나 보고서에 저장하지 마세요.
- 실패한 잠금 해제를 반복하거나 계정·입력란 검증을 우회하지 마세요. 취약점은 보안 정책에 따라 비공개로 보고하세요.

## 문제 해결

먼저 `sparekey doctor`를 확인하세요. 설치 점검 성공이 실제 잠금 화면 검증이나 잠금 해제 성공을 뜻하지는 않습니다.

| 오류 | 조치 |
| --- | --- |
| `not_set_up`, `helper_not_running`, `helper_version_mismatch` | 로컬 터미널에서 `sparekey setup`을 실행합니다. |
| `accessibility_missing` | 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 helper를 허용하고 setup을 다시 실행합니다. |
| `credential_unavailable` | setup을 다시 실행하고 요청하면 암호를 입력합니다. |
| `breaker_tripped`, `unlock_not_confirmed` | 시도를 멈춥니다. 암호가 바뀌었다면 로컬에서 `sparekey setup --reset-password`를 실행합니다. |
| `rate_limited` | 30초 이내의 시도가 제한됩니다. 반복 실행하지 않습니다. |
| `login_account_mismatch`, `login_window_unsupported`, `field_not_ready` | 오류와 현재 잠금 화면을 확인합니다. 검증되지 않은 입력란에는 입력하지 않습니다. |
| `relock_revoked` | 현재 상태를 유지합니다. `--force`로 우회하지 않습니다. |
| `display_sleep_not_confirmed` | 잠금은 성공했을 수 있습니다. 추가 동작 전에 `status`를 확인합니다. |

남아 있는 응용 프로그램 강제 종료 창도 지원하지 않는 화면으로 판정될 수 있습니다. 제한된 복구 절차는 [스킬](skills/sparekey/SKILL.md)을 참고하세요. probe 실패는 암호 제출을 뜻하지 않습니다.

## 개발

저장소 루트에서 실행합니다.

```sh
swift build
swift test
swift build -c release
python3 scripts/embed-agent-assets.py --check
```

`Package.swift`는 실행 파일, `SparekeyCore` 타깃, core·transport 테스트를 정의합니다. 에셋 검사는 스킬 원본과 생성된 Swift 파일의 일치 여부를 확인합니다.
[Shimmer 렌더러](scripts/render-shimmer/README.md)는 helper 조작 없이 이미지를 만듭니다.
[로컬 서명 실험](scripts/spike/README.md)은 Keychain과 LaunchAgent를 변경하므로 의도적으로 실행해야 합니다.
릴리스 기록은 [변경 기록](CHANGELOG.md)에 있습니다. 잠금 화면 접근 방식은 [Cindy](https://github.com/makecindy/cindy)를 참고했으며 Sparekey는 독립 구현입니다.

## 라이선스

[MIT](LICENSE), 저작권자 yoonpooh.
