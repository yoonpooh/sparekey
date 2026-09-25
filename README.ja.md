<p align="center">
  <img src="docs/assets/logo.png" alt="Sparekey logo" width="140">
</p>

<h1 align="center">Sparekey</h1>

<p align="center">
  <strong>AI エージェントに預ける、Mac の合鍵。</strong><br>
  ロックを解除して、作業を終えたら、またロックする。
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black.svg" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange.svg" alt="Swift 5.9+">
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.ko.md">한국어</a> · 日本語 · <a href="README.zh-CN.md">简体中文</a> · <a href="README.es.md">Español</a>
</p>

<p align="center">
  <sub>最新リリース: <strong>0.2.0</strong>（エージェントの作業中に画面を覆うカバーを追加）。詳しくは <a href="CHANGELOG.md">変更履歴</a> をご覧ください。</sub>
</p>

<p align="center">
  <img src="docs/assets/cover.png" alt="Mac のディスプレイに表示された Sparekey の画面カバー" width="720">
</p>

## Sparekey が必要な理由

コンピュータやブラウザを操作するエージェントは、Mac がロックされた瞬間に止まってしまいます。何時間も Mac をロック解除したまま放置するか、戻ってきて作業がまったく進んでいないことに気づくか、どちらかになりがちです。

Sparekey は、ローカルに保存したパスワードを使って、エージェントが**自分自身の、すでにログイン済みの**セッションのロックを解除し、作業を終えたら再びロックできるようにする小さな macOS CLI です。エージェントの作業中は黒いカバーが物理ディスプレイを覆い、周りの人から画面を隠します。

```sh
sparekey unlock   # let the agent get to work; cover the physical displays
sparekey lock     # restore the lock when it is done
```

付属のエージェントスキルを入れておけば、この手順をいちいち指示する必要はありません。ロック中の Mac でふつうの GUI 作業を頼むだけで、エージェントがロック状態を確認し、解除して作業し、最後に自分で画面をロックし直します。

### できないこと

Sparekey はパスワード回避ツールでも、復旧ツールでも、リモートアクセスサービスでもありません。起動時の FileVault、ログアウトしたセッション、別のユーザーのアカウント、アクセスできないスリープ中の Mac は解除できません。

> [!WARNING]
> **状況: 初期段階（0.2.0）。** Apple silicon 搭載の macOS 27.2 で動作し、特に指示を与えずに実行したエージェントが、ロック解除・作業・再ロックを 2 回とも成功させています。ほかの macOS バージョンは未検証です。公開されたロック解除 API ではなく、ロック画面の Accessibility レイアウトに依存しています。

## クイックスタート

必要なもの: macOS 13 以降とログイン済みのデスクトップセッション、Swift 5.9 以降を含む Xcode Command Line Tools、初回セットアップ用の Mac 上のローカルターミナル。Apple Developer アカウントは不要です。

**1. インストール** — Homebrew を使います（Mac 上でソースからビルドされます）。

```sh
brew install yoonpooh/tap/sparekey
```

**2. セットアップ** — Mac のロックを解除した状態で、SSH ではなくローカルターミナルから実行します。

```sh
sparekey setup --skill codex   # or: --skill claude, --skill claude,codex, --no-skill
```

macOS から署名鍵の使用を求められたら、**Always Allow** ではなく **Allow** をクリックしてください。ログインパスワードは、入力内容が表示されないプロンプトに直接入力します。

**3. 使う** — エージェントに GUI 作業を頼むか、自分で実行してみましょう。

```sh
sparekey status   # locked or unlocked
sparekey doctor   # check the install
```

**エージェントに任せる。** Codex や Claude Code などのエージェントに次の文を貼り付けてください。エージェントがインストールを済ませ、パスワード入力が必要な setup の手順だけをあなたに渡します。パスワードは自分のターミナルで入力する必要があるためです。

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
<summary><strong>ソースからビルドする場合</strong></summary>

