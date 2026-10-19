# Sparekey

AI エージェントがログイン済みの自分の Mac をロック解除し、作業後に再ロックするための macOS CLI です。

[![MIT ライセンス](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.md) · [한국어](README.ko.md) · 日本語 · [简体中文](README.zh-CN.md) · [Español](README.es.md)

![Mac ディスプレイの Sparekey カバー](docs/assets/cover.png)

## 主な機能

- ログインキーチェーンのパスワードで自分のセッションをロック解除します。
- コンソールアカウントと安全なパスワード欄を検証し、試行ごとに最大 1 回だけ送信します。
- デフォルトのカバーで物理ディスプレイを隠します。エージェントは下のアプリを操作・キャプチャできます。
- 最大 60 分間ディスプレイのスリープを抑止し、再ロックや認証済みの引き継ぎで解除します。
- タスク用の再ロックトークン、Codex と Claude Code のスキル、JSON 出力を提供します。

ロック画面の Accessibility レイアウトに依存します。macOS 13 以降というパッケージの配布対象は、すべての OS バージョンでの動作保証ではありません。

## 必要なもの

- macOS 13 以降と、ログイン済みの自分のデスクトップセッション。
- ソースビルド用の Swift 5.9 以降を含む Xcode Command Line Tools。Homebrew formula もソースをビルドします。
- ロック解除済みの Mac のローカル対話型ターミナル。setup と uninstall は通常のユーザーで、`sudo` を使わずに実行します。
- インストールした helper のアクセシビリティ権限と、ログインキーチェーンへのアクセス。
- Homebrew でインストールする場合は Homebrew。

Apple Developer アカウントは不要です。起動時の FileVault、ログアウト済みのセッション、別のアカウントは解除できません。リモートアクセス機能もありません。

## インストール

```sh
brew install yoonpooh/tap/sparekey
```

ソースからビルドする場合は次を実行します。

```sh
git clone https://github.com/yoonpooh/sparekey.git
cd sparekey
swift build -c release
.build/release/sparekey setup --skill codex
```

ソース版の `PATH` 設定は[英語のインストール手順](README.md#installation)を参照してください。
リポジトリ内の formula はチェックサムが未設定のテンプレートなので、そのファイルを直接リリース用 formula としてインストールしないでください。

## クイックスタートと使い方

Homebrew でのインストール後、自分の Mac のローカルターミナルで設定します。

```sh
sparekey setup --skill codex
```

`--skill claude`、`--skill claude,codex`、`--no-skill` も選べます。選択を省略すると対話形式で尋ねます。
setup はローカル署名 ID を作成または再利用し、helper に署名して、必要に応じてパスワードを保存し、ユーザー別 LaunchAgent を起動します。
パスワードは非表示の入力欄にだけ入力してください。署名鍵の確認では **Always Allow** ではなく **Allow** を選び、helper のアクセシビリティ設定に従ってください。

```sh
sparekey doctor
sparekey status --json
```

スキルのインストールや更新後は新しいエージェントの会話を開始してください。スキルが状態確認、probe、解除、終了時の処理を案内します。
手動でロック中の Mac を使う場合は、各コマンドの結果を確認してから進みます。

```sh
sparekey probe --json
sparekey unlock --json
```

`probe` は画面を起こしてパスワード欄を確認しますが、パスワードを読み取りも送信もしません。
パスワード猶予期間中の復帰で `unlocked` と `lockToken` が返った場合、そのトークンを保持し `unlock` を省略します。
それ以外は成功した `unlock` のトークンを保持します。終了時にはタスクが受け取った値を使います。

```sh
sparekey lock --lock-token "$TASK_LOCK_TOKEN" --json
```

`TASK_LOCK_TOKEN` は返されたトークンを格納する例示用のシェル変数で、Sparekey の設定ではありません。
最初から解除済みのセッションに新しい再ロック権限は付与されません。`relock_revoked` では状態を維持し、終了処理で `--force` を使わないでください。

## 設定

ユーザー設定ファイルではなく CLI オプションで設定します。全パスは[英語の設定一覧](README.md#configuration)を参照してください。

- helper は `~/Library/Application Support/sparekey/bin/sparekey` にあります。
- Codex スキルは `~/.agents/skills/sparekey/SKILL.md`、Claude Code スキルは `~/.claude/skills/sparekey/SKILL.md` にあります。
- `setup --identity NAME` で既存の署名 ID を、`setup --reset-password` で保存パスワードの更新を指定します。
- `unlock --no-cover` はその解除時のカバーを省略します。
- `sparekey skill install --agent codex` または `--agent claude` で後からスキルを追加できます。

変更済みスキルは確認または `skill install --force` で置き換え、`SKILL.md.bak` に保存します。既存バックアップは上書きしません。
旧 Sparekey プラグインからの移行時のみ Codex CLI が必要です。削除を確認してからスキルを書き込みます。

アップグレードや再ビルド後はローカルで `sparekey setup` を実行し、helper とスキルを更新します。読み取り可能な保存パスワードは再利用します。
ローカル対話型ターミナルで `sparekey uninstall` を実行すると、管理対象のインストールと内容が一致するスキルを削除します。
署名 ID、アクセシビリティ項目、変更済みスキル、自分で作ったリンク、Homebrew の CLI は別途削除します。

## CLI リファレンス

```sh
sparekey --help
sparekey help unlock
sparekey --version
```

公開コマンドの構文、オプション、JSON、終了コードは [CLI リファレンス](docs/CLI.md)にまとめています。引数なしではヘルプを表示します。
`--json` は `unlock`、`lock`、`status`、`probe`、`doctor` で使用できます。終了コードは成功 `0`、処理失敗 `1`、使用法の誤り `2` です。

## 仕組み

CLI はプライベートな Unix ソケットで署名済み helper に要求を送り、双方が相手のユーザー ID を確認します。
helper はコンソールセッション、Apple 署名の `loginwindow`、アカウント表示、パスワード欄を検証してからキーチェーンを読み取ります。
30 秒の試行制限と、送信後に解除を確認できない場合のサーキットブレーカーがあります。

カバーは送信前にロック画面の下に置かれます。**Unlock Mac** で macOS 認証を完了すると画面を表示し、タスクの再ロック権限を無効にします。
システムのロックイベント、画面維持の終了、helper の再起動でもトークンは失効します。60 分は画面維持の上限であり、自動ロック予約ではありません。
[設計メモ](docs/DESIGN.md)と[エージェントスキル](skills/sparekey/SKILL.md)に詳細があります。

## セキュリティ

インストール前に[セキュリティポリシー](SECURITY.md)を読んでください。

- 同じユーザー権限のすべてのプロセスが解除を要求できます。信頼できる個人アカウント向けです。
- カバーはロックではなく、画面を見ずに行う物理入力も防ぎません。キャプチャには含まれません。
- helper はネットワークではなくローカルソケットを使います。同じユーザー権限のマルウェアは防げません。
- パスワードをチャット、引数、環境変数、文書に入れないでください。トークンもログや報告に残さないでください。
- 失敗した解除のループや検証の回避は行わず、脆弱性はポリシーに従って非公開で報告してください。

## トラブルシューティング

まず `sparekey doctor` を確認します。成功しても、実際のロック画面や解除成功を検証したことにはなりません。

- `not_set_up`、`helper_not_running`、`helper_version_mismatch` はローカルで `sparekey setup` を実行します。
- `accessibility_missing` はシステム設定 > プライバシーとセキュリティ > アクセシビリティで helper を許可し、setup を再実行します。
- `credential_unavailable` は setup を再実行します。保存パスワードが古い場合は `sparekey setup --reset-password` を使います。
- `breaker_tripped`、`unlock_not_confirmed`、`rate_limited` では試行を繰り返さず、原因を確認します。
- アカウントや入力欄の検証エラーでは未検証の欄に入力しません。`relock_revoked` では状態を変えません。
- `display_sleep_not_confirmed` でもロック済みの可能性があります。次の操作前に `status` を確認します。

残った「アプリケーションの強制終了」ウィンドウの限定的な復旧方法は[スキル](skills/sparekey/SKILL.md)を参照してください。probe の失敗はパスワード送信を意味しません。

## 開発

リポジトリルートで実行します。

```sh
swift build
swift test
swift build -c release
python3 scripts/embed-agent-assets.py --check
```

`Package.swift` は実行ファイル、`SparekeyCore`、core と transport のテストを定義します。エセット検査はスキルと生成 Swift の一致を確認します。
[Shimmer レンダラー](scripts/render-shimmer/README.md)は helper を操作せず画像を生成します。
[ローカル署名実験](scripts/spike/README.md)は Keychain と LaunchAgent を変更するため、意図して実行してください。
[変更履歴](CHANGELOG.md)も参照してください。ロック画面へのアクセス方法は [Cindy](https://github.com/makecindy/cindy)を参考にした独立実装です。

## ライセンス

[MIT](LICENSE)、著作権者 yoonpooh。
