//! HEIC / HEIF：自己解析容器（尺寸、旋轉 / 鏡像、ICC、EXIF），像素交給系統解碼器。
//!
//! - Windows：WIC（需安裝「HEIF 影像擴充功能」與「HEVC 視訊擴充功能」）
//! - Linux：執行時載入系統的 libheif（libheif1 + libheif-plugin-libde265）
//! - Android：NDK AImageDecoder（Android 11 / API 30 以上）
//! - macOS / iOS：ImageIO（尚未實作）
//!
//! HEVC 有專利授權問題，因此不內建解碼器。

use crate::{Error, Result};
use image::{DynamicImage, RgbaImage};

/// ftyp 品牌判斷是否為 HEIF（HEVC 編碼；AVIF 不在此列）。
pub fn is_heif(data: &[u8]) -> bool {
    if data.len() < 16 || &data[4..8] != b"ftyp" {
        return false;
    }
    let size = (u32::from_be_bytes([data[0], data[1], data[2], data[3]]) as usize).min(data.len());
    const BRANDS: &[&[u8; 4]] = &[
        b"heic", b"heix", b"heim", b"heis", b"hevc", b"hevx", b"hevm", b"hevs",
    ];
    let major = &data[8..12];
    if BRANDS.iter().any(|b| major == &b[..]) {
        return true;
    }
    // mif1 / msf1 為通用品牌：再看相容品牌是否含 HEVC 系列
    let mut i = 16;
    while i + 4 <= size {
        let b = &data[i..i + 4];
        if BRANDS.iter().any(|x| b == &x[..]) {
            return true;
        }
        i += 4;
    }
    false
}

/// HEIF 的幾何轉換（依 ipma 中出現的順序套用）。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Transform {
    /// 逆時針旋轉 n × 90°
    Rotate(u8),
    /// 鏡像（HEIF 第二版的 mode 定義，與 libheif 一致）：
    /// false = 上下翻轉，true = 左右翻轉
    Mirror(bool),
    /// clap（clean aperture）裁切：x, y, w, h（以當下影像座標計）
    Crop(u32, u32, u32, u32),
}

#[derive(Clone, Debug, Default)]
pub struct Info {
    /// 編碼尺寸（未旋轉）
    pub width: u32,
    pub height: u32,
    pub transforms: Vec<Transform>,
    pub icc: Option<Vec<u8>>,
    /// 純 TIFF 資料（不含 "Exif\0\0"）
    pub exif: Option<Vec<u8>>,
    pub has_alpha: bool,
}

impl Info {
    /// 顯示尺寸（已套用裁切與旋轉）
    pub fn display_size(&self) -> (u32, u32) {
        let (mut w, mut h) = (self.width, self.height);
        for t in &self.transforms {
            match *t {
                Transform::Rotate(n) if n % 2 == 1 => (w, h) = (h, w),
                Transform::Crop(_, _, cw, ch) => (w, h) = (cw, ch),
                _ => {}
            }
        }
        (w, h)
    }
}

fn derr(msg: impl Into<String>) -> Error {
    Error::Decode {
        path: String::new(),
        msg: msg.into(),
    }
}

// ---------- ISOBMFF 解析 ----------

struct Rd<'a> {
    d: &'a [u8],
    p: usize,
}

impl<'a> Rd<'a> {
    fn new(d: &'a [u8]) -> Self {
        Self { d, p: 0 }
    }
    fn left(&self) -> usize {
        self.d.len().saturating_sub(self.p)
    }
    fn bytes(&mut self, n: usize) -> Option<&'a [u8]> {
        let s = self.d.get(self.p..self.p.checked_add(n)?)?;
        self.p += n;
        Some(s)
    }
    fn u8(&mut self) -> Option<u8> {
        Some(self.bytes(1)?[0])
    }
    fn u16(&mut self) -> Option<u16> {
        let b = self.bytes(2)?;
        Some(u16::from_be_bytes([b[0], b[1]]))
    }
    fn u32(&mut self) -> Option<u32> {
        let b = self.bytes(4)?;
        Some(u32::from_be_bytes([b[0], b[1], b[2], b[3]]))
    }
    fn u64(&mut self) -> Option<u64> {
        let b = self.bytes(8)?;
        Some(u64::from_be_bytes(b.try_into().ok()?))
    }
    /// 0 / 4 / 8 bytes 的整數（iloc 用）
    fn uint(&mut self, size: u8) -> Option<u64> {
        match size {
            0 => Some(0),
            4 => self.u32().map(u64::from),
            8 => self.u64(),
            _ => None,
        }
    }
    fn full(&mut self) -> Option<(u8, u32)> {
        let v = self.u32()?;
        Some(((v >> 24) as u8, v & 0x00FF_FFFF))
    }
}

