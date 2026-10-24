//! 電商模式：Shopee / momo 主圖、選項圖、詳情圖。
//!
//! 流程：`prepare`（讀檔＋排版＋預檢）→ `encode`（壓縮，記憶體內）→ `write`（清理舊檔後寫入）。

use crate::cleanup::{self, Disposal};
use crate::encode::{self, Target};
use crate::geom::{self, Fit};
use crate::{Error, Result, detail, load};
use image::RgbImage;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Platform {
    Shopee,
    Momo,
}

impl Platform {
    pub fn dir_name(self) -> &'static str {
        match self {
            Platform::Shopee => "shopee",
            Platform::Momo => "momo",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Category {
    Main,
    Variant,
    Desc,
}

impl Category {
    pub fn prefix(self) -> &'static str {
        match self {
            Category::Main => "main",
            Category::Variant => "variant",
            Category::Desc => "desc",
        }
    }
}

pub const SHOPEE_MAX_BYTES: u64 = 2_000_000;
/// momo 主圖 / 選項圖：38 KB（以 1024 計，取較嚴格者）– 1,000,000 bytes
pub const MOMO_MAIN_MIN_BYTES: u64 = 38 * 1024;
pub const MOMO_MAX_BYTES: u64 = 1_000_000;
/// momo 詳情圖：< 500 KB（以 1000 計，取較嚴格者）
pub const MOMO_DESC_MAX_BYTES: u64 = 500_000;
pub const MOMO_MAIN_SIZE: u32 = 1000;
pub const SHOPEE_DESC_LIMIT: usize = 12;
pub const MOMO_DESC_LIMIT: usize = 20;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub shopee_max_desc: usize,
    pub momo_max_desc: usize,
    pub smart_cut: bool,
    /// Shopee 品質下限，仍超標才縮解析度
    pub shopee_min_quality: u8,
    /// momo 品質下限（只調品質）
    pub momo_min_quality: u8,
    /// 品質上限：每張圖各自二分搜尋「符合大小限制的最高品質」，不超過此值
    pub max_quality: u8,
    /// 色度 4:4:4（文字 / 細線邊緣較清晰，檔案較大）
    pub chroma444: bool,
    /// Shopee 輸出最大寬度（0 = 不限制）
    pub shopee_max_width: u32,
    /// momo 詳情圖最後一段低於此高度時從前一段挪高度（0 = 保持實際高度）
    pub momo_min_last: u32,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            shopee_max_desc: 12,
            momo_max_desc: 18,
            smart_cut: false,
            shopee_min_quality: 60,
            momo_min_quality: 10,
            max_quality: 92,
            chroma444: false,
            shopee_max_width: 2000,
            momo_min_last: detail::MOMO_DEFAULT_MIN_LAST,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct InputImage {
    pub path: PathBuf,
    #[serde(default)]
    pub fit: Fit,
}

impl InputImage {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self {
            path: path.into(),
            fit: Fit::Pad,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Job {
    pub name: String,
    #[serde(default)]
    pub main: Vec<InputImage>,
    #[serde(default)]
    pub variant: Vec<InputImage>,
    #[serde(default)]
    pub desc: Vec<PathBuf>,
    pub platforms: Vec<Platform>,
    #[serde(default)]
    pub settings: Settings,
    /// 未指定時 = 三區合計圖片最多的來源資料夾
    #[serde(default)]
    pub output_root: Option<PathBuf>,
}

/// UI 用：這張圖在該平台/類別下是否需要選擇補白或裁切。
pub fn needs_fit_choice(platform: Platform, cat: Category, w: u32, h: u32) -> bool {
    match (platform, cat) {
        (_, Category::Desc) => false,
        (Platform::Shopee, Category::Main) => {
            !geom::matches_ratio(w, h, 1, 1) && !geom::matches_ratio(w, h, 3, 4)
        }
        _ => !geom::matches_ratio(w, h, 1, 1),
    }
}

/// Shopee 主圖：1:1 或 3:4 保持；否則取較接近的比例。
pub fn shopee_main_ratio(w: u32, h: u32) -> Option<(u32, u32)> {
    if geom::matches_ratio(w, h, 1, 1) || geom::matches_ratio(w, h, 3, 4) {
        return None;
    }
    let r = (w as f64 / h as f64).ln();
    if (r - 0.0).abs() <= (r - 0.75f64.ln()).abs() {
        Some((1, 1))
    } else {
        Some((3, 4))
    }
}

fn file_name(name: &str, cat: Category, idx: usize, total: usize) -> String {
    let width = total.to_string().len().max(2);
    format!("{name}_{}_{:0width$}.jpg", cat.prefix(), idx + 1)
}

/// 三區合計圖片最多的資料夾（同數取先出現者）。
pub fn source_folder(job: &Job) -> Option<PathBuf> {
    let mut order: Vec<PathBuf> = Vec::new();
    let mut count: HashMap<PathBuf, usize> = HashMap::new();
    let all = job
        .main
        .iter()
        .map(|i| &i.path)
        .chain(job.variant.iter().map(|i| &i.path))
        .chain(job.desc.iter());
    for p in all {
        let dir = p.parent().map(|d| d.to_path_buf()).unwrap_or_default();
        let c = count.entry(dir.clone()).or_insert(0);
        if *c == 0 {
            order.push(dir);
        }
        *c += 1;
    }
    order
        .into_iter()
        .fold(None, |best: Option<PathBuf>, d| match &best {
            Some(b) if count[b] >= count[&d] => best,
            _ => Some(d),
        })
}

fn validate(job: &Job) -> Result<()> {
    let n = job.name.trim();
    if n.is_empty() {
        return Err(Error::Invalid("name 不可空白".into()));
    }
    if n.chars()
        .any(|c| r#"\/:*?"<>|"#.contains(c) || c.is_control())
    {
        return Err(Error::Invalid(format!("name 含有不能用於檔名的字元：{n}")));
    }
    if job.platforms.is_empty() {
        return Err(Error::Invalid("至少勾選一個平台".into()));
    }
    if job.main.is_empty() && job.variant.is_empty() && job.desc.is_empty() {
        return Err(Error::Invalid("三個區塊都沒有圖片".into()));
    }
    let s = &job.settings;
    if !(1..=SHOPEE_DESC_LIMIT).contains(&s.shopee_max_desc) {
        return Err(Error::Invalid(format!(
            "Shopee 詳情圖上限需在 1–{SHOPEE_DESC_LIMIT}"
        )));
    }
    if !(1..=MOMO_DESC_LIMIT).contains(&s.momo_max_desc) {
        return Err(Error::Invalid(format!(
            "momo 詳情圖上限需在 1–{MOMO_DESC_LIMIT}"
        )));
    }
    if !(1..=100).contains(&s.max_quality)
        || s.shopee_min_quality > s.max_quality
        || s.momo_min_quality > s.max_quality
    {
        return Err(Error::Invalid("品質設定不合理".into()));
    }
    if s.shopee_max_width != 0 && s.shopee_max_width < detail::SHOPEE_UPSCALE_WIDTH {
        return Err(Error::Invalid(format!(
            "Shopee 最大寬度需為 0（不限制）或 ≥ {}",
            detail::SHOPEE_UPSCALE_WIDTH
        )));
    }
    if s.momo_min_last >= detail::MOMO_SEG_HEIGHT {
        return Err(Error::Invalid("momo 尾段最小高度需小於 1500".into()));
    }
    Ok(())
}

/// 排版完成、尚未壓縮的一張輸出。
pub struct Piece {
    pub platform: Platform,
    pub category: Category,
    pub index: usize,
    pub file_name: String,
    pub image: RgbImage,
    pub target: Target,
}

#[derive(Clone, Debug, Serialize)]
pub struct Overflow {
    pub platform: Platform,
    pub count: usize,
    pub limit: usize,
}

pub struct Prepared {
    pub name: String,
    pub output_root: PathBuf,
    pub pieces: Vec<Piece>,
    pub desc_counts: Vec<(Platform, usize)>,
    /// 非空 = 預檢失敗，整批不輸出
    pub overflow: Vec<Overflow>,
}

/// 讀檔、排版並預檢（不壓縮、不寫檔）。
pub fn prepare(job: &Job) -> Result<Prepared> {
    validate(job)?;
    let output_root = match &job.output_root {
        Some(p) => p.clone(),
        None => source_folder(job).unwrap_or_default(),
    };
    let s = &job.settings;
    let load_all = |paths: Vec<&PathBuf>| -> Result<Vec<RgbImage>> {
        paths.par_iter().map(|p| load::load_rgb(p)).collect()
    };
    let mains = load_all(job.main.iter().map(|i| &i.path).collect())?;
    let variants = load_all(job.variant.iter().map(|i| &i.path).collect())?;
    let descs = load_all(job.desc.iter().collect())?;

    let mut pieces = Vec::new();
    let mut desc_counts = Vec::new();
    let mut overflow = Vec::new();
    let name = job.name.trim().to_string();

    for &pf in &job.platforms {
        let (main_t, desc_t) = match pf {
            Platform::Shopee => {
                let t = Target {
                    max_bytes: SHOPEE_MAX_BYTES,
                    min_bytes: None,
                    min_quality: s.shopee_min_quality,
                    max_quality: s.max_quality,
                    allow_downscale: true,
                    chroma444: s.chroma444,
                };
                (t.clone(), t)
            }
            Platform::Momo => (
                Target {
                    max_bytes: MOMO_MAX_BYTES,
                    min_bytes: Some(MOMO_MAIN_MIN_BYTES),
                    min_quality: s.momo_min_quality,
                    max_quality: s.max_quality,
                    allow_downscale: false,
                    chroma444: s.chroma444,
                },
                Target {
                    max_bytes: MOMO_DESC_MAX_BYTES,
                    min_bytes: None,
                    min_quality: s.momo_min_quality,
                    max_quality: s.max_quality,
                    allow_downscale: false,
                    chroma444: s.chroma444,
                },
            ),
        };

        for (cat, inputs, imgs) in [
            (Category::Main, &job.main, &mains),
            (Category::Variant, &job.variant, &variants),
        ] {
            let total = imgs.len();
            for (i, (inp, img)) in inputs.iter().zip(imgs.iter()).enumerate() {
                let out = match (pf, cat) {
                    (Platform::Shopee, Category::Main) => {
                        match shopee_main_ratio(img.width(), img.height()) {
                            None => img.clone(),
                            Some((rw, rh)) => geom::fit_ratio(img, rw, rh, inp.fit),
                        }
                    }
                    (Platform::Shopee, _) => geom::fit_ratio(img, 1, 1, inp.fit),
                    (Platform::Momo, _) => {
                        let sq = geom::fit_ratio(img, 1, 1, inp.fit);
                        geom::resize(&sq, MOMO_MAIN_SIZE, MOMO_MAIN_SIZE)
                    }
                };
                let out = match pf {
                    Platform::Shopee
                        if s.shopee_max_width > 0 && out.width() > s.shopee_max_width =>
                    {
                        geom::resize_to_width(&out, s.shopee_max_width)
                    }
                    _ => out,
                };
                pieces.push(Piece {
                    platform: pf,
                    category: cat,
                    index: i,
                    file_name: file_name(&name, cat, i, total),
                    image: out,
                    target: main_t.clone(),
                });
            }
        }

        if !descs.is_empty() {
            let laid = match pf {
                Platform::Shopee => detail::shopee_layout(&descs, s.smart_cut, s.shopee_max_width),
                Platform::Momo => detail::momo_layout(&descs, s.smart_cut, s.momo_min_last),
            };
            let limit = match pf {
                Platform::Shopee => s.shopee_max_desc,
                Platform::Momo => s.momo_max_desc,
            };
            desc_counts.push((pf, laid.len()));
            if laid.len() > limit {
                overflow.push(Overflow {
                    platform: pf,
                    count: laid.len(),
                    limit,
                });
            }
            let total = laid.len();
            for (i, img) in laid.into_iter().enumerate() {
                pieces.push(Piece {
                    platform: pf,
                    category: Category::Desc,
                    index: i,
                    file_name: file_name(&name, Category::Desc, i, total),
                    image: img,
                    target: desc_t.clone(),
                });
            }
        }
    }

    Ok(Prepared {
        name,
        output_root,
        pieces,
        desc_counts,
        overflow,
    })
}

#[derive(Clone, Debug, Serialize)]
pub struct Output {
    pub platform: Platform,
    pub category: Category,
    pub file_name: String,
    pub width: u32,
    pub height: u32,
    pub bytes: usize,
    pub quality: u8,
    pub mode: encode::Mode,
    pub warnings: Vec<crate::warn::Warn>,
    #[serde(skip)]
    pub data: Vec<u8>,
}

/// 執行進度。
#[derive(Clone, Debug, Serialize)]
pub enum Progress {
    /// 讀檔與排版（含預檢）
    Preparing,
    /// 壓縮中：已完成 / 總數
    Encoding { done: usize, total: usize },
    /// 清理舊檔與寫入
    Writing,
}

pub fn encode_all(p: &Prepared) -> Result<Vec<Output>> {
    encode_all_with_progress(p, &|_| {})
}

pub fn encode_all_with_progress(
    p: &Prepared,
    progress: &(dyn Fn(Progress) + Sync),
) -> Result<Vec<Output>> {
    let total = p.pieces.len();
    let done = std::sync::atomic::AtomicUsize::new(0);
    progress(Progress::Encoding { done: 0, total });
    p.pieces
        .par_iter()
        .map(|pc| {
            let e = encode::compress_to_target(&pc.image, &pc.target)?;
            let n = done.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1;
            progress(Progress::Encoding { done: n, total });
            Ok(Output {
                platform: pc.platform,
                category: pc.category,
                file_name: pc.file_name.clone(),
                width: e.width,
                height: e.height,
                bytes: e.data.len(),
                quality: e.quality,
                mode: e.mode,
                warnings: e.warnings,
                data: e.data,
            })
        })
        .collect()
}

#[derive(Clone, Debug, Serialize)]
pub struct WriteReport {
    pub written: Vec<PathBuf>,
    pub disposed: Vec<PathBuf>,
}

/// 清理本次有處理的類別舊檔，再寫入 `<root>/<platform>/`。
pub fn write_outputs(
    name: &str,
    root: &Path,
    outputs: &[Output],
    how: Disposal,
) -> Result<WriteReport> {
    let mut by_pf: HashMap<Platform, Vec<&Output>> = HashMap::new();
    for o in outputs {
        by_pf.entry(o.platform).or_default().push(o);
    }
    let mut rep = WriteReport {
        written: vec![],
        disposed: vec![],
    };
    let mut pfs: Vec<_> = by_pf.keys().copied().collect();
    pfs.sort_by_key(|p| p.dir_name());
    for pf in pfs {
        let outs = &by_pf[&pf];
        let dir = root.join(pf.dir_name());
        std::fs::create_dir_all(&dir)?;
        let mut cats: Vec<Category> = outs.iter().map(|o| o.category).collect();
        cats.dedup();
        cats.sort_by_key(|c| c.prefix());
        cats.dedup();
        let old = cleanup::find_old_outputs(&dir, name, &cats)?;
        cleanup::dispose(&old, how)?;
        rep.disposed.extend(old);
        for o in outs {
            let p = dir.join(&o.file_name);
            std::fs::write(&p, &o.data)?;
            rep.written.push(p);
        }
    }
    Ok(rep)
}

#[derive(Debug, Serialize)]
pub struct RunReport {
    pub output_root: PathBuf,
    pub desc_counts: Vec<(Platform, usize)>,
    /// 非空時代表預檢失敗、未輸出任何檔案
    pub overflow: Vec<Overflow>,
    pub outputs: Vec<Output>,
    pub written: Vec<PathBuf>,
    pub disposed: Vec<PathBuf>,
}

/// 完整執行。`dry_run` 時只壓縮不寫檔。
pub fn run(job: &Job, how: Disposal, dry_run: bool) -> Result<RunReport> {
    run_with_progress(job, how, dry_run, &|_| {})
}

/// 同 [`run`]，並回報進度。
pub fn run_with_progress(
    job: &Job,
    how: Disposal,
    dry_run: bool,
    progress: &(dyn Fn(Progress) + Sync),
) -> Result<RunReport> {
    progress(Progress::Preparing);
    let p = prepare(job)?;
    let mut rep = RunReport {
        output_root: p.output_root.clone(),
        desc_counts: p.desc_counts.clone(),
        overflow: p.overflow.clone(),
        outputs: vec![],
        written: vec![],
        disposed: vec![],
    };
    if !p.overflow.is_empty() {
        return Ok(rep);
    }
    rep.outputs = encode_all_with_progress(&p, progress)?;
    if !dry_run {
        progress(Progress::Writing);
        let w = write_outputs(&p.name, &p.output_root, &rep.outputs, how)?;
        rep.written = w.written;
        rep.disposed = w.disposed;
    }
    Ok(rep)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn naming() {
        assert_eq!(file_name("ssd", Category::Main, 0, 3), "ssd_main_01.jpg");
        assert_eq!(file_name("ssd", Category::Desc, 11, 12), "ssd_desc_12.jpg");
        assert_eq!(
            file_name("ssd", Category::Variant, 4, 120),
            "ssd_variant_005.jpg"
        );
    }

    #[test]
    fn shopee_main_ratio_choice() {
        assert_eq!(shopee_main_ratio(1000, 1000), None);
        assert_eq!(shopee_main_ratio(750, 1000), None);
        assert_eq!(shopee_main_ratio(1600, 900), Some((1, 1)));
        assert_eq!(shopee_main_ratio(500, 1000), Some((3, 4)));
        assert_eq!(shopee_main_ratio(950, 1000), Some((1, 1)));
        assert_eq!(shopee_main_ratio(800, 1000), Some((3, 4)));
    }

    #[test]
    fn fit_choice_visibility() {
        assert!(!needs_fit_choice(
            Platform::Shopee,
            Category::Main,
            750,
            1000
        ));
        assert!(needs_fit_choice(Platform::Momo, Category::Main, 750, 1000));
        assert!(needs_fit_choice(
            Platform::Shopee,
            Category::Variant,
            750,
            1000
        ));
        assert!(!needs_fit_choice(Platform::Momo, Category::Desc, 750, 1000));
    }

    #[test]
    fn source_folder_most_images() {
        let job = Job {
            name: "n".into(),
            main: vec![InputImage::new("/a/1.jpg")],
            variant: vec![InputImage::new("/b/1.jpg"), InputImage::new("/b/2.jpg")],
            desc: vec!["/a/d1.jpg".into(), "/a/d2.jpg".into()],
            platforms: vec![Platform::Momo],
            settings: Settings::default(),
            output_root: None,
        };
        assert_eq!(source_folder(&job).unwrap(), PathBuf::from("/a"));
    }

    #[test]
    fn rejects_bad_settings() {
        let mut job = Job {
            name: "n/x".into(),
            main: vec![InputImage::new("/a/1.jpg")],
            variant: vec![],
            desc: vec![],
            platforms: vec![Platform::Momo],
            settings: Settings::default(),
            output_root: None,
        };
        assert!(validate(&job).is_err());
        job.name = "ok".into();
        assert!(validate(&job).is_ok());
        job.settings.momo_max_desc = 21;
        assert!(validate(&job).is_err());
    }
}
