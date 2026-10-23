//! image_compressor 影像核心。
//!
//! 電商模式（Shopee / momo）與普通模式（對照 Caesium）。

pub mod cleanup;
pub mod detail;
pub mod ecommerce;
pub mod encode;
pub mod exif;
pub mod geom;
pub mod heif;
pub mod jpeg_lossless;
pub mod load;
pub mod natsort;
pub mod normal;
pub mod warn;

pub use image::RgbImage;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("I/O 錯誤：{0}")]
    Io(#[from] std::io::Error),
    #[error("無法讀取圖片 {path}：{msg}")]
    Decode { path: String, msg: String },
    #[error("JPEG 編碼失敗：{0}")]
    Encode(String),
    #[error("設定錯誤：{0}")]
    Invalid(String),
    #[error("移到垃圾桶失敗：{0}")]
    Trash(String),
    /// 此平台不支援的格式（目前只有 "heif"）
    #[error("此平台無法讀取 {0} 格式")]
    Unsupported(String),
}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Serialize)]
pub enum ErrorKind {
    Io,
    Decode,
    Encode,
    Invalid,
    Trash,
    Unsupported,
}

/// 可複製的錯誤資訊：kind + 不含前綴的細節；message 為完整中文訊息（CLI 用）。
#[derive(Clone, Debug, serde::Serialize)]
pub struct ErrorInfo {
    pub kind: ErrorKind,
    pub detail: String,
    pub message: String,
}

impl From<&Error> for ErrorInfo {
    fn from(e: &Error) -> Self {
        let (kind, detail) = match e {
            Error::Io(x) => (ErrorKind::Io, x.to_string()),
            Error::Decode { path, msg } => (
                ErrorKind::Decode,
                if path.is_empty() {
                    msg.clone()
                } else {
                    format!("{path}: {msg}")
                },
            ),
            Error::Encode(m) => (ErrorKind::Encode, m.clone()),
            Error::Invalid(m) => (ErrorKind::Invalid, m.clone()),
            Error::Trash(m) => (ErrorKind::Trash, m.clone()),
            Error::Unsupported(m) => (ErrorKind::Unsupported, m.clone()),
        };
        Self {
            kind,
            detail,
            message: e.to_string(),
        }
    }
}