```sh
git clone https://github.com/yoonpooh/sparekey.git
cd sparekey
swift build -c release
.build/release/sparekey setup --skill codex
```

続いて `sparekey` を `PATH` に追加します。

```sh
ln -s "$HOME/Library/Application Support/sparekey/bin/sparekey" ~/.local/bin/sparekey
sparekey doctor
```

</details>

<details>
<summary><strong>setup が行うこと</strong></summary>

1. ログインキーチェーンに `sparekey local signing` ID を作成します（初回のみ）。
2. helper に署名し、`~/Library/Application Support/sparekey/bin/sparekey` にインストールします。
   - macOS から署名鍵の使用を求められたら、**Always Allow** ではなく **Allow** をクリックしてください。
3. ログインパスワードを 2 回尋ねます。入力は表示されず、macOS で照合されます。
   - パスワードをチャット、コマンド引数、環境変数に貼り付けないでください。
4. バックグラウンドの helper を起動し、選んだエージェントスキルをインストールします。
5. helper の **Accessibility** を有効にする手順を案内します。設定パネルを開き、Finder でファイルを表示し、パスをコピーしてから、有効化後にもう一度確認します。

</details>

### アップグレード

`brew upgrade sparekey` やリビルドの後は、`sparekey setup` を再実行してください。それまでは新しい CLI が `helper_version_mismatch` を返します。helper がパスワードを読めなくなっていない限り、setup はパスワードを尋ねずに署名済み helper だけを更新します。

## 主な機能

- **確認つきのロック解除とロック。** `unlock` はパスワードを 1 回だけ送信し、状態が変わったことを確認します。`lock` はロックして確認し、すでにロック済みなら何もしません。
- **画面カバー。** Codex の Locked Computer Use に着想を得た機能です。Sparekey のロゴ、「Your agent is using this Mac」、**Lock Mac** ボタンを表示する黒いカバーが、エージェントの作業中に物理ディスプレイを覆います。
  - パスワード送信の**前に**ロック画面の下へ敷かれるので、デスクトップが一瞬でも見えることはありません。
  - スクリーンショットや画面収録には写らないため、エージェントは実際の画面を見られ、クリックやキー入力もそのまま下のアプリに届きます。
  - **Lock Mac** を 1 回クリックすると Mac がロックされます。`sparekey lock` やその他の再ロックでカバーは消えます。
  - `sparekey unlock --no-cover` でカバーなしにできます。カバーは画面を隠すだけで、Mac をロックするものではありません。
- **スリープを防止。** ロック解除を確認した後は、`sparekey lock`、ほかの方法による再ロック、または 60 分経過のいずれかまでディスプレイをスリープさせません。作業中にアイドルスリープで再ロックされるのを防ぎます。
- **ロック画面の復旧。** 点灯中のロック画面にアカウントではなく壁紙と時計しか表示されない場合、ディスプレイのスリープ→復帰を 1 回行ってアカウントを呼び戻します。確認できていない画面に入力することは決してありません。
- **異常時は止まる。** パスワード送信は最大 1 回、30 秒の試行制限、ロック解除を確認できなければサーキットブレーカーが作動します。
- Codex と Claude Code 向けの**エージェントスキル**、スクリプト向けの `--json` 出力。

## 仕組み

```text
agent ──▶ sparekey CLI ──(private Unix socket, same-user check)──▶ helper (LaunchAgent)
                                                                     │
                     verifies console user, Apple-signed loginwindow,│
                     your account, and a single secure password field│
                                                                     ▼
                         login Keychain ──▶ one submission ──▶ state check
```