/// 逐一列出 box：(type, payload)
fn boxes(d: &[u8]) -> Vec<([u8; 4], &[u8])> {
    let mut out = Vec::new();
    let mut r = Rd::new(d);
    while r.left() >= 8 {
        let start = r.p;
        let Some(size) = r.u32() else { break };
        let Some(t) = r.bytes(4) else { break };
        let t: [u8; 4] = t.try_into().unwrap();
        let (hdr, total) = match size {
            0 => (8, d.len() - start),
            1 => match r.u64() {
                Some(s) => (16, s as usize),
                None => break,
            },
            s => (8, s as usize),
        };
        if total < hdr || start + total > d.len() {
            break;
        }
        out.push((t, &d[start + hdr..start + total]));
        r.p = start + total;
    }
    out
}

fn find<'a>(list: &[([u8; 4], &'a [u8])], t: &[u8; 4]) -> Option<&'a [u8]> {
    list.iter().find(|(x, _)| x == t).map(|(_, p)| *p)
}

struct Extent {
    offset: u64,
    length: u64,
}

struct Loc {
    method: u8,
    base: u64,
    extents: Vec<Extent>,
}

fn parse_iloc(p: &[u8]) -> Option<Vec<(u32, Loc)>> {
    let mut r = Rd::new(p);
    let (v, _) = r.full()?;
    let a = r.u8()?;
    let b = r.u8()?;
    let (off_sz, len_sz, base_sz) = (a >> 4, a & 15, b >> 4);
    let idx_sz = if v >= 1 { b & 15 } else { 0 };
    let n = if v < 2 { r.u16()? as u32 } else { r.u32()? };
    let mut out = Vec::new();
    for _ in 0..n {
        let id = if v < 2 { r.u16()? as u32 } else { r.u32()? };
        let method = if v >= 1 { (r.u16()? & 15) as u8 } else { 0 };
        let _dref = r.u16()?;
        let base = r.uint(base_sz)?;
        let ec = r.u16()?;
        let mut extents = Vec::new();
        for _ in 0..ec {
            if v >= 1 && idx_sz > 0 {
                r.uint(idx_sz)?;
            }
            let offset = r.uint(off_sz)?;
            let length = r.uint(len_sz)?;
            extents.push(Extent { offset, length });
        }
        out.push((
            id,
            Loc {
                method,
                base,
                extents,
            },
        ));
    }
    Some(out)
}

/// iinf → (item_id, item_type)
fn parse_iinf(p: &[u8]) -> Option<Vec<(u32, [u8; 4])>> {
    let mut r = Rd::new(p);
    let (v, _) = r.full()?;
    let _n = if v == 0 { r.u16()? as u32 } else { r.u32()? };
    let mut out = Vec::new();
    for (t, b) in boxes(&p[r.p..]) {
        if &t != b"infe" {
            continue;
        }
        let mut r = Rd::new(b);
        let (iv, _) = r.full()?;
        if iv < 2 {
            continue;
        }
        let id = if iv == 2 { r.u16()? as u32 } else { r.u32()? };
        let _prot = r.u16()?;
        let ty: [u8; 4] = r.bytes(4)?.try_into().ok()?;
        out.push((id, ty));
    }
    Some(out)
}

/// ipma → item_id → 1-based property 索引（依序）
fn parse_ipma(p: &[u8]) -> Option<Vec<(u32, Vec<u16>)>> {
    let mut r = Rd::new(p);
    let (v, flags) = r.full()?;
    let n = r.u32()?;
    let mut out = Vec::new();
    for _ in 0..n {
        let id = if v < 1 { r.u16()? as u32 } else { r.u32()? };
        let c = r.u8()?;
        let mut props = Vec::new();
        for _ in 0..c {
            let idx = if flags & 1 != 0 {
                r.u16()? & 0x7FFF
            } else {
                (r.u8()? & 0x7F) as u16
            };
            props.push(idx);
        }
        out.push((id, props));
    }
    Some(out)
}

