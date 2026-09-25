<p align="center">
  <img src="docs/assets/logo.png" alt="Sparekey logo" width="160">
</p>

<h1 align="center">Sparekey</h1>

<p align="center">
  <strong>AI エージェントのための、Mac の予備の鍵。</strong><br>
  画面のロックを解除し、作業を終えたら、再びロックします。
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black.svg" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange.svg" alt="Swift 5.9+">
</p>

[English](README.md) · [한국어](README.ko.md) · 日本語 · [简体中文](README.zh-CN.md) · [Español](README.es.md)

---

Mac がロックされると、コンピュータやブラウザを操作するエージェントも作業を続けられません。Sparekey は、Mac にローカル保存したパスワードを使って、エージェントが**自分の、すでにログイン済みの**セッションのロックを解除し、作業後に再びロックできる小さな macOS CLI です。

```sh
sparekey unlock   # let the agent get to work; cover the physical displays
sparekey lock     # restore the lock when it is done
```

付属のエージェントスキルを使えば、この手順を逐一指示する必要はありません。ロック中の Mac で通常の GUI 作業を頼むと、エージェントがロック状態を確認し、解除して作業を進め、最後に自分で画面を再ロックします。

> **状況:** 初期段階（0.1）。Apple silicon 搭載の macOS 27.2 では、明示的な指示なしにエージェントがロック解除、作業、再ロックまで行う動作を 2 回確認しました。ほかの macOS バージョンは未検証です。公開されたロック解除 API ではなく、ロック画面の Accessibility レイアウトに依存します。

## 対象外の用途

Sparekey はパスワード回避ツール、復旧ツール、リモートアクセスサービスではありません。起動時の FileVault、ログアウトしたセッション、別のユーザーのアカウント、アクセスできないスリープ中の Mac は解除できません。

## 仕組み

```text
agent ──▶ sparekey CLI ──(private Unix socket, same-user check)──▶ helper (LaunchAgent)
                                                                     │
                     verifies console user, Apple-signed loginwindow,│
                     your account, and a single secure password field│
                                                                     ▼
                         login Keychain ──▶ one submission ──▶ state check
```

- `setup` はバイナリを固定の場所にコピーし、ローカルのコード署名 ID で署名して、ユーザーごとのバックグラウンド helper として起動します。
- パスワードはログイン Keychain に保存されます。読み取れるのは、その署名済み helper だけです。
- helper は検証済みのパスワード欄一つだけに入力し、送信は**最大 1 回**です。別のアカウント、ダイアログ、復旧画面、レイアウト変更など、想定外の状態では安全側に停止します。
- パスワード送信前に、ロック画面の下へ黒いカバーを配置します。解除後は物理ディスプレイを覆いますが、スクリーンショットには映りません。エージェントのクリックや入力はカバーを通過します。カバーの Lock Mac ボタンを 1 回押すと画面をロックできます。省略するには `sparekey unlock --no-cover` を使います。
- 状態が保持される 30 秒の試行制限と遮断機構により、古いパスワードでログイン失敗が積み重なるのを防ぎます。

## 動作要件

- macOS 13 以降と、ログイン済みのデスクトップセッション
- Swift 5.9 以降を含む Xcode Command Line Tools
- 初期設定に使う Mac 上のローカルターミナル

Apple Developer アカウントは不要です。

## インストール

Homebrew を使う場合（Mac 上でソースからビルド）:

```sh
brew install yoonpooh/tap/sparekey
sparekey setup --skill codex   # or: --skill claude, --skill claude,codex, --no-skill
```

自分でビルドする場合:

```sh
git clone https://github.com/yoonpooh/sparekey.git
cd sparekey
swift build -c release
.build/release/sparekey setup --skill codex
```

Mac のロックを解除した状態で、SSH ではなくローカルターミナルから setup を実行してください。次の処理を行います。

1. ログイン Keychain に `sparekey local signing` ID を作成します（初回のみ）。
2. helper に署名し、`~/Library/Application Support/sparekey/bin/sparekey` にインストールします。
   - macOS が署名鍵の使用を尋ねたら、**Always Allow** ではなく **Allow** をクリックしてください。
3. ログインパスワードを 2 回求めます。入力は表示されず、macOS で照合されます。
   - チャット、コマンド引数、環境変数にパスワードを貼り付けないでください。
4. バックグラウンド helper を起動し、選択したエージェントスキルをインストールします。
5. helper の **Accessibility** を有効にする手順を案内します。設定画面を開き、Finder にファイルを表示してパスをコピーし、有効化後に再確認します。

ソースからビルドした場合は、`sparekey` を `PATH` に追加してください。

```sh
ln -s "$HOME/Library/Application Support/sparekey/bin/sparekey" ~/.local/bin/sparekey
sparekey doctor
```

`brew upgrade sparekey` または再ビルドの後は、`sparekey setup` を再実行してください。helper がパスワードを読めなくなった場合を除き、パスワードを聞き直さずに署名済み helper を更新します。

## エージェントスキル

setup では **Codex**（`~/.agents/skills/sparekey`）と **Claude Code**（`~/.claude/skills/sparekey`）向けのスキルをインストールできます。後からのインストールも可能です。