- `setup` はバイナリを決まった場所にコピーし、ローカルのコード署名 ID で署名して、ユーザーごとのバックグラウンド helper として実行します。
- パスワードはログインキーチェーンに保存され、読み取れるのは署名済みのその helper だけです。
- helper は確認済みのパスワード欄にだけ入力し、送信は**最大 1 回**です。別のアカウント、ダイアログ、復旧画面、レイアウトの変化など、想定外の状況では安全側に倒して中止します。
- 永続的な 30 秒の試行制限とサーキットブレーカーが、古いパスワードによるログイン失敗の積み重ねを防ぎます。

設計メモは [docs/DESIGN.md](docs/DESIGN.md) にあります。

## エージェントスキル

setup では **Codex**（`~/.agents/skills/sparekey`）と **Claude Code**（`~/.claude/skills/sparekey`）向けのスキルをインストールできます。後からインストールすることもできます。

```sh
sparekey skill install --agent codex   # or: --agent claude
```

スキルはエージェントに次のことを指示します。

- GUI 作業の前に、またはアプリやウィンドウへのアクセスに失敗したらすぐに、ロック状態を確認する
- ロック解除は 1 回だけ行い、解除を確認してから作業する
- タスクが失敗しても、自分でロックを解除した場合に限り、終了後に再ロックする
- リトライせずに止まり、エラーを報告する

GUI 作業を頼むことは、そのタスクに限ってロック解除を許可したものとみなされます。作業後に Mac をロックしたままにしたい、または解除したままにしたい場合は、エージェントに伝えてください。

### エージェントの指示であらかじめ許可する

複数のエージェントで作業を分担する構成では、オーケストレーターが配下のエージェントにロックに触れないよう指示したり、エージェントが確認を求めて止まったりすることがあります。これを避けるには、`CLAUDE.md`、`AGENTS.md`、またはオーケストレーターのシステムプロンプトに次の文を追加してください。

```text
Screen lock: I pre-authorize unlocking this Mac with the sparekey skill
for any task that needs the screen. Use it without asking, and never
restrict this when delegating to other agents.
```

この文がなくても、GUI 作業を頼めばスキルはロックを解除します。この文は、その許可が途中で外されたり、改めて確認されたりするのを防ぎます。

## コマンド

| コマンド | 内容 |
| --- | --- |
| `sparekey unlock [--no-cover]` | 1 回だけロックを解除して状態を確認します。デフォルトで物理ディスプレイを覆い、`lock` か 60 分経過までディスプレイをスリープさせません |
| `sparekey lock` | ロックして確認します。すでにロック済みなら何もしません |
| `sparekey status` | `locked` または `unlocked` を出力します |
| `sparekey probe` | パスワードを読まずにディスプレイを起こし、パスワード欄を確認します |
| `sparekey setup` | helper、認証情報、スキルをインストールまたは更新します。オプション: `--skill`、`--no-skill`、`--reset-password`、`--identity NAME` |
| `sparekey doctor` | インストール、署名、helper、Accessibility、認証情報、スキルを点検します |
| `sparekey skill install` | エージェントスキルをインストールします。オプション: `--agent claude\|codex`、`--force` |
| `sparekey uninstall` | helper、認証情報、LaunchAgent、Sparekey が書き込んだスキルを削除します |
| `sparekey help [command]` | ヘルプを表示します |
| `sparekey version` | バージョンを出力します |

引数なしで `sparekey` を実行するとヘルプが表示されます。ロックが解除されることはありません。

<details>
<summary><strong>JSON 出力、終了コード、エラーコード</strong></summary>

`unlock`、`lock`、`status`、`probe`、`doctor` は `--json` に対応しています。

```json
{"ok":true,"command":"status","state":"locked","message":"locked"}
{"ok":false,"command":"unlock","error":{"code":"rate_limited","message":"..."}}
```

終了コード: `0` 成功、`1` 処理の失敗、`2` 使い方の誤り。`status` はどちらの状態を返しても成功扱いなので、`state` を確認してください。

