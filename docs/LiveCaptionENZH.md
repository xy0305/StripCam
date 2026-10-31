# 实时翻译（英语 → 简体中文）

FullUI 播放页能力：把直播流里的英语语音识别成英文，再用系统翻译成中文字幕叠在画面上。

## 技术栈

| 阶段 | 实现 |
|------|------|
| 音频 | `LiveCaptionAudioReader`：独立 FFmpeg 音频 demux（与 KSPlayer 同 URL/Headers），优先最低码率 HLS 音频变体；`holdForBandwidth` 在起播/卡顿时让出带宽 |
| ASR | Apple `Speech`：`en-US`，优先本机；iOS 26+ 用 `SpeechAnalyzer` / `SpeechTranscriber` |
| MT | Apple `Translation`：`en` → `zh-Hans`（需 iOS 18+） |
| UI | FullUI 控制层「实时翻译」开关；关闭时先清字幕再异步停管道 |

不包含日语 SenseVoice / Sakura / Whisper。

## 使用

1. 进入直播间，等画面起播。
2. 点控制层 `character.bubble` 按钮，或「更多 / 设置」里的「实时翻译」。
3. 首次使用会申请**语音识别**权限，并可能提示下载英语→简体中文翻译包。
4. 再点一次即可关闭；关闭应立刻去掉字幕。

## 代码位置

- 共享模型 / 偏好：`Shared/AngelLiveCore/.../LiveCaption/`
- 音频 / ASR / MT / Session：`Shared/AngelLiveDependencies/.../LiveCaption/`
- FullUI：`iOS/AngelLive/AngelLive/FullUI/Views/Player/LiveCaption/` + 播放控制层接线

## 限制

- 仅 FullUI；默认播放内核 KSPlayer（`USE_VLC=1` 时无 FFmpeg demux，功能不可用）。
- 需要 iOS 18+（Translation）。
- 第二路音频 demux 会多占一些带宽；已用最低变体 + hold 降低对播放的影响。
- 面向英语直播；非英语内容识别质量会下降。

## 验证清单

- [ ] 英语直播开启后出现中文字幕
- [ ] 关闭开关字幕立刻消失，播放不卡顿
- [ ] 切换清晰度 / 刷新直播后字幕自动跟上新地址
- [ ] 拒绝语音识别权限时有可读错误提示
