//! 結構化警告：UI 依 code 與參數自行翻譯；Display 為 CLI 用的中文。

use serde::Serialize;
use std::fmt;

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(tag = "code", rename_all = "snake_case")]
pub enum Warn {
    /// 品質到下限仍超過大小上限
    OverMax { quality: u8, bytes: u64, max: u64 },
    /// 品質到下限仍超標，已縮小解析度
    Downscaled {
        quality: u8,
        times: u32,
        width: u32,
        height: u32,
    },
    /// 已用最高品質仍低於大小下限
    UnderMin { bytes: u64, min: u64 },
    /// GIF 只取第一格
    GifFirstFrame,
    /// 無損 JPEG 需重新編碼（縮放或轉檔）
    JpegReencoded,
    /// 目標大小模式：品質降到 1 仍超過目標
    TargetNotReached { bytes: u64, target: u64 },
    /// EXIF 超過 JPEG 上限（64 KB），已移除其中的縮圖
    ExifThumbnailRemoved,
    /// EXIF 超過 JPEG 上限（64 KB），未保留
    ExifDropped,
}

impl Warn {
    pub fn code(&self) -> &'static str {
        match self {
            Warn::OverMax { .. } => "over_max",
            Warn::Downscaled { .. } => "downscaled",
            Warn::UnderMin { .. } => "under_min",
            Warn::GifFirstFrame => "gif_first_frame",
            Warn::JpegReencoded => "jpeg_reencoded",
            Warn::TargetNotReached { .. } => "target_not_reached",
            Warn::ExifThumbnailRemoved => "exif_thumbnail_removed",
            Warn::ExifDropped => "exif_dropped",
        }
    }

    /// 參數（依各 code 固定順序）
    pub fn args(&self) -> Vec<i64> {
        match *self {
            Warn::OverMax {
                quality,
                bytes,
                max,
            } => vec![quality as i64, bytes as i64, max as i64],
            Warn::Downscaled {
                quality,
                times,
                width,
                height,
            } => {
                vec![quality as i64, times as i64, width as i64, height as i64]
            }
            Warn::UnderMin { bytes, min } => vec![bytes as i64, min as i64],
            Warn::GifFirstFrame
            | Warn::JpegReencoded
            | Warn::ExifThumbnailRemoved
            | Warn::ExifDropped => vec![],
            Warn::TargetNotReached { bytes, target } => vec![bytes as i64, target as i64],
        }
    }
}

impl fmt::Display for Warn {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Warn::OverMax {
                quality,
                bytes,
                max,
            } => {
                write!(f, "品質 {quality} 仍有 {bytes} bytes，超過上限 {max}")
            }
            Warn::Downscaled {
                quality,
                times,
                width,
                height,
            } => {
                write!(
                    f,
                    "品質降到 {quality} 仍超標，解析度縮小 {times} 次至 {width}×{height}"
                )
            }
            Warn::UnderMin { bytes, min } => {
                write!(
                    f,
                    "檔案 {bytes} bytes 低於下限 {min}（已用品質 100、4:4:4 並關閉最佳化）"
                )
            }
            Warn::GifFirstFrame => write!(f, "GIF 只取第一格"),
            Warn::JpegReencoded => {
                write!(f, "JPEG 需重新編碼（縮放或轉檔），以品質 100、4:4:4 輸出")
            }
            Warn::TargetNotReached { bytes, target } => {
                write!(f, "品質降到 1 仍有 {bytes} bytes，超過目標 {target}")
            }
            Warn::ExifThumbnailRemoved => write!(f, "EXIF 超過 JPEG 的 64 KB 上限，已移除其中的縮圖"),
            Warn::ExifDropped => write!(f, "EXIF 超過 JPEG 的 64 KB 上限，未保留"),
        }
    }
}
