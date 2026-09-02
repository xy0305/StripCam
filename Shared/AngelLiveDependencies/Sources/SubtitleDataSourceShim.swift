#if canImport(KSPlayer)
import Foundation

/// 上游 kingslay/KSPlayer 2.3.4 无 `SubtitleDataSource` 类型（其字幕 API 为 `SubtitleDataSouce`，
/// 且 `addSubtitle(dataSouce:)` 参数名有拼写差异）。此处提供空协议占位，兼容 AngelLive 的字幕参数类型。
public protocol SubtitleDataSource {}
#endif