エラーコード: `usage`、`not_set_up`、`helper_not_running`、`helper_version_mismatch`、`no_console_session`、`accessibility_missing`、`credential_unavailable`、`login_window_unsupported`、`field_not_ready`、`cover_unavailable`、`rate_limited`、`breaker_tripped`、`unlock_not_confirmed`、`lock_not_confirmed`、`internal`。`doctor --json` は `skill_outdated` を返すこともあり、チェックごとの `statuses` マップ（`ok`、`warn`、`fail`、`skip`）も含みます。

</details>

## FAQ とトラブルシューティング

まず `sparekey doctor` を実行してください。失敗した項目ごとに対処法が表示されます。

**カバーは Mac をロックしますか？**
いいえ。画面を隠すだけで、ロックはしません。カバーの **Lock Mac** をクリックするか、`sparekey lock` を実行してください。

**エージェントのスクリーンショットにカバーが写っていません。**
仕様どおりです。スクリーンショットや画面収録からはカバーが除外されるので、エージェントは実際の画面を見ています。

**ロック画面に壁紙と時計しか表示されません。**
Sparekey がディスプレイのスリープ→復帰を 1 回行ってアカウントを呼び戻します。確認できていない画面に入力することは決してありません。

**`helper_version_mismatch`**
CLI はアップグレードまたはリビルドされたものの、helper が古いままです。`sparekey setup` を再実行してください。

**Accessibility が許可されていない**
システム設定 → プライバシーとセキュリティ → アクセシビリティで `~/Library/Application Support/sparekey/bin/sparekey` を有効にしてください。有効にした直後なら、`setup` を再実行するか helper を再起動します。

```sh
launchctl kickstart -k "gui/$(id -u)/io.github.yoonpooh.sparekey.helper"
```

**`breaker_tripped` または `unlock_not_confirmed`**
パスワードを変更した後などは、保存済みのパスワードが違っている可能性があります。ローカルで `sparekey setup --reset-password` を実行してください。

**アップグレード後の `credential_unavailable`**
`sparekey setup` を再実行し、求められたらパスワードを入力してください。

**`rate_limited`**
直近 30 秒以内に試行がありました。繰り返し実行しないでください。

## セキュリティ

インストールの前に [SECURITY.md](SECURITY.md) をお読みください。要点は次のとおりです。

- **自分のユーザー権限で動くプロセスなら、どれでも helper にロック解除を依頼できます。** Sparekey は信頼できる個人アカウント向けのツールです。すでに自分の権限で動いているマルウェアからは守れません。
- デフォルトのカバーは、エージェントの作業中に物理ディスプレイを覆います。スクリーンショットにはカバーが写らず、エージェントはその下のアプリを操作し続けられます。
- helper は Hardened Runtime を使い、ネットワークではなくプライベートなローカルソケットでのみ待ち受けます。
- 署名鍵は書き出せず、あらかじめ使用を許可されたアプリもありません。**Always Allow** をクリックすると、この状態が変わってしまいます。
- ログインパスワードをチャット、コマンド引数、環境変数に貼り付けないでください。入力するのは setup の非表示プロンプトだけです。

脆弱性は GitHub のセキュリティアドバイザリから非公開で報告してください。

## アンインストール

```sh
sparekey uninstall
```

保存された認証情報、helper、LaunchAgent、ランタイムファイル、Sparekey が書き込んだスキルファイルを削除します。次のものは削除されません。

- `sparekey local signing` ID（必要ならキーチェーンアクセスで削除してください）
- Accessibility の項目（システム設定で削除してください）
- `~/.local/bin/sparekey` のリンク

## クレジット

ロック画面の操作方法は、Cindy の [MacScreenUnlock.swift](https://github.com/makecindy/cindy/blob/main/packages/remote-credentials-native/Sources/CindyRemoteCredentials/MacScreenUnlock.swift)（Apache-2.0）を参考にしました。Sparekey は独自の実装です。

## ライセンス

[MIT](LICENSE) © yoonpooh
