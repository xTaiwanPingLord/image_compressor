//! 電商模式 API（包裝 imgcore::ecommerce）。

use crate::frb_generated::StreamSink;
use imgcore::cleanup::Disposal;
use imgcore::ecommerce as ec;
use imgcore::geom;
use std::path::PathBuf;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ShopPlatform {
    Shopee,
    Momo,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ImgCategory {
    Main,
    Variant,
    Desc,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Fit {
    Pad,
    Crop,
}

impl From<ShopPlatform> for ec::Platform {
    fn from(p: ShopPlatform) -> Self {
        match p {
            ShopPlatform::Shopee => ec::Platform::Shopee,
            ShopPlatform::Momo => ec::Platform::Momo,
        }
    }
}
impl From<ec::Platform> for ShopPlatform {
    fn from(p: ec::Platform) -> Self {
        match p {
            ec::Platform::Shopee => ShopPlatform::Shopee,
            ec::Platform::Momo => ShopPlatform::Momo,
        }
    }
}
impl From<ImgCategory> for ec::Category {
    fn from(c: ImgCategory) -> Self {
        match c {
            ImgCategory::Main => ec::Category::Main,
            ImgCategory::Variant => ec::Category::Variant,
            ImgCategory::Desc => ec::Category::Desc,
        }
    }
}
impl From<ec::Category> for ImgCategory {
    fn from(c: ec::Category) -> Self {
        match c {
            ec::Category::Main => ImgCategory::Main,
            ec::Category::Variant => ImgCategory::Variant,
            ec::Category::Desc => ImgCategory::Desc,
        }
    }
}
impl From<Fit> for geom::Fit {
    fn from(f: Fit) -> Self {
        match f {
            Fit::Pad => geom::Fit::Pad,
            Fit::Crop => geom::Fit::Crop,
        }
    }
}

#[derive(Clone, Debug)]
pub struct EcomSettings {
    pub shopee_max_desc: u32,
    pub momo_max_desc: u32,
    pub smart_cut: bool,
    /// 0 = 不限制
    pub shopee_max_width: u32,
    /// 0 = 保持實際高度
    pub momo_min_last: u32,
    /// 品質上限（60–100）；每張圖各自找符合大小限制的最高品質
    pub max_quality: u8,
    /// 色度 4:4:4
    pub chroma444: bool,
}

#[flutter_rust_bridge::frb(sync)]
pub fn default_settings() -> EcomSettings {
    let d = ec::Settings::default();
    EcomSettings {
        shopee_max_desc: d.shopee_max_desc as u32,
        momo_max_desc: d.momo_max_desc as u32,
        smart_cut: d.smart_cut,
        shopee_max_width: d.shopee_max_width,
        momo_min_last: d.momo_min_last,
        max_quality: d.max_quality,
        chroma444: d.chroma444,
    }
}

/// 各平台詳情圖上限的最大可設定值。
#[flutter_rust_bridge::frb(sync)]
pub fn desc_limit(platform: ShopPlatform) -> u32 {
    match platform {
        ShopPlatform::Shopee => ec::SHOPEE_DESC_LIMIT as u32,
        ShopPlatform::Momo => ec::MOMO_DESC_LIMIT as u32,
    }
}

/// 該圖在此平台/類別下是否需要選擇補白或裁切。
#[flutter_rust_bridge::frb(sync)]
pub fn needs_fit_choice(
    platform: ShopPlatform,
    category: ImgCategory,
    width: u32,
    height: u32,
) -> bool {
    ec::needs_fit_choice(platform.into(), category.into(), width, height)
}

#[derive(Clone, Debug)]
pub struct EcomInput {
    pub path: String,
    pub fit: Fit,
}

#[derive(Clone, Debug)]
pub struct EcomJob {
    pub name: String,
    pub main: Vec<EcomInput>,
    pub variant: Vec<EcomInput>,
    pub desc: Vec<String>,
    pub platforms: Vec<ShopPlatform>,
    pub settings: EcomSettings,
}

pub struct OutputInfo {
    pub platform: ShopPlatform,
    pub category: ImgCategory,
    pub file_name: String,
    pub width: u32,
    pub height: u32,
    pub bytes: u64,
    pub quality: u8,
    pub warnings: Vec<String>,
}

pub struct OverflowInfo {
    pub platform: ShopPlatform,
    pub count: u32,
    pub limit: u32,
}

pub struct DescCount {
    pub platform: ShopPlatform,
    pub count: u32,
}

pub struct EcomReport {
    pub output_root: String,
    pub desc_counts: Vec<DescCount>,
    /// 非空 = 預檢失敗，未輸出任何檔案
    pub overflow: Vec<OverflowInfo>,
    pub outputs: Vec<OutputInfo>,
    pub written_count: u32,
    pub disposed_count: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EcomStage {
    Preparing,
    Encoding,
    Writing,
    Done,
    Failed,
}

pub struct EcomProgress {
    pub stage: EcomStage,
    /// Encoding 時：已完成 / 總數
    pub done: u32,
    pub total: u32,
    /// Done 時的結果
    pub report: Option<EcomReport>,
    /// Failed 時的錯誤訊息
    pub error: Option<String>,
}

impl EcomProgress {
    fn stage(stage: EcomStage) -> Self {
        Self {
            stage,
            done: 0,
            total: 0,
            report: None,
            error: None,
        }
    }
}

fn to_core(job: EcomJob) -> ec::Job {
    let inputs = |v: Vec<EcomInput>| {
        v.into_iter()
            .map(|i| ec::InputImage {
                path: PathBuf::from(i.path),
                fit: i.fit.into(),
            })
            .collect()
    };
    ec::Job {
        name: job.name,
        main: inputs(job.main),
        variant: inputs(job.variant),
        desc: job.desc.into_iter().map(PathBuf::from).collect(),
        platforms: job.platforms.into_iter().map(Into::into).collect(),
        settings: ec::Settings {
            shopee_max_desc: job.settings.shopee_max_desc as usize,
            momo_max_desc: job.settings.momo_max_desc as usize,
            smart_cut: job.settings.smart_cut,
            shopee_max_width: job.settings.shopee_max_width,
            momo_min_last: job.settings.momo_min_last,
            max_quality: job.settings.max_quality.clamp(60, 100),
            chroma444: job.settings.chroma444,
            ..ec::Settings::default()
        },
        output_root: None,
    }
}

fn to_report(r: ec::RunReport) -> EcomReport {
    EcomReport {
        output_root: r.output_root.to_string_lossy().into_owned(),
        desc_counts: r
            .desc_counts
            .into_iter()
            .map(|(p, n)| DescCount {
                platform: p.into(),
                count: n as u32,
            })
            .collect(),
        overflow: r
            .overflow
            .into_iter()
            .map(|o| OverflowInfo {
                platform: o.platform.into(),
                count: o.count as u32,
                limit: o.limit as u32,
            })
            .collect(),
        outputs: r
            .outputs
            .into_iter()
            .map(|o| OutputInfo {
                platform: o.platform.into(),
                category: o.category.into(),
                file_name: o.file_name,
                width: o.width,
                height: o.height,
                bytes: o.bytes as u64,
                quality: o.quality,
                warnings: o.warnings,
            })
            .collect(),
        written_count: r.written.len() as u32,
        disposed_count: r.disposed.len() as u32,
    }
}

/// 執行電商模式；透過 sink 回報進度，最後送出 Done 或 Failed。
/// `dry_run` = 只預檢與壓縮、不寫檔。
pub fn run_ecommerce(job: EcomJob, dry_run: bool, sink: StreamSink<EcomProgress>) {
    let job = to_core(job);
    let progress = |p: ec::Progress| {
        let _ = sink.add(match p {
            ec::Progress::Preparing => EcomProgress::stage(EcomStage::Preparing),
            ec::Progress::Encoding { done, total } => EcomProgress {
                done: done as u32,
                total: total as u32,
                ..EcomProgress::stage(EcomStage::Encoding)
            },
            ec::Progress::Writing => EcomProgress::stage(EcomStage::Writing),
        });
    };
    let res = ec::run_with_progress(&job, Disposal::platform_default(), dry_run, &progress);
    let _ = sink.add(match res {
        Ok(r) => EcomProgress {
            report: Some(to_report(r)),
            ..EcomProgress::stage(EcomStage::Done)
        },
        Err(e) => EcomProgress {
            error: Some(e.to_string()),
            ..EcomProgress::stage(EcomStage::Failed)
        },
    });
}
