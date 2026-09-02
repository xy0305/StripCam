# StripCam

一个 **Stripchat 第三方 iOS 播放器**，UI 参考 [AngelLive](https://github.com/pcccccc/AngelLive) 的原生克制风格（侧边栏分类 + 直播网格 + 沉浸式竖屏播放页 + 右侧滑入的清晰度面板），核心能力对照 Stripchat 插件脚本实现：

- 完整分类目录（推荐 / 地区 / 类型 / 情侣 / 男主播 / 我的最爱）
- 实时封面 + 主播信息（观看数、HD、状态）
- **最高画质 + 声音**：解析多条 CDN 的 HLS 主播放列表，自动选择最高码率，并支持手动切换清晰度 / 线路
- 本地收藏、主播搜索、Cookie 登录（我的最爱）

> ⚠️ 本应用为**第三方非官方**播放器，与 Stripchat 官方无关，仅供学习交流使用。请遵守当地法律法规，仅观看你有权访问的内容。

## 系统要求

- Xcode 16.0+（项目使用文件系统同步组格式）
- iOS 17.0+
- 语言：Swift 5

## 运行

1. 用 Xcode 打开 `StripCam.xcodeproj`
2. 在 `StripCam` target → Signing & Capabilities 中选择你的开发者团队
3. 选择 iPhone / iPad 模拟器或真机运行

## 「我的最爱」使用说明

「我的最爱」需要登录后的 Cookie：

1. 浏览器登录 [stripchat.com](https://stripchat.com)
2. 打开开发者工具 → Network，复制任意请求头里的完整 `Cookie`
3. 打开 App → 设置 → 粘贴 Cookie → 保存
4. 回到侧边栏进入「❤️ 我的最爱」

Cookie 仅保存在本机（UserDefaults），不会上传。

## 直播流解析原理

对应插件脚本 `_resolvePlayableStreams`：

- CDN：`edge-hls.saawsedge.com` / `edge-hls.growcdnssedge.com` / `edge-hls.doppiocdn.com`
- 直接构造各清晰度：`/hls/{id}/master/{id}_{quality}.m3u8?playlistType=lowLatency`
- 拉取 `_auto.m3u8` 主播放列表，解析 `#EXT-X-STREAM-INF` 变体（含 `BANDWIDTH` / `RESOLUTION` / `NAME`）与 `pkey`（MOUFLON PSCH）
- 按码率从高到低排序；「自动」档让 AVPlayer 不限制码率，优先选择最高画质（视频 + 音频多路复用）

## 目录结构

```
StripCam/
├── StripCamApp.swift              # App 入口（音频会话配置）
├── ContentView.swift              # 根视图（NavigationSplitView 侧边栏）
├── Support/                       # 常量 / 模型 / API / 收藏存储
├── ViewModels/                    # 首页 / 搜索 / 播放器状态
├── Views/
│   ├── Home/                      # 直播网格
│   ├── Player/                    # 播放页 / 清晰度面板 / 主播信息
│   ├── Components/                # 卡片 / 网络图片
│   └── ...                        # 收藏 / 搜索 / 设置
└── Assets.xcassets
```

## License

MIT