/// iref → (type, from, to[])
fn parse_iref(p: &[u8]) -> Option<Vec<([u8; 4], u32, Vec<u32>)>> {
    let mut r = Rd::new(p);
    let (v, _) = r.full()?;
    let mut out = Vec::new();
    for (t, b) in boxes(&p[r.p..]) {
        let mut r = Rd::new(b);
        let from = if v == 0 { r.u16()? as u32 } else { r.u32()? };
        let n = r.u16()?;
        let mut to = Vec::new();
        for _ in 0..n {
            to.push(if v == 0 { r.u16()? as u32 } else { r.u32()? });
        }
        out.push((t, from, to));
    }
    Some(out)
}

fn item_data(file: &[u8], idat: Option<&[u8]>, loc: &Loc) -> Option<Vec<u8>> {
    let src = match loc.method {
        0 => file,
        1 => idat?,
        _ => return None,
    };
    let mut v = Vec::new();
    for e in &loc.extents {
        let start = (loc.base + e.offset) as usize;
        let end = if e.length == 0 {
            src.len()
        } else {
            start.checked_add(e.length as usize)?
        };
        v.extend_from_slice(src.get(start..end)?);
    }
    Some(v)
}

/// 解析容器資訊（不解碼像素）。
pub fn parse(data: &[u8]) -> Result<Info> {
    parse_inner(data).ok_or_else(|| derr("HEIF 容器格式錯誤"))
}

fn parse_inner(data: &[u8]) -> Option<Info> {
    let top = boxes(data);
    let meta = find(&top, b"meta")?;
    let meta = boxes(meta.get(4..)?);
    let mut r = Rd::new(find(&meta, b"pitm")?);
    let (pv, _) = r.full()?;
    let primary = if pv == 0 { r.u16()? as u32 } else { r.u32()? };

    let items = find(&meta, b"iinf").and_then(parse_iinf).unwrap_or_default();
    let locs = find(&meta, b"iloc").and_then(parse_iloc).unwrap_or_default();
    let refs = find(&meta, b"iref").and_then(parse_iref).unwrap_or_default();
    let idat = find(&meta, b"idat");
    let iprp = boxes(find(&meta, b"iprp")?);
    let ipco = boxes(find(&iprp, b"ipco")?);
    let ipma: Vec<(u32, Vec<u16>)> = iprp
        .iter()
        .filter(|(t, _)| t == b"ipma")
        .filter_map(|(_, p)| parse_ipma(p))
        .flatten()
        .collect();

    let props_of = |id: u32| -> Vec<([u8; 4], &[u8])> {
        ipma.iter()
            .filter(|(i, _)| *i == id)
            .flat_map(|(_, v)| v.iter())
            .filter(|&&i| i > 0)
            .filter_map(|&i| ipco.get(i as usize - 1).copied())
            .collect()
    };

    let mut info = Info::default();
    for (t, p) in props_of(primary) {
        let mut r = Rd::new(p);
        match &t {
            b"ispe" => {
                r.full()?;
                info.width = r.u32()?;
                info.height = r.u32()?;
            }
            b"irot" => info.transforms.push(Transform::Rotate(r.u8()? & 3)),
            b"imir" => info.transforms.push(Transform::Mirror(r.u8()? & 1 == 1)),
            b"clap" => {
                let mut v = [0i64; 8];
                for (i, x) in v.iter_mut().enumerate() {
                    let u = r.u32()?;
                    // 寬高為無號，偏移為有號
                    *x = if i < 4 { u as i64 } else { u as i32 as i64 };
                }
                // (wN, wD, hN, hD, hoN, hoD, voN, voD)
                if v[1] == 0 || v[3] == 0 || v[5] == 0 || v[7] == 0 {
                    continue;
                }
                // 目前尺寸（clap 前若已有旋轉則交換）
                let (iw, ih) = {
                    let tmp = Info {
                        width: info.width,
                        height: info.height,
                        transforms: info.transforms.clone(),
                        ..Default::default()
                    };
                    tmp.display_size()
                };
                let cw = v[0] as f64 / v[1] as f64;
                let ch = v[2] as f64 / v[3] as f64;
                let left = (iw as f64 - 1.0) / 2.0 + v[4] as f64 / v[5] as f64 - (cw - 1.0) / 2.0;
                let top = (ih as f64 - 1.0) / 2.0 + v[6] as f64 / v[7] as f64 - (ch - 1.0) / 2.0;
                let l = (left.round().max(0.0) as u32).min(iw.saturating_sub(1));
                let t = (top.round().max(0.0) as u32).min(ih.saturating_sub(1));
                let w = (cw.round() as u32).clamp(1, iw - l);
                let h = (ch.round() as u32).clamp(1, ih - t);
                if (l, t, w, h) != (0, 0, iw, ih) {
                    info.transforms.push(Transform::Crop(l, t, w, h));
                }
            }
            b"colr" => {
                let ct = r.bytes(4)?;
                if (ct == b"prof" || ct == b"rICC") && info.icc.is_none() {
                    info.icc = Some(p[4..].to_vec());
                }
            }
            _ => {}
        }
    }
    if info.width == 0 || info.height == 0 {
        return None;
    }

    // 輔助圖：auxl 指向 primary 且 auxC 為 alpha
    for (t, from, to) in &refs {
        if t == b"auxl" && to.contains(&primary) {
            let alpha = props_of(*from).iter().any(|(t, p)| {
                t == b"auxC"
                    && p.get(4..)
                        .map(|u| u.starts_with(b"urn:mpeg:hevc:2015:auxid:1") || u.starts_with(b"urn:mpeg:mpegB:cicp:systems:auxiliary:alpha"))
                        .unwrap_or(false)
            });
            info.has_alpha |= alpha;
        }
    }

    // EXIF：cdsc 指向 primary 的 Exif item
    let exif_id = items
        .iter()
        .filter(|(_, ty)| ty == b"Exif")
        .map(|(id, _)| *id)
        .find(|id| {
            refs.iter()
                .any(|(t, from, to)| t == b"cdsc" && from == id && to.contains(&primary))
        })
        .or_else(|| items.iter().find(|(_, ty)| ty == b"Exif").map(|(id, _)| *id));
    if let Some(id) = exif_id
        && let Some((_, loc)) = locs.iter().find(|(i, _)| *i == id)
        && let Some(d) = item_data(data, idat, loc)
        && d.len() > 4
    {
        let off = u32::from_be_bytes([d[0], d[1], d[2], d[3]]) as usize;
        if let Some(t) = d.get(4 + off..) {
            let t = t.strip_prefix(b"Exif\0\0").unwrap_or(t);
            if t.starts_with(b"II") || t.starts_with(b"MM") {
                info.exif = Some(t.to_vec());
            }
        }
    }
    Some(info)
}

