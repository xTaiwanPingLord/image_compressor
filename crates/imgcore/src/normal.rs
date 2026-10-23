//! 普通模式：對照 Caesium 的壓縮 / 縮放 / 輸出設定。

use crate::cleanup::{self, Disposal};
use crate::{Error, Result, exif, jpeg_lossless};
use image::{
    DynamicImage, ImageDecoder, ImageEncoder, ImageFormat, ImageReader, RgbaImage,
    metadata::Orientation,
};
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::io::Cursor;
use std::path::{Path, PathBuf};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum OutFormat {
    /// 維持原格式（BMP / TIFF / GIF 轉 PNG）
    #[default]
    Same,
    Jpeg,
    Png,
    Webp,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum Chroma {
    /// 品質 ≥ 90 用 4:4:4，否則 4:2:0
    #[default]
    Auto,
    S444,
    S422,
    S420,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum ResizeMode {
    #[default]
    None,
    /// 百分比（value = %）
    Percentage,
    /// 固定寬度（value = px）
    Width,
    /// 固定高度（value = px）
    Height,
    /// 長邊（value = px）
    LongEdge,
    /// 短邊（value = px）
    ShortEdge,
    /// 等比縮放到框內（value × value2）
    FitBox,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Options {
    // ---- Compression ----
    /// 無損：JPEG 只做霍夫曼 / progressive 最佳化；PNG 用 oxipng；WebP 用 lossless
    pub lossless: bool,
    /// 1–100
    pub quality: u8,
    /// Some = 依目標大小（bytes）搜尋品質
    pub max_size: Option<u64>,
    pub jpeg_chroma: Chroma,
    /// oxipng 最佳化等級 0–6
    pub png_level: u8,
    /// 保留 EXIF / XMP 等中繼資料（ICC 色彩描述檔一律保留）
    pub keep_metadata: bool,
    /// 保留原檔的修改 / 存取時間
    pub keep_dates: bool,

    // ---- Resize ----
    pub resize: ResizeMode,
    pub resize_value: u32,
    pub resize_value2: u32,
    /// 不放大
    pub no_enlarge: bool,

    // ---- Output ----
    pub format: OutFormat,
    /// None = 與原檔相同資料夾
    pub output_dir: Option<PathBuf>,
    /// 檔名後綴，例如 "_compressed"
    pub suffix: String,
    /// 輸出到其他資料夾時保留子資料夾結構（相對於加入時的資料夾）
    pub keep_structure: bool,
    /// 壓縮後比原檔大時改為輸出原檔
    pub skip_if_bigger: bool,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            lossless: false,
            quality: 80,
            max_size: None,
            jpeg_chroma: Chroma::Auto,
            png_level: 3,
            keep_metadata: true,
            keep_dates: false,
            resize: ResizeMode::None,
            resize_value: 100,
            resize_value2: 0,
            no_enlarge: true,
            format: OutFormat::Same,
            output_dir: None,
            suffix: "_compressed".into(),
            keep_structure: false,
            skip_if_bigger: true,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub enum Kind {
    Jpeg,
    Png,
    Webp,
}

impl Kind {
    pub fn ext(self) -> &'static str {
        match self {
            Kind::Jpeg => "jpg",
            Kind::Png => "png",
            Kind::Webp => "webp",
        }
    }
}

/// 壓縮結果（記憶體內）。
#[derive(Clone, Debug)]
pub struct Compressed {
    pub data: Vec<u8>,
    pub kind: Kind,
    pub width: u32,
    pub height: u32,
    /// 實際使用的品質（無損為 None）
    pub quality: Option<u8>,
    pub warnings: Vec<String>,
}

/// 依縮放設定計算輸出尺寸。
pub fn target_size(w: u32, h: u32, o: &Options) -> (u32, u32) {
    let v = o.resize_value.max(1) as f64;
    let (wf, hf) = (w as f64, h as f64);
    let mut s = match o.resize {
        ResizeMode::None => 1.0,
        ResizeMode::Percentage => v / 100.0,
        ResizeMode::Width => v / wf,
        ResizeMode::Height => v / hf,
        ResizeMode::LongEdge => v / wf.max(hf),
        ResizeMode::ShortEdge => v / wf.min(hf),
        ResizeMode::FitBox => {
            let v2 = o.resize_value2.max(1) as f64;
            (v / wf).min(v2 / hf)
        }
    };
    if o.no_enlarge {
        s = s.min(1.0);
    }
    if (s - 1.0).abs() < 1e-9 {
        return (w, h);
    }
    (
        ((wf * s).round() as u32).max(1),
        ((hf * s).round() as u32).max(1),
    )
}

fn input_kind(fmt: Option<ImageFormat>) -> Option<Kind> {
    match fmt? {
        ImageFormat::Jpeg => Some(Kind::Jpeg),
        ImageFormat::Png => Some(Kind::Png),
        ImageFormat::WebP => Some(Kind::Webp),
        _ => None,
    }
}

/// 輸出格式。
pub fn output_kind(input: Option<ImageFormat>, o: &Options) -> Kind {
    match o.format {
        OutFormat::Jpeg => Kind::Jpeg,
        OutFormat::Png => Kind::Png,
        OutFormat::Webp => Kind::Webp,
        OutFormat::Same => input_kind(input).unwrap_or(Kind::Png),
    }
}

struct Decoded {
    img: DynamicImage,
    icc: Option<Vec<u8>>,
    exif: Option<Vec<u8>>,
}

fn decode(data: &[u8]) -> Result<Decoded> {
    let err = |e: image::ImageError| Error::Decode {
        path: String::new(),
        msg: e.to_string(),
    };
    let reader = ImageReader::new(Cursor::new(data)).with_guessed_format()?;
    let mut dec = reader.into_decoder().map_err(err)?;
    let icc = dec.icc_profile().ok().flatten();
    let exif = dec.exif_metadata().ok().flatten();
    let orient = dec.orientation().unwrap_or(Orientation::NoTransforms);
    let mut img = DynamicImage::from_decoder(dec).map_err(err)?;
    img.apply_orientation(orient);
    Ok(Decoded { img, icc, exif })
}

fn is_srgb(icc: &[u8]) -> bool {
    qcms::Profile::new_from_slice(icc, false)
        .map(|p| p.is_sRGB())
        .unwrap_or(true)
}

/// 轉 sRGB（用於無法嵌入 ICC 的輸出）。
fn rgba_to_srgb(rgba: &mut RgbaImage, icc: Option<&[u8]>) {
    let Some(icc) = icc else { return };
    let Some(src) = qcms::Profile::new_from_slice(icc, false) else {
        return;
    };
    if src.is_sRGB() {
        return;
    }
    let mut dst = qcms::Profile::new_sRGB();
    dst.precache_output_transform();
    if let Some(t) =
        qcms::Transform::new(&src, &dst, qcms::DataType::RGBA8, qcms::Intent::Perceptual)
    {
        t.apply(rgba.as_mut());
    }
}

fn resize_rgba(img: &RgbaImage, w: u32, h: u32) -> RgbaImage {
    if img.dimensions() == (w, h) {
        return img.clone();
    }
    use fast_image_resize as fr;
    let src = fr::images::Image::from_vec_u8(
        img.width(),
        img.height(),
        img.as_raw().clone(),
        fr::PixelType::U8x4,
    )
    .expect("src");
    let mut dst = fr::images::Image::new(w, h, fr::PixelType::U8x4);
    let opts = fr::ResizeOptions::new()
        .resize_alg(fr::ResizeAlg::Convolution(fr::FilterType::Lanczos3))
        .use_alpha(true);
    fr::Resizer::new()
        .resize(&src, &mut dst, &opts)
        .expect("resize");
    RgbaImage::from_raw(w, h, dst.into_vec()).expect("dst")
}

fn has_alpha(img: &RgbaImage) -> bool {
    img.pixels().any(|p| p.0[3] != 255)
}

fn flatten_white(img: &RgbaImage) -> image::RgbImage {
    image::RgbImage::from_fn(img.width(), img.height(), |x, y| {
        let p = img.get_pixel(x, y).0;
        let a = p[3] as u32;
        let c = |v: u8| ((v as u32 * a + 255 * (255 - a) + 127) / 255) as u8;
        image::Rgb([c(p[0]), c(p[1]), c(p[2])])
    })
}

fn chroma_for(c: Chroma, q: u8, lossless: bool) -> ((u8, u8), (u8, u8)) {
    match c {
        _ if lossless => ((1, 1), (1, 1)),
        Chroma::S444 => ((1, 1), (1, 1)),
        Chroma::S422 => ((2, 1), (2, 1)),
        Chroma::S420 => ((2, 2), (2, 2)),
        Chroma::Auto if q >= 90 => ((1, 1), (1, 1)),
        Chroma::Auto => ((2, 2), (2, 2)),
    }
}

fn encode_jpeg(
    img: &image::RgbImage,
    q: u8,
    chroma: ((u8, u8), (u8, u8)),
    icc: Option<&[u8]>,
    exif_app1: Option<&[u8]>,
) -> Result<Vec<u8>> {
    let (w, h) = img.dimensions();
    std::panic::catch_unwind(|| -> std::io::Result<Vec<u8>> {
        let mut c = mozjpeg::Compress::new(mozjpeg::ColorSpace::JCS_RGB);
        c.set_size(w as usize, h as usize);
        c.set_quality(q as f32);
        c.set_chroma_sampling_pixel_sizes(chroma.0, chroma.1);
        let mut s = c.start_compress(Vec::new())?;
        if let Some(e) = exif_app1 {
            s.write_marker(mozjpeg::Marker::APP(1), e);
        }
        if let Some(i) = icc {
            s.write_icc_profile(i);
        }
        s.write_scanlines(img.as_raw())?;
        s.finish()
    })
    .map_err(|_| Error::Encode("mozjpeg panic".into()))?
    .map_err(|e| Error::Encode(e.to_string()))
}

fn png_strip(keep_metadata: bool) -> oxipng::StripChunks {
    if keep_metadata {
        oxipng::StripChunks::None
    } else {
        oxipng::StripChunks::Safe
    }
}

fn oxipng_opt(data: &[u8], level: u8, keep_metadata: bool) -> Result<Vec<u8>> {
    let mut o = oxipng::Options::from_preset(level.min(6));
    o.strip = png_strip(keep_metadata);
    oxipng::optimize_from_memory(data, &o).map_err(|e| Error::Encode(e.to_string()))
}

fn encode_png_lossless(img: &RgbaImage, icc: Option<&[u8]>, o: &Options) -> Result<Vec<u8>> {
    let mut buf = Vec::new();
    let mut enc = image::codecs::png::PngEncoder::new_with_quality(
        &mut buf,
        image::codecs::png::CompressionType::Fast,
        image::codecs::png::FilterType::Adaptive,
    );
    if let Some(i) = icc {
        let _ = enc.set_icc_profile(i.to_vec());
    }
    let (w, h) = img.dimensions();
    if has_alpha(img) {
        enc.write_image(img.as_raw(), w, h, image::ExtendedColorType::Rgba8)
    } else {
        let rgb = DynamicImage::ImageRgba8(img.clone()).into_rgb8();
        enc.write_image(rgb.as_raw(), w, h, image::ExtendedColorType::Rgb8)
    }
    .map_err(|e| Error::Encode(e.to_string()))?;
    oxipng_opt(&buf, o.png_level, o.keep_metadata)
}

/// 品質 → 調色盤色數（有損 PNG）。
fn png_colors(q: u8) -> i32 {
    if q >= 90 {
        256
    } else {
        (16.0 + q as f64 / 90.0 * 240.0).round() as i32
    }
}

/// 有損 PNG：量化成調色盤（quantizr，MIT 授權）後再用 oxipng 最佳化。
fn encode_png_lossy(img: &RgbaImage, q: u8, o: &Options) -> Result<Vec<u8>> {
    let (w, h) = img.dimensions();
    let qi = quantizr::Image::new(img.as_raw(), w as usize, h as usize)
        .map_err(|e| Error::Encode(format!("{e:?}")))?;
    let mut opts = quantizr::Options::default();
    opts.set_max_colors(png_colors(q))
        .map_err(|e| Error::Encode(format!("{e:?}")))?;
    let mut res = quantizr::QuantizeResult::quantize(&qi, &opts);
    let _ = res.set_dithering_level(1.0);
    let mut idx = vec![0u8; (w * h) as usize];
    res.remap_image(&qi, &mut idx)
        .map_err(|e| Error::Encode(format!("{e:?}")))?;
    let pal = res.get_palette();
    let n = pal.count as usize;
    let mut plte = Vec::with_capacity(n * 3);
    let mut trns = Vec::with_capacity(n);
    for c in &pal.entries[..n] {
        plte.extend_from_slice(&[c.r, c.g, c.b]);
        trns.push(c.a);
    }
    let mut buf = Vec::new();
    {
        let mut enc = png::Encoder::new(&mut buf, w, h);
        enc.set_color(png::ColorType::Indexed);
        enc.set_depth(png::BitDepth::Eight);
        enc.set_palette(plte);
        if trns.iter().any(|&a| a != 255) {
            enc.set_trns(trns);
        }
        let mut wr = enc
            .write_header()
            .map_err(|e| Error::Encode(e.to_string()))?;
        wr.write_image_data(&idx)
            .map_err(|e| Error::Encode(e.to_string()))?;
    }
    oxipng_opt(&buf, o.png_level, o.keep_metadata)
}

fn encode_webp(img: &RgbaImage, q: Option<u8>) -> Vec<u8> {
    let (w, h) = img.dimensions();
    let enc = webp::Encoder::from_rgba(img.as_raw(), w, h);
    match q {
        None => enc.encode_lossless().to_vec(),
        Some(q) => enc.encode(q as f32).to_vec(),
    }
}

/// 在記憶體中壓縮（不寫檔）。預覽與批次共用。
pub fn compress_bytes(data: &[u8], o: &Options) -> Result<Compressed> {
    let in_fmt = image::guess_format(data).ok();
    let kind = output_kind(in_fmt, o);
    let mut warnings = Vec::new();

    let resizing = o.resize != ResizeMode::None;
    let same_kind = input_kind(in_fmt) == Some(kind);

    // 快速無損路徑：不解碼
    if o.lossless && same_kind && !resizing {
        let (w, h) = image::ImageReader::new(Cursor::new(data))
            .with_guessed_format()?
            .into_dimensions()
            .map_err(|e| Error::Decode {
                path: String::new(),
                msg: e.to_string(),
            })?;
        match kind {
            Kind::Jpeg => {
                let out = jpeg_lossless::optimize(data, o.keep_metadata)?;
                return Ok(Compressed {
                    data: out,
                    kind,
                    width: w,
                    height: h,
                    quality: None,
                    warnings,
                });
            }
            Kind::Png => {
                let out = oxipng_opt(data, o.png_level, o.keep_metadata)?;
                return Ok(Compressed {
                    data: out,
                    kind,
                    width: w,
                    height: h,
                    quality: None,
                    warnings,
                });
            }
            Kind::Webp => {}
        }
    }

    let dec = decode(data)?;
    if matches!(in_fmt, Some(ImageFormat::Gif)) {
        warnings.push("GIF 只取第一格".into());
    }
    let mut rgba = dec.img.to_rgba8();
    let (tw, th) = target_size(rgba.width(), rgba.height(), o);
    rgba = resize_rgba(&rgba, tw, th);

    let icc = dec.icc.as_deref().filter(|i| !is_srgb(i));
    let exif_app1 = if o.keep_metadata {
        dec.exif
            .as_deref()
            .map(|e| exif::to_app1(&exif::reset_orientation(e)))
    } else {
        None
    };

    // 單一品質下的編碼
    let encode_q = |q: Option<u8>| -> Result<Vec<u8>> {
        match kind {
            Kind::Jpeg => {
                let q = q.unwrap_or(100);
                let rgb = flatten_white(&rgba);
                encode_jpeg(
                    &rgb,
                    q,
                    chroma_for(o.jpeg_chroma, q, o.lossless),
                    icc,
                    exif_app1.as_deref(),
                )
            }
            Kind::Png => match q {
                None => encode_png_lossless(&rgba, icc, o),
                Some(q) => {
                    let mut s = rgba.clone();
                    rgba_to_srgb(&mut s, icc);
                    encode_png_lossy(&s, q, o)
                }
            },
            Kind::Webp => {
                let mut s = rgba.clone();
                rgba_to_srgb(&mut s, icc);
                Ok(encode_webp(&s, q))
            }
        }
    };

    if o.lossless {
        if kind == Kind::Jpeg {
            warnings.push("JPEG 需重新編碼（縮放或轉檔），以品質 100、4:4:4 輸出".into());
        }
        let q = if kind == Kind::Jpeg { Some(100) } else { None };
        let out = encode_q(if kind == Kind::Jpeg { q } else { None })?;
        return Ok(Compressed {
            data: out,
            kind,
            width: tw,
            height: th,
            quality: q,
            warnings,
        });
    }

    // PNG 品質 100 視為無損
    let lossy_q = |q: u8| {
        if kind == Kind::Png && q >= 100 {
            None
        } else {
            Some(q)
        }
    };

    match o.max_size {
        None => {
            let q = o.quality.clamp(1, 100);
            let out = encode_q(lossy_q(q))?;
            Ok(Compressed {
                data: out,
                kind,
                width: tw,
                height: th,
                quality: Some(q),
                warnings,
            })
        }
        Some(max) => {
            // 二分搜尋最高可行品質
            let top = encode_q(lossy_q(100))?;
            if top.len() as u64 <= max {
                return Ok(Compressed {
                    data: top,
                    kind,
                    width: tw,
                    height: th,
                    quality: Some(100),
                    warnings,
                });
            }
            let bottom = encode_q(lossy_q(1))?;
            if bottom.len() as u64 > max {
                warnings.push(format!(
                    "品質降到 1 仍有 {} bytes，超過目標 {}",
                    bottom.len(),
                    max
                ));
                return Ok(Compressed {
                    data: bottom,
                    kind,
                    width: tw,
                    height: th,
                    quality: Some(1),
                    warnings,
                });
            }
            let (mut lo, mut hi, mut best) = (1u8, 100u8, bottom);
            while hi - lo > 1 {
                let m = lo + (hi - lo) / 2;
                let d = encode_q(lossy_q(m))?;
                if d.len() as u64 <= max {
                    lo = m;
                    best = d;
                } else {
                    hi = m;
                }
            }
            Ok(Compressed {
                data: best,
                kind,
                width: tw,
                height: th,
                quality: Some(lo),
                warnings,
            })
        }
    }
}

/// 輸出路徑。`base` = 加入時的資料夾（保留結構用）。
pub fn output_path(input: &Path, base: Option<&Path>, kind: Kind, o: &Options) -> PathBuf {
    let parent = input.parent().unwrap_or(Path::new(""));
    let dir = match &o.output_dir {
        None => parent.to_path_buf(),
        Some(d) => match (o.keep_structure, base) {
            (true, Some(b)) => match parent.strip_prefix(b) {
                Ok(rel) => d.join(rel),
                Err(_) => d.clone(),
            },
            _ => d.clone(),
        },
    };
    let stem = input
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    dir.join(format!("{stem}{}.{}", o.suffix, kind.ext()))
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub enum Status {
    Done,
    /// 壓縮後較大，改輸出原檔
    KeptOriginal,
    Failed,
}

#[derive(Clone, Debug, Serialize)]
pub struct FileResult {
    pub input: PathBuf,
    pub output: Option<PathBuf>,
    pub original_size: u64,
    pub new_size: u64,
    pub width: u32,
    pub height: u32,
    pub status: Status,
    pub error: Option<String>,
    pub warnings: Vec<String>,
}

fn same_file(a: &Path, b: &Path) -> bool {
    match (std::fs::canonicalize(a), std::fs::canonicalize(b)) {
        (Ok(x), Ok(y)) => x == y,
        _ => a == b,
    }
}

/// 壓縮並寫檔。
pub fn process_file(input: &Path, base: Option<&Path>, o: &Options, how: Disposal) -> FileResult {
    let mut r = FileResult {
        input: input.to_path_buf(),
        output: None,
        original_size: 0,
        new_size: 0,
        width: 0,
        height: 0,
        status: Status::Failed,
        error: None,
        warnings: vec![],
    };
    let src_meta = std::fs::metadata(input).ok();
    let res = (|| -> Result<()> {
        let data = std::fs::read(input)?;
        r.original_size = data.len() as u64;
        let in_fmt = image::guess_format(&data).ok();
        let c = compress_bytes(&data, o)?;
        r.width = c.width;
        r.height = c.height;
        r.warnings = c.warnings.clone();
        let out_path = output_path(input, base, c.kind, o);
        let bigger = c.data.len() as u64 >= data.len() as u64;
        let same_kind = input_kind(in_fmt) == Some(c.kind);
        let resized = (c.width, c.height) != image::image_dimensions(input).unwrap_or((0, 0));
        let overwrite = same_file(input, &out_path);

        let bytes: &[u8] = if o.skip_if_bigger && bigger && same_kind && !resized {
            r.status = Status::KeptOriginal;
            &data
        } else {
            r.status = Status::Done;
            &c.data
        };
        r.new_size = bytes.len() as u64;

        if overwrite {
            if r.status == Status::KeptOriginal {
                r.output = Some(out_path);
                return Ok(());
            }
            // 覆寫原檔：先把原檔移到垃圾桶
            cleanup::dispose(std::slice::from_ref(&input.to_path_buf()), how)?;
        }
        if let Some(d) = out_path.parent() {
            std::fs::create_dir_all(d)?;
        }
        std::fs::write(&out_path, bytes)?;
        if o.keep_dates
            && let Some(meta) = &src_meta
        {
            let at = filetime::FileTime::from_last_access_time(meta);
            let mt = filetime::FileTime::from_last_modification_time(meta);
            let _ = filetime::set_file_times(&out_path, at, mt);
        }
        r.output = Some(out_path);
        Ok(())
    })();
    if let Err(e) = res {
        r.status = Status::Failed;
        r.error = Some(e.to_string());
    }
    r
}

/// 批次處理；progress(索引, 結果) 於每個檔案完成時呼叫。
pub fn run_batch(
    inputs: &[(PathBuf, Option<PathBuf>)],
    o: &Options,
    how: Disposal,
    progress: &(dyn Fn(usize, &FileResult) + Sync),
) -> Vec<FileResult> {
    inputs
        .par_iter()
        .enumerate()
        .map(|(i, (p, base))| {
            let r = process_file(p, base.as_deref(), o, how);
            progress(i, &r);
            r
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{Rgb, RgbImage, Rgba};

    fn photo(w: u32, h: u32) -> RgbImage {
        let mut s = 12345u32;
        RgbImage::from_fn(w, h, |x, y| {
            s ^= s << 13;
            s ^= s >> 17;
            s ^= s << 5;
            let n = (s % 32) as i32 - 16;
            let c = |b: i32| (b + n).clamp(0, 255) as u8;
            Rgb([
                c((x * 255 / w) as i32),
                c((y * 255 / h) as i32),
                c(((x / 40 + y / 40) % 2 * 120) as i32),
            ])
        })
    }

    fn jpg(img: &RgbImage, q: u8) -> Vec<u8> {
        crate::encode::encode_jpeg(img, q, crate::encode::Mode::Chroma444Plain).unwrap()
    }

    fn png_bytes(img: &DynamicImage) -> Vec<u8> {
        let mut v = Vec::new();
        img.write_to(&mut Cursor::new(&mut v), ImageFormat::Png)
            .unwrap();
        v
    }

    #[test]
    fn sizes() {
        let mut o = Options {
            resize: ResizeMode::LongEdge,
            resize_value: 1000,
            ..Default::default()
        };
        assert_eq!(target_size(4000, 3000, &o), (1000, 750));
        assert_eq!(target_size(500, 300, &o), (500, 300)); // 不放大
        o.no_enlarge = false;
        assert_eq!(target_size(500, 300, &o), (1000, 600));
        o.resize = ResizeMode::Percentage;
        o.resize_value = 50;
        assert_eq!(target_size(4000, 3000, &o), (2000, 1500));
        o.resize = ResizeMode::FitBox;
        o.resize_value = 800;
        o.resize_value2 = 800;
        assert_eq!(target_size(4000, 2000, &o), (800, 400));
        o.resize = ResizeMode::ShortEdge;
        o.resize_value = 600;
        assert_eq!(target_size(4000, 2000, &o), (1200, 600));
        o.resize = ResizeMode::Height;
        o.resize_value = 100;
        assert_eq!(target_size(400, 200, &o), (200, 100));
    }

    #[test]
    fn jpeg_lossy_smaller() {
        let src = jpg(&photo(800, 600), 95);
        let c = compress_bytes(&src, &Options::default()).unwrap();
        assert_eq!(c.kind, Kind::Jpeg);
        assert!(
            c.data.len() < src.len() / 2,
            "{} {}",
            c.data.len(),
            src.len()
        );
        assert_eq!((c.width, c.height), (800, 600));
    }

    #[test]
    fn jpeg_lossless_identical_pixels() {
        let src = jpg(&photo(400, 300), 90);
        let o = Options {
            lossless: true,
            ..Default::default()
        };
        let c = compress_bytes(&src, &o).unwrap();
        assert!(c.data.len() < src.len());
        let a = image::load_from_memory(&src).unwrap().to_rgb8();
        let b = image::load_from_memory(&c.data).unwrap().to_rgb8();
        assert_eq!(a.as_raw(), b.as_raw());
    }

    #[test]
    fn max_size_search() {
        let src = jpg(&photo(1200, 900), 95);
        let o = Options {
            max_size: Some(60_000),
            ..Default::default()
        };
        let c = compress_bytes(&src, &o).unwrap();
        assert!(c.data.len() <= 60_000);
        let q = c.quality.unwrap();
        assert!(q > 1 && q < 100);
    }

    #[test]
    fn png_lossy_and_lossless() {
        let img = DynamicImage::ImageRgb8(photo(300, 200));
        let src = png_bytes(&img);
        let lossy = compress_bytes(
            &src,
            &Options {
                quality: 60,
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(lossy.kind, Kind::Png);
        assert!(lossy.data.len() < src.len());
        let ll = compress_bytes(
            &src,
            &Options {
                lossless: true,
                ..Default::default()
            },
        )
        .unwrap();
        let back = image::load_from_memory(&ll.data).unwrap().to_rgb8();
        assert_eq!(back.as_raw(), img.to_rgb8().as_raw());
    }

    #[test]
    fn png_alpha_kept_in_png_and_flattened_in_jpeg() {
        let mut im = RgbaImage::from_pixel(64, 64, Rgba([0, 0, 0, 0]));
        im.put_pixel(10, 10, Rgba([255, 0, 0, 255]));
        let src = png_bytes(&DynamicImage::ImageRgba8(im));
        let p = compress_bytes(
            &src,
            &Options {
                quality: 80,
                ..Default::default()
            },
        )
        .unwrap();
        let back = image::load_from_memory(&p.data).unwrap().to_rgba8();
        assert_eq!(back.get_pixel(0, 0).0[3], 0);
        let j = compress_bytes(
            &src,
            &Options {
                format: OutFormat::Jpeg,
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(j.kind, Kind::Jpeg);
        let back = image::load_from_memory(&j.data).unwrap().to_rgb8();
        assert!(back.get_pixel(0, 0).0.iter().all(|&c| c > 245));
    }

    #[test]
    fn webp_convert() {
        let src = jpg(&photo(400, 300), 95);
        let o = Options {
            format: OutFormat::Webp,
            quality: 75,
            ..Default::default()
        };
        let c = compress_bytes(&src, &o).unwrap();
        assert_eq!(c.kind, Kind::Webp);
        assert_eq!(&c.data[..4], b"RIFF");
        let back = image::load_from_memory(&c.data).unwrap();
        assert_eq!((back.width(), back.height()), (400, 300));
    }

    #[test]
    fn exif_kept_and_orientation_reset() {
        // 400x300 存成方向 6（需順時針轉 90°）
        let img = photo(400, 300);
        let base = jpg(&img, 95);
        let mut tiff = b"II*\0\x08\0\0\0\x01\0\x12\x01\x03\0\x01\0\0\0\x06\0\0\0\0\0\0\0".to_vec();
        let mut with = base[..2].to_vec();
        let mut app1 = b"Exif\0\0".to_vec();
        app1.append(&mut tiff);
        with.extend_from_slice(&[0xFF, 0xE1]);
        with.extend_from_slice(&((app1.len() + 2) as u16).to_be_bytes());
        with.extend_from_slice(&app1);
        with.extend_from_slice(&base[2..]);

        let c = compress_bytes(&with, &Options::default()).unwrap();
        assert_eq!((c.width, c.height), (300, 400)); // 已轉正
        let mut dec = ImageReader::new(Cursor::new(&c.data))
            .with_guessed_format()
            .unwrap()
            .into_decoder()
            .unwrap();
        assert_eq!(dec.orientation().unwrap(), Orientation::NoTransforms);
        assert!(dec.exif_metadata().unwrap().is_some());

        let c2 = compress_bytes(
            &with,
            &Options {
                keep_metadata: false,
                ..Default::default()
            },
        )
        .unwrap();
        let mut dec = ImageReader::new(Cursor::new(&c2.data))
            .with_guessed_format()
            .unwrap()
            .into_decoder()
            .unwrap();
        assert!(dec.exif_metadata().unwrap().is_none());
    }

    #[test]
    fn output_paths() {
        let o = Options::default();
        assert_eq!(
            output_path(Path::new("/a/b/x.jpg"), None, Kind::Jpeg, &o),
            PathBuf::from("/a/b/x_compressed.jpg")
        );
        let o = Options {
            output_dir: Some("/out".into()),
            keep_structure: true,
            suffix: String::new(),
            ..Default::default()
        };
        assert_eq!(
            output_path(
                Path::new("/a/b/c/x.png"),
                Some(Path::new("/a")),
                Kind::Webp,
                &o
            ),
            PathBuf::from("/out/b/c/x.webp")
        );
    }

    #[test]
    fn batch_writes_and_keeps_original_when_bigger() {
        let d = tempfile::tempdir().unwrap();
        // 已高度壓縮的小 JPEG：再壓 q100 會變大
        let small = jpg(&photo(200, 150), 30);
        let a = d.path().join("a.jpg");
        std::fs::write(&a, &small).unwrap();
        let big = jpg(&photo(800, 600), 98);
        let b = d.path().join("sub").join("b.jpg");
        std::fs::create_dir_all(b.parent().unwrap()).unwrap();
        std::fs::write(&b, &big).unwrap();

        let o = Options {
            quality: 100,
            keep_dates: true,
            ..Default::default()
        };
        let res = run_batch(
            &[(a.clone(), None), (b.clone(), None)],
            &o,
            Disposal::OldFolder,
            &|_, _| {},
        );
        assert_eq!(res[0].status, Status::KeptOriginal);
        assert_eq!(
            std::fs::read(d.path().join("a_compressed.jpg")).unwrap(),
            small
        );

        let o = Options {
            quality: 70,
            ..Default::default()
        };
        let res = run_batch(&[(b.clone(), None)], &o, Disposal::OldFolder, &|_, _| {});
        assert_eq!(res[0].status, Status::Done);
        assert!(res[0].new_size < res[0].original_size);
        assert!(d.path().join("sub/b_compressed.jpg").exists());
    }

    #[test]
    fn overwrite_original_moves_old_to_old_folder() {
        let d = tempfile::tempdir().unwrap();
        let a = d.path().join("a.jpg");
        std::fs::write(&a, jpg(&photo(600, 400), 98)).unwrap();
        let o = Options {
            suffix: String::new(),
            quality: 60,
            ..Default::default()
        };
        let r = process_file(&a, None, &o, Disposal::OldFolder);
        assert_eq!(r.status, Status::Done);
        assert!(d.path().join("_old/a.jpg").exists());
        assert!(
            std::fs::metadata(&a).unwrap().len()
                < std::fs::metadata(d.path().join("_old/a.jpg"))
                    .unwrap()
                    .len()
        );
    }
}
