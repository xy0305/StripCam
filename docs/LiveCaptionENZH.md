# 实时翻译（英语 → 简体中文）

FullUI 播放页能力：把直播流里的英语语音识别成英文，再用系统翻译成中文字幕叠在画面上。

## 技术栈

| 阶段 | 实现 |
|------|------|
| 音频 | `LiveCaptionAudioReader`：独立 FFmpeg 音频 demux（与 KSPlayer 同 Headers）。HLS master 先在 Swift 里解析（`LiveCaptionHLS`），只把**独立音频 rendition / 最低码率变体**的 media playlist 交给 FFmpeg，避免 FFmpeg 探测全部视频档；`holdForBandwidth` 在起播/卡顿时让出带宽 |
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

## Chaturbate（2026-10-31 实测）

- 播放地址：插件 `get_edge_hls_url_ajax` → `edgeXX-sin.live.mmcdn.com/.../llhls.m3u8?token=…`，LL-HLS，fMP4（`EXT-X-MAP` init + 1.6 s 段 / 0.8 s part）。
- 音频是独立 rendition：`EXT-X-MEDIA TYPE=AUDIO`（AAC-LC 48 kHz 立体声 ~96 kbps），所有视频档共用。
- **token 一次性**：同一 master URL 第二次 GET 返回 `w3: session_duplicated` / FFmpeg 403。所以字幕不能复用播放器的 URL，`LiveCaptionController.makeRefresher` 会重新跑插件拿一个新 token（两个 session 可并存，不影响播放器）。
- 头：`User-Agent: libmpv` 即可，Referer / Cookie 非必需（插件仍会带 Referer）。
- 直接读音频 chunklist：拿 token 到首个 PCM 约 5 s，之后实时；若让 FFmpeg 打开 master，要 20–27 s 且会下载全部 4 个视频档。
- 直播没有 seek：FFmpeg 从直播边缘（`live_start_index=-3`）开始；读取失败 3 次后重新取 token 再连（2 分钟内最多 4 次）。
- 播放器续签 token（EOF 恢复）不会重启字幕；只有换流 / 换清晰度才重启。

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
- [ ] Chaturbate 英语房间：开启后 ~5–8 s 出字幕，播放器不黑屏/不卡；关掉再开仍正常
- [ ] Chaturbate 主播转私密/下播：字幕提示错误，不无限重连