/// 依序套用 HEIF 幾何轉換。
pub fn apply_transforms(mut img: DynamicImage, ts: &[Transform]) -> DynamicImage {
    for t in ts {
        img = match *t {
            // 逆時針 90° = 順時針 270°
            Transform::Rotate(1) => img.rotate270(),
            Transform::Rotate(2) => img.rotate180(),
            Transform::Rotate(3) => img.rotate90(),
            Transform::Rotate(_) => img,
            Transform::Mirror(false) => img.flipv(),
            Transform::Mirror(true) => img.fliph(),
            Transform::Crop(x, y, w, h) => img.crop_imm(x, y, w, h),
        };
    }
    img
}

// ---------- 解碼 ----------

/// 系統解碼器已套用哪些 HEIF 轉換。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[allow(dead_code)]
pub(crate) enum Applied {
    /// clap / irot / imir 都已套用（libheif、Windows WIC，實測）
    All,
    /// 只套用 clap 與 irot，未套用 imir（Android，實測）
    CropRotate,
    /// 都未套用
    None,
}

/// 系統解碼器的輸出。
pub(crate) struct Raw {
    pub rgba: RgbaImage,
    pub applied: Applied,
    /// 像素已轉成 sRGB（不需再套 ICC）
    pub srgb: bool,
}

pub struct Decoded {
    /// 已轉正
    pub img: DynamicImage,
    /// 像素所在的色彩空間（None = sRGB）
    pub icc: Option<Vec<u8>>,
    pub exif: Option<Vec<u8>>,
}

/// 此平台是否能解 HEIF（Linux 依是否裝有 libheif 而定）。
pub fn supported() -> bool {
    sys::supported()
}

pub fn decode(data: &[u8]) -> Result<Decoded> {
    let info = parse(data)?;
    let raw = sys::decode(data)?;
    Ok(finish(&info, raw))
}

/// 補上解碼器沒套用的轉換。
fn finish(info: &Info, raw: Raw) -> Decoded {
    let (w, h) = (raw.rgba.width(), raw.rgba.height());
    let disp = info.display_size();
    // 尺寸還是編碼尺寸、但應該要變 → 解碼器什麼都沒套用
    let applied = if (w, h) == (info.width, info.height) && disp != (w, h) {
        Applied::None
    } else {
        raw.applied
    };
    let mut img = DynamicImage::ImageRgba8(raw.rgba);
    match applied {
        Applied::All => {}
        Applied::None => img = apply_transforms(img, &info.transforms),
        Applied::CropRotate => {
            let mirrors: Vec<Transform> = info
                .transforms
                .iter()
                .copied()
                .filter(|t| matches!(t, Transform::Mirror(_)))
                .collect();
            img = apply_transforms(img, &mirrors);
        }
    }
    let img = if info.has_alpha {
        img
    } else {
        DynamicImage::ImageRgb8(img.to_rgb8())
    };
    Decoded {
        img,
        icc: if raw.srgb { None } else { info.icc.clone() },
        exif: info.exif.clone(),
    }
}

