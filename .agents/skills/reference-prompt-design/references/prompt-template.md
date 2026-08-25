# プロンプトテンプレート詳細

R2V 動画生成（MiniMax H3 想定）のプロンプト標準構造。`<...>` は埋めるべき部分。

**公式リファレンス（必読）**: MiniMax H3 Full-Reference Mode 出力書式ガイド
<https://huggingface.co/MiniMaxAI/MiniMax-H3/blob/main/docs/VIDEO_PROMPT_WRITING_GUIDE_ref_en.md>

本テンプレートの構造・タスク型・ラベル・マーカーはすべて上記ガイドに準拠する。

---

## ラベル仕様（ガイド §2）

| ラベル | 意味 | 備考 |
|--------|------|------|
| `<Subject N>` | 参照アセットから抽象化し、対象動画で再利用/変更する**可視コンテンツ**（人物・環境・服飾など） | 複数アセットで1被写体を定義、1アセットで複数被写体も可。環境も `<Subject N>` |
| `<Picture N>` | 具体的なフレームやショット計画のアンカーとなる参照画像 | キャラ定義のみなら単独エントリを作らず `<Subject N>` 内で引用 |
| `<Video N>` | 編集元・継続起点・全体の時間構造を提供する参照動画 | 可視コンテンツとして再利用するものは `<Subject N>` に属す |
| `<Audio N>` | コピー/参照される音声信号 | **音声が入っているだけでは作らない**。コピー/参照の役割がある場合のみ定義 |

- `<Video N>` と `<Audio N>` は**独立に採番**される。同一ソース由来でもペアを意味しない。
- 被写体が複数アセット由来の場合は「face from Picture 4, posture from Picture 1-3」のように各アセットの寄与を併記する。

## タスク型（ガイド §3 `summary`）

`summary` は必ず `[タスク型]` の前置きで始める。複数該当時は `+` で結合し重複させない。

| タスク型 | 使う時 |
|---------|--------|
| `keyframe completion` | 画像が最初/中間/最後のフレームなど具体的アンカーになる |
| `reference generation` | 画像/動画/音声がキャラ・シーン・動作などの生成指針になる（編集元でない） |
| `video editing` | 既存のソース動画を直接編集する |
| `video continuation` | 既存動画の続きを生成・遷移させる |
| `audio reuse` | 同一の音声信号を全編/一部そのまま再利用（≤完全コピー） |
| `audio reference` | 音楽スタイル・音色・歌詞などだけを参照（信号はコピーしない） |

例: `[reference generation + audio reuse]`（モーションを参照しつつ音声を完全コピー）

## 維持マーカー（ガイド §4 `retention_analysis`）

各ラベルは定義済みの役割に応じてマーカーを1つ選ぶ。

- **`<Subject N>` / `<Picture N>` / `<Video N>`**: `fully_preserved` / `partially_preserved` / `attribute_transfer` / `weak_reference`
- **`<Audio N>`**: `fully_copy`（全編1:1コピー）/ `partially_copy`（一部コピー・後加工）/ `reference`（音色等のみ参照）/ `weak_reference`

`retention_analysis` に `(Sx)` は書かない。`detailed_description` のみ `(Sx)` を使う。

---

## 標準構造（雛形）

```
subject_definitions:
<Subject 1> is <character description>. Face and <identity features> come from <Picture N>,
and body, build, and posture come from <Picture N>...<Picture N>. Her motion, rhythm, and
timing come from <Video N>.
<Subject 2> is <environment/background>, which fills the entire frame behind <Subject 1>
throughout the video.
<Audio 1> is <audio role>, <copied / referenced> in the target video.

summary:
[reference generation + audio reuse] The target video shows <Subject 1>, <character>,
<main action> from <Video N>, inside <Subject 2>, with <Audio 1> reused as its full soundtrack,
matching the reference video's structure from opening to the final state.

retention_analysis:
<Subject 1> (appears in [Shot 1]-[Shot N]): fully_preserved - face, body, and identity features
retained from <Picture N>...<Picture N>.
<Subject 2> (appears in all shots as the background): fully_preserved - the environment is
retained throughout.
<Video N> (structure and motion across all shots): attribute_transfer - the motion, rhythm, and
camera flow are transferred to <Subject 1>.
<Audio 1>: fully_copy - <Audio 1> is reused 1:1 as the target video's complete final audio track.

detailed_description:
<1-2文のスタイル前置き: ジャンル/色/照明のトーン。>[Shot 1] に置く前の一文として確立。
[Shot 1] The shot opens ... <構図・被写体の位置・外見・環境/照明・アクション/状態変化・
カメラ移動・現在の音を明記> <参照ラベル出現位置>.
[Shot 2] At 00:03.000, the shot cuts ... (以降同様).
[Shot 3] At 00:06.000, ...
[Shot 4] At 00:09.000, ...
[Shot 5] At 00:12.000, ...

overall_soundscape:
<アンビエンス/物理音の要約。音声をコピーするなら "copied ambience layer from <Audio 1>"
のように明記。>

non_diegetic_music:
<聴衆のみ聞こえるBGM。無ければ N/A。>
```

---

## `detailed_description` の書き方（ガイド §5）

- **350〜500語**を目安（generation）。ショットごとに情報量を配分する。1ショットだからといって短くしない。
- **`[Shot 1]` はタイムスタンプなし**。以降 `[Shot N] At MM:SS.mmm, ...` でカット時点を表す。
- 各ショットで必ず明記するもの：
  1. 現在の構図（ショットサイズ・アングル）
  2. 被写体の外見と位置
  3. 環境と照明
  4. アクションと状態変化
  5. カメラ移動（種類・振幅・速度）
  6. 現在の音（該当する場合）
  7. 参照ラベル（`<Subject N>` / `<Picture N>` / `<Video N>` / `<Audio N>`）が実際に現れる/作用する位置
- プロット要約や参照関係の羅列にしない。
- `(Sx)` は対象動画の実発声順で採番、全発声で使い回す。音声の直接再利用・完全コピーで歌詞/ささやき等を利用する場合 `<d>[Language] ...</d>` で正確に。判読不能は `[unclear]`。

---

## モデル制限がかかった時の対応

生成・素材が使用中のモデルの制限に抵触し、プロンプトを生成できない場合は、**勝手にプロンプトを生成せず、制限がかかったことをユーザーに報告するだけにする**。

- 報告は1〜2文で簡潔に。理由・説教・道徳的な長文は避ける（制限はモデルにより異なる）。
- 以降の進め方（代替案の検討など）はユーザーの判断を仰ぐ。
