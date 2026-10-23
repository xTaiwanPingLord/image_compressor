//! 普通模式 API（包裝 imgcore::normal）。

use crate::frb_generated::StreamSink;
use imgcore::cleanup::Disposal;
use imgcore::{load, natsort, normal as nm};
use std::path::{Path, PathBuf};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OutFormat {
    Same,
    Jpeg,
    Png,
    Webp,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChromaSubsampling {
    Auto,
    S444,
    S422,
    S420,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ResizeMode {
    None,
    Percentage,
    Width,
    Height,
    LongEdge,
    ShortEdge,
    FitBox,
}

#[derive(Clone, Debug)]
pub struct NormalOptions {
    pub lossless: bool,
    pub quality: u8,
    /// 0 = 依品質；>0 = 目標大小（bytes）
    pub max_size: u64,
    pub jpeg_chroma: ChromaSubsampling,
    pub png_level: u8,
    pub keep_metadata: bool,
    pub keep_dates: bool,
    pub resize: ResizeMode,
    pub resize_value: u32,
    pub resize_value2: u32,
    pub no_enlarge: bool,
    pub format: OutFormat,
    /// 空字串 = 與原檔相同資料夾
    pub output_dir: String,
    pub suffix: String,
    pub keep_structure: bool,
    pub skip_if_bigger: bool,
}

fn from_core(o: nm::Options) -> NormalOptions {
    NormalOptions {
        lossless: o.lossless,
        quality: o.quality,
        max_size: o.max_size.unwrap_or(0),
        jpeg_chroma: match o.jpeg_chroma {
            nm::Chroma::Auto => ChromaSubsampling::Auto,
            nm::Chroma::S444 => ChromaSubsampling::S444,
            nm::Chroma::S422 => ChromaSubsampling::S422,
            nm::Chroma::S420 => ChromaSubsampling::S420,
        },
        png_level: o.png_level,
        keep_metadata: o.keep_metadata,
        keep_dates: o.keep_dates,
        resize: match o.resize {
            nm::ResizeMode::None => ResizeMode::None,
            nm::ResizeMode::Percentage => ResizeMode::Percentage,
            nm::ResizeMode::Width => ResizeMode::Width,
            nm::ResizeMode::Height => ResizeMode::Height,
            nm::ResizeMode::LongEdge => ResizeMode::LongEdge,
            nm::ResizeMode::ShortEdge => ResizeMode::ShortEdge,
            nm::ResizeMode::FitBox => ResizeMode::FitBox,
        },
        resize_value: o.resize_value,
        resize_value2: o.resize_value2,
        no_enlarge: o.no_enlarge,
        format: match o.format {
            nm::OutFormat::Same => OutFormat::Same,
            nm::OutFormat::Jpeg => OutFormat::Jpeg,
            nm::OutFormat::Png => OutFormat::Png,
            nm::OutFormat::Webp => OutFormat::Webp,
        },
        output_dir: o
            .output_dir
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_default(),
        suffix: o.suffix,
        keep_structure: o.keep_structure,
        skip_if_bigger: o.skip_if_bigger,
    }
}

fn to_core(o: &NormalOptions) -> nm::Options {
    nm::Options {
        lossless: o.lossless,
        quality: o.quality.clamp(1, 100),
        max_size: (o.max_size > 0).then_some(o.max_size),
        jpeg_chroma: match o.jpeg_chroma {
            ChromaSubsampling::Auto => nm::Chroma::Auto,
            ChromaSubsampling::S444 => nm::Chroma::S444,
            ChromaSubsampling::S422 => nm::Chroma::S422,
            ChromaSubsampling::S420 => nm::Chroma::S420,
        },
        png_level: o.png_level.min(6),
        keep_metadata: o.keep_metadata,
        keep_dates: o.keep_dates,
        resize: match o.resize {
            ResizeMode::None => nm::ResizeMode::None,
            ResizeMode::Percentage => nm::ResizeMode::Percentage,
            ResizeMode::Width => nm::ResizeMode::Width,
            ResizeMode::Height => nm::ResizeMode::Height,
            ResizeMode::LongEdge => nm::ResizeMode::LongEdge,
            ResizeMode::ShortEdge => nm::ResizeMode::ShortEdge,
            ResizeMode::FitBox => nm::ResizeMode::FitBox,
        },
        resize_value: o.resize_value,
        resize_value2: o.resize_value2,
        no_enlarge: o.no_enlarge,
        format: match o.format {
            OutFormat::Same => nm::OutFormat::Same,
            OutFormat::Jpeg => nm::OutFormat::Jpeg,
            OutFormat::Png => nm::OutFormat::Png,
            OutFormat::Webp => nm::OutFormat::Webp,
        },
        output_dir: (!o.output_dir.trim().is_empty()).then(|| PathBuf::from(o.output_dir.trim())),
        suffix: o.suffix.clone(),
        keep_structure: o.keep_structure,
        skip_if_bigger: o.skip_if_bigger,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn default_normal_options() -> NormalOptions {
    from_core(nm::Options::default())
}

/// 加入的檔案；`base` = 拖入的資料夾（保留結構用），單獨檔案為 None。
#[derive(Clone, Debug)]
pub struct NormalInput {
    pub path: String,
    pub base: Option<String>,
}

fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(rd) = std::fs::read_dir(dir) else {
        return;
    };
    let mut entries: Vec<PathBuf> = rd.filter_map(|e| e.ok().map(|e| e.path())).collect();
    natsort::sort_paths(&mut entries);
    for p in entries {
        if p.is_dir() {
            walk(&p, out);
        } else if p.is_file() && load::is_image_path(&p) {
            out.push(p);
        }
    }
}

/// 展開資料夾（含子資料夾）並保留來源資料夾作為 base。
pub fn collect_images_recursive(paths: Vec<String>) -> Vec<NormalInput> {
    let mut out = Vec::new();
    let mut singles: Vec<PathBuf> = Vec::new();
    for p in paths.iter().map(PathBuf::from) {
        if p.is_dir() {
            let mut v = Vec::new();
            walk(&p, &mut v);
            let base = p.to_string_lossy().into_owned();
            out.extend(v.into_iter().map(|f| NormalInput {
                path: f.to_string_lossy().into_owned(),
                base: Some(base.clone()),
            }));
        } else if p.is_file() && load::is_image_path(&p) {
            singles.push(p);
        }
    }
    natsort::sort_paths(&mut singles);
    out.extend(singles.into_iter().map(|f| NormalInput {
        path: f.to_string_lossy().into_owned(),
        base: None,
    }));
    out
}

pub struct PreviewResult {
    /// 壓縮後的檔案內容（可直接顯示）
    pub data: Vec<u8>,
    /// 副檔名：jpg / png / webp
    pub ext: String,
    pub width: u32,
    pub height: u32,
    pub original_size: u64,
    pub quality: Option<u8>,
    pub warnings: Vec<String>,
}

/// 以目前設定在記憶體中壓縮（不寫檔），用於預覽與預估大小。
pub fn preview_compress(path: String, options: NormalOptions) -> anyhow::Result<PreviewResult> {
    let data = std::fs::read(&path)?;
    let c = nm::compress_bytes(&data, &to_core(&options))?;
    Ok(PreviewResult {
        ext: c.kind.ext().into(),
        width: c.width,
        height: c.height,
        original_size: data.len() as u64,
        quality: c.quality,
        warnings: c.warnings,
        data: c.data,
    })
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FileStatus {
    Done,
    KeptOriginal,
    Failed,
}

pub struct FileResult {
    pub index: u32,
    pub output: Option<String>,
    pub original_size: u64,
    pub new_size: u64,
    pub width: u32,
    pub height: u32,
    pub status: FileStatus,
    pub error: Option<String>,
    pub warnings: Vec<String>,
}

/// 批次壓縮並寫檔；每完成一個檔案送出一筆結果，全部完成後 stream 結束。
pub fn run_normal(inputs: Vec<NormalInput>, options: NormalOptions, sink: StreamSink<FileResult>) {
    let o = to_core(&options);
    let list: Vec<(PathBuf, Option<PathBuf>)> = inputs
        .into_iter()
        .map(|i| (PathBuf::from(i.path), i.base.map(PathBuf::from)))
        .collect();
    nm::run_batch(&list, &o, Disposal::platform_default(), &|i, r| {
        let _ = sink.add(FileResult {
            index: i as u32,
            output: r.output.as_ref().map(|p| p.to_string_lossy().into_owned()),
            original_size: r.original_size,
            new_size: r.new_size,
            width: r.width,
            height: r.height,
            status: match r.status {
                nm::Status::Done => FileStatus::Done,
                nm::Status::KeptOriginal => FileStatus::KeptOriginal,
                nm::Status::Failed => FileStatus::Failed,
            },
            error: r.error.clone(),
            warnings: r.warnings.clone(),
        });
    });
}