```sh
sparekey skill install --agent codex
```

スキルはエージェントに次のように指示します。

- GUI 作業の前、またはアプリやウィンドウにアクセスできなくなった時点で、ロック状態を確認する。
- 1 回だけロックを解除し、解除を確認してから作業する。
- 作業に失敗した場合も、自分が解除したときに限って作業後に再ロックする。
- 再試行せず、エラーを報告する。

GUI 作業の依頼は、その作業のためにロックを解除する許可とみなされます。作業後に Mac をロックしたまま、または解除したままにしたい場合は、エージェントに伝えてください。

## コマンド

| コマンド | 動作 |
| --- | --- |
| `sparekey unlock [--no-cover]` | 1 回ロックを解除して状態を確認します。既定では物理ディスプレイを覆い、`lock` の実行または 60 分の経過までディスプレイをスリープさせません。 |
| `sparekey lock` | ロックして確認します。すでにロック中なら何もしません。 |
| `sparekey status` | `locked` または `unlocked` を出力します。 |
| `sparekey probe` | パスワードを読まずにディスプレイを起こし、パスワード欄を確認します。 |
| `sparekey setup` | helper、認証情報、スキルをインストールまたは更新します。 |
| `sparekey doctor` | インストール、署名、helper、Accessibility、認証情報、スキルを検査します。 |
| `sparekey skill install` | エージェントスキルをインストールします。 |
| `sparekey uninstall` | helper、認証情報、LaunchAgent、Sparekey が書き込んだスキルを削除します。 |

引数なしで `sparekey` を実行するとヘルプを表示し、ロックは解除しません。

<details>
<summary><strong>JSON 出力、終了コード、エラーコード</strong></summary>

`unlock`、`lock`、`status`、`probe`、`doctor` は `--json` に対応しています。

```json
{"ok":true,"command":"status","state":"locked","message":"locked"}
{"ok":false,"command":"unlock","error":{"code":"rate_limited","message":"..."}}
```

終了コードは成功が `0`、処理の失敗が `1`、使い方の誤りが `2` です。`status` はどちらの状態でも成功し得るため、`state` を確認してください。

エラーコード: `usage`、`not_set_up`、`helper_not_running`、`helper_version_mismatch`、`no_console_session`、`accessibility_missing`、`credential_unavailable`、`login_window_unsupported`、`field_not_ready`、`cover_unavailable`、`rate_limited`、`breaker_tripped`、`unlock_not_confirmed`、`lock_not_confirmed`、`internal`。`doctor --json` は `skill_outdated` も報告する場合があり、項目ごとの `statuses` マップ（`ok`、`warn`、`fail`、`skip`）も追加します。

</details>

## トラブルシューティング

まず `sparekey doctor` を実行してください。失敗した各項目に対処方法が表示されます。

- **Accessibility がない:** システム設定 → プライバシーとセキュリティ → アクセシビリティで `~/Library/Application Support/sparekey/bin/sparekey` を許可してください。許可した直後なら `setup` を再実行するか、`launchctl kickstart -k "gui/$(id -u)/io.github.yoonpooh.sparekey.helper"` で helper を再起動してください。
- **`breaker_tripped` または `unlock_not_confirmed`:** パスワードの変更後などは、保存済みのパスワードが違う可能性があります。ローカルで `sparekey setup --reset-password` を実行してください。
- **更新後の `credential_unavailable`:** `sparekey setup` を再実行し、求められたらパスワードを入力してください。
- **`rate_limited`:** 過去 30 秒以内に試行がありました。繰り返し実行しないでください。

## セキュリティ

インストール前に [SECURITY.md](SECURITY.md) をお読みください。要点は次のとおりです。

- **あなたのユーザー権限で動くプロセスは、どれでも helper にロック解除を依頼できます。** Sparekey は信頼できる個人アカウント向けです。すでに同じ権限で動いているマルウェアからは保護できません。
- 既定のカバーはエージェントの作業中、物理ディスプレイを隠します。スクリーンショットにカバーは映らず、エージェントは下のアプリを操作できます。
- helper は強化されたランタイムを使い、ネットワークではなく非公開のローカルソケットだけで待ち受けます。
- 署名鍵は書き出せず、使用を事前に信頼されたアプリもありません。**Always Allow** をクリックすると、この状態が変わります。

脆弱性は GitHub のセキュリティアドバイザリから非公開で報告してください。

## アンインストール

```sh
sparekey uninstall
```

保存済みの認証情報、helper、LaunchAgent、実行時ファイル、Sparekey が書き込んだスキルファイルを削除します。次は削除しません。

- `sparekey local signing` ID（必要なら Keychain Access で削除）
- Accessibility の登録（システム設定で削除）
- `~/.local/bin/sparekey` リンク

## クレジット

ロック画面の操作方法は、Cindy の [MacScreenUnlock.swift](https://github.com/makecindy/cindy/blob/main/packages/remote-credentials-native/Sources/CindyRemoteCredentials/MacScreenUnlock.swift)（Apache-2.0）を参考にしました。Sparekey は独立した実装です。設計メモは [docs/DESIGN.md](docs/DESIGN.md) にあります。

## ライセンス

[MIT](LICENSE) © yoonpooh