/// 內建測試圖（64×48，左上角紅色方塊；檔名數字為產生時的 EXIF 方向：
/// 2 = 左右翻轉、3 = 180°、6 = 順時針 90°、7 = 轉置（反對角線）
const FX_PLAIN: &[u8] = include_bytes!("../tests/fixtures/plain.heic");
const FX_ORIENT6: &[u8] = include_bytes!("../tests/fixtures/orient6.heic");
const FX_ORIENT2: &[u8] = include_bytes!("../tests/fixtures/orient2.heic");
const FX_ORIENT3: &[u8] = include_bytes!("../tests/fixtures/orient3.heic");
const FX_ORIENT7: &[u8] = include_bytes!("../tests/fixtures/orient7.heic");
const FX_ALPHA: &[u8] = include_bytes!("../tests/fixtures/alpha.heic");

/// 用內建測試圖確認系統解碼器可用（結果快取）。
#[allow(dead_code)]
fn self_check() -> bool {
    static OK: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *OK.get_or_init(|| sys::decode(FX_PLAIN).is_ok())
}

/// 自我測試：(項目, 結果)。給 CLI / 診斷用。
pub fn self_test() -> Vec<(&'static str, std::result::Result<String, String>)> {
    let red = |im: &image::RgbImage, x: u32, y: u32| {
        let p = im.get_pixel(x, y).0;
        p[0] > 200 && p[1] < 60 && p[2] < 60
    };
    let run = |data: &[u8], want: (u32, u32), marker: (u32, u32)| -> std::result::Result<String, String> {
        let raw = sys::decode(data).map_err(|e| e.to_string())?;
        let raw_dims = raw.rgba.dimensions();
        let d = decode(data).map_err(|e| e.to_string())?;
        let im = d.img.to_rgb8();
        let msg = format!("raw {}×{} → {}×{}", raw_dims.0, raw_dims.1, im.width(), im.height());
        if im.dimensions() != want {
            return Err(format!("{msg}（應為 {}×{}）", want.0, want.1));
        }
        if !red(&im, marker.0, marker.1) {
            return Err(format!("{msg}，方向錯誤"));
        }
        Ok(msg)
    };
    vec![
        ("plain", run(FX_PLAIN, (64, 48), (2, 2))),
        ("rotate90", run(FX_ORIENT6, (48, 64), (45, 2))),
        ("mirror", run(FX_ORIENT2, (64, 48), (61, 2))),
        ("rotate180", run(FX_ORIENT3, (64, 48), (61, 45))),
        ("transverse", run(FX_ORIENT7, (48, 64), (45, 61))),
        ("alpha", (|| {
            let d = decode(FX_ALPHA).map_err(|e| e.to_string())?;
            let a = d.img.to_rgba8();
            if a.get_pixel(30, 5).0[3] < 10 && a.get_pixel(30, 40).0[3] > 245 {
                Ok("ok".to_string())
            } else {
                // WIC 與 Android 的解碼器都不支援 HEIC 透明度；照片不受影響
                Ok("系統解碼器不支援透明度（透明處顯示原色）".to_string())
            }
        })()),
    ]
}

fn unsupported() -> Error {
    Error::Unsupported("HEIC".into())
}

#[cfg(target_os = "linux")]
#[path = "heif/linux.rs"]
mod sys;

#[cfg(windows)]
#[path = "heif/windows.rs"]
mod sys;

#[cfg(target_os = "android")]
#[path = "heif/android.rs"]
mod sys;

