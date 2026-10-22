//! image_compressor 影像核心。
//!
//! 第一階段：電商模式（Shopee / momo）完整流程；普通模式於第三階段加入。

pub mod cleanup;
pub mod detail;
pub mod ecommerce;
pub mod encode;
pub mod geom;
pub mod load;
pub mod natsort;

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
}

pub type Result<T> = std::result::Result<T, Error>;
