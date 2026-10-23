//! 檔案與縮圖相關 API。

use crate::api::common::AppError;
use imgcore::{geom, heif, load, natsort};
use std::path::{Path, PathBuf};

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// 展開資料夾（不遞迴）、只保留支援的圖片，依檔名自然排序。
pub fn collect_images(paths: Vec<String>) -> Vec<String> {
    let mut out: Vec<PathBuf> = Vec::new();
    for p in paths.iter().map(PathBuf::from) {
        if p.is_dir() {
            if let Ok(rd) = std::fs::read_dir(&p) {
                out.extend(
                    rd.filter_map(|e| e.ok().map(|e| e.path()))
                        .filter(|f| f.is_file() && load::is_image_path(f)),
                );
            }
        } else if p.is_file() && load::is_image_path(&p) {
            out.push(p);
        }
    }
    natsort::sort_paths(&mut out);
    out.into_iter()
        .map(|p| p.to_string_lossy().into_owned())
        .collect()
}

/// 依檔名自然排序。
#[flutter_rust_bridge::frb(sync)]
pub fn sort_natural(mut paths: Vec<String>) -> Vec<String> {
    natsort::sort_paths(&mut paths);
    paths
}

#[flutter_rust_bridge::frb(sync)]
pub fn natural_compare(a: String, b: String) -> i32 {
    natsort::natural_cmp(&a, &b) as i32
}

pub struct ImageMeta {
    pub path: String,
    pub width: u32,
    pub height: u32,
    pub file_size: u64,
    /// 讀取失敗（含此平台無法解碼 HEIC）
    pub error: Option<AppError>,
}

/// 此平台能否解碼 HEIC / HEIF（第一次呼叫會做一次實際解碼測試）。
pub fn heif_supported() -> bool {
    heif::supported()
}

/// HEIC 解碼自我測試（診斷用）：每行「OK/FAIL 項目: 說明」。
pub fn heif_self_test() -> Vec<String> {
    heif::self_test()
        .into_iter()
        .map(|(name, r)| match r {
            Ok(m) => format!("OK   {name}: {m}"),
            Err(e) => format!("FAIL {name}: {e}"),
        })
        .collect()
}

fn is_heif_file(p: &Path) -> bool {
    use std::io::Read;
    let mut b = [0u8; 64];
    std::fs::File::open(p)
        .and_then(|mut f| f.read(&mut b))
        .map(|n| heif::is_heif(&b[..n]))
        .unwrap_or(false)
}

/// 讀取尺寸（已考慮 EXIF 旋轉）與檔案大小。
pub fn image_meta(path: String) -> ImageMeta {
    let p = Path::new(&path);
    let file_size = std::fs::metadata(p).map(|m| m.len()).unwrap_or(0);
    // 不能解碼的 HEIC 先標成錯誤，避免加入後才失敗
    let res = if is_heif_file(p) && !heif::supported() {
        Err(imgcore::Error::Unsupported("HEIC".into()))
    } else {
        load::dimensions(p)
    };
    match res {
        Ok((width, height)) => ImageMeta {
            path,
            width,
            height,
            file_size,
            error: None,
        },
        Err(e) => ImageMeta {
            path,
            width: 0,
            height: 0,
            file_size,
            error: Some((&e).into()),
        },
    }
}

/// 產生縮圖（JPEG bytes，最長邊 max_side，已套用 EXIF 方向、sRGB、白底）。
pub fn thumbnail(path: String, max_side: u32) -> anyhow::Result<Vec<u8>> {
    let img = load::load_rgb(Path::new(&path))?;
    let (w, h) = img.dimensions();
    let s = (max_side as f64 / w.max(h) as f64).min(1.0);
    let small = if s < 1.0 { geom::scale(&img, s) } else { img };
    Ok(imgcore::encode::encode_jpeg(
        &small,
        85,
        imgcore::encode::Mode::Normal,
    )?)
}