#[cfg(not(any(target_os = "linux", windows, target_os = "android")))]
mod sys {
    use super::*;
    pub fn supported() -> bool {
        false
    }
    pub fn decode(_: &[u8]) -> Result<Raw> {
        Err(unsupported())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn brand_detection() {
        let mut d = vec![0, 0, 0, 24];
        d.extend(b"ftypmif1\0\0\0\0mif1heic");
        assert!(is_heif(&d));
        let mut d = vec![0, 0, 0, 20];
        d.extend(b"ftypavif\0\0\0\0avif");
        assert!(!is_heif(&d));
        assert!(!is_heif(b"\xFF\xD8\xFF\xE0garbage-garbage"));
    }

    #[test]
    fn transforms_order() {
        let mut im = RgbaImage::new(3, 2);
        im.put_pixel(0, 0, image::Rgba([255, 0, 0, 255]));
        let img = DynamicImage::ImageRgba8(im);
        // 逆時針 90°：左上角的點移到左下角
        let r = apply_transforms(img.clone(), &[Transform::Rotate(1)]).to_rgba8();
        assert_eq!(r.dimensions(), (2, 3));
        assert_eq!(r.get_pixel(0, 2).0[0], 255);
        // 左右鏡像：左上 → 右上
        let m = apply_transforms(img, &[Transform::Mirror(true)]).to_rgba8();
        assert_eq!(m.get_pixel(2, 0).0[0], 255);
    }

    fn fixture(name: &str) -> Vec<u8> {
        let p = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name);
        std::fs::read(p).unwrap()
    }

    #[test]
    fn parse_fixtures() {
        let i = parse(&fixture("plain.heic")).unwrap();
        assert_eq!(i.display_size(), (64, 48));
        assert!(!i.has_alpha);
        let i = parse(&fixture("orient6.heic")).unwrap();
        assert_eq!(i.display_size(), (48, 64));
        assert!(i.transforms.contains(&Transform::Rotate(3)));
        assert!(i.exif.as_deref().unwrap().starts_with(b"II") || i.exif.as_deref().unwrap().starts_with(b"MM"));
        let i = parse(&fixture("orient2.heic")).unwrap();
        assert!(i.transforms.contains(&Transform::Mirror(true)));
        assert!(parse(&fixture("alpha.heic")).unwrap().has_alpha);
        assert!(is_heif(&fixture("plain.heic")));
    }

    /// 需要系統解碼器（Linux：libheif1 + libheif-plugin-libde265）
    #[test]
    fn decode_fixtures() {
        if !supported() {
            eprintln!("skip: no HEIF decoder");
            return;
        }
        let red = |im: &image::RgbImage, x: u32, y: u32| {
            let p = im.get_pixel(x, y).0;
            p[0] > 200 && p[1] < 60 && p[2] < 60
        };
        let im = decode(&fixture("plain.heic")).unwrap().img.to_rgb8();
        assert_eq!(im.dimensions(), (64, 48));
        assert!(red(&im, 2, 2));
        // EXIF 6 = 順時針轉 90°：紅色標記到右上
        let im = decode(&fixture("orient6.heic")).unwrap().img.to_rgb8();
        assert_eq!(im.dimensions(), (48, 64));
        assert!(red(&im, 45, 2), "{:?}", im.get_pixel(45, 2));
        // EXIF 2 = 左右翻轉：紅色標記到右上
        let im = decode(&fixture("orient2.heic")).unwrap().img.to_rgb8();
        assert!(red(&im, 61, 2));
        let d = decode(&fixture("alpha.heic")).unwrap();
        let a = d.img.to_rgba8();
        assert!(a.get_pixel(30, 5).0[3] < 10 && a.get_pixel(30, 40).0[3] > 245);
    }

    /// 模擬只套用 clap / irot 的解碼器（WIC、Android），確認補上 imir 後方向正確
    #[test]
    fn crop_rotate_decoder() {
        if !supported() {
            return;
        }
        let raw_plain = sys::decode(&fixture("plain.heic")).unwrap().rgba;
        for (name, want, marker) in [
            ("orient2.heic", (64, 48), (61, 2)),
            ("orient7.heic", (48, 64), (45, 61)),
            ("orient6.heic", (48, 64), (45, 2)),
        ] {
            let info = parse(&fixture(name)).unwrap();
            let rot: Vec<Transform> = info
                .transforms
                .iter()
                .copied()
                .filter(|t| matches!(t, Transform::Rotate(_)))
                .collect();
            let emulated = apply_transforms(DynamicImage::ImageRgba8(raw_plain.clone()), &rot).to_rgba8();
            let d = finish(&info, Raw { rgba: emulated, applied: Applied::CropRotate, srgb: false });
            let im = d.img.to_rgb8();
            assert_eq!(im.dimensions(), want, "{name}");
            let p = im.get_pixel(marker.0, marker.1).0;
            assert!(p[0] > 200 && p[1] < 60 && p[2] < 60, "{name}: {p:?}");
        }
    }
}
