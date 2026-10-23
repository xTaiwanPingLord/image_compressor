//! 讀檔：套用 EXIF 方向、ICC 轉 sRGB、透明合成白底，輸出 8-bit RGB。

use crate::{Error, Result, heif};
use image::{
    DynamicImage, ImageDecoder, ImageFormat, ImageReader, RgbImage, metadata::Orientation,
};
use std::io::Cursor;
use std::path::Path;

pub const IMAGE_EXTS: &[&str] = &[
    "jpg", "jpeg", "png", "webp", "bmp", "tif", "tiff", "gif", "heic", "heif", "hif",
];

pub fn is_image_path(p: &Path) -> bool {
    p.extension()
        .and_then(|e| e.to_str())
        .map(|e| IMAGE_EXTS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

fn derr(path: &Path, e: impl ToString) -> Error {
    Error::Decode {
        path: path.display().to_string(),
        msg: e.to_string(),
    }
}

fn with_path(path: &Path, e: Error) -> Error {
    match e {
        Error::Decode { msg, .. } => derr(path, msg),
        e => e,
    }
}

/// 已轉正的解碼結果。
pub struct Decoded {
    pub img: DynamicImage,
    /// 像素的色彩空間（None 或 sRGB 皆可視為 sRGB）
    pub icc: Option<Vec<u8>>,
    /// EXIF（TIFF 資料，可能帶 "Exif\0\0" 前綴）
    pub exif: Option<Vec<u8>>,
    /// image crate 認得的格式；HEIF 為 None
    pub format: Option<ImageFormat>,
    pub heif: bool,
}

/// 從記憶體解碼任何支援的格式（含 HEIF），並套用方向。
pub fn decode_bytes(data: &[u8]) -> Result<Decoded> {
    if heif::is_heif(data) {
        let d = heif::decode(data)?;
        return Ok(Decoded {
            img: d.img,
            icc: d.icc,
            exif: d.exif,
            format: None,
            heif: true,
        });
    }
    let err = |e: image::ImageError| Error::Decode {
        path: String::new(),
        msg: e.to_string(),
    };
    let reader = ImageReader::new(Cursor::new(data)).with_guessed_format()?;
    let format = reader.format();
    let mut dec = reader.into_decoder().map_err(err)?;
    let icc = dec.icc_profile().ok().flatten();
    let exif = dec.exif_metadata().ok().flatten();
    let orient = dec.orientation().unwrap_or(Orientation::NoTransforms);
    let mut img = DynamicImage::from_decoder(dec).map_err(err)?;
    img.apply_orientation(orient);
    Ok(Decoded {
        img,
        icc,
        exif,
        format,
        heif: false,
    })
}

/// 只讀尺寸（已考慮 EXIF / HEIF 旋轉）。
pub fn dimensions(path: &Path) -> Result<(u32, u32)> {
    let reader = ImageReader::open(path)?.with_guessed_format()?;
    if reader.format().is_none() {
        let data = std::fs::read(path)?;
        if heif::is_heif(&data) {
            return heif::parse(&data)
                .map(|i| i.display_size())
                .map_err(|e| with_path(path, e));
        }
    }
    let mut dec = reader.into_decoder().map_err(|e| derr(path, e))?;
    let (w, h) = dec.dimensions();
    let o = dec.orientation().unwrap_or(Orientation::NoTransforms);
    Ok(match o {
        Orientation::Rotate90
        | Orientation::Rotate270
        | Orientation::Rotate90FlipH
        | Orientation::Rotate270FlipH => (h, w),
        _ => (w, h),
    })
}

pub fn load_rgb(path: &Path) -> Result<RgbImage> {
    let data = std::fs::read(path)?;
    let d = decode_bytes(&data).map_err(|e| with_path(path, e))?;
    Ok(to_srgb_on_white(d.img, d.icc.as_deref()))
}

/// 轉 sRGB 並把透明處合成白底。
pub fn to_srgb_on_white(img: DynamicImage, icc: Option<&[u8]>) -> RgbImage {
    let (w, h) = (img.width(), img.height());
    let has_alpha = img.color().has_alpha();
    let is_rgb = matches!(
        img.color(),
        image::ColorType::Rgb8
            | image::ColorType::Rgba8
            | image::ColorType::Rgb16
            | image::ColorType::Rgba16
            | image::ColorType::Rgb32F
            | image::ColorType::Rgba32F
    );
    let mut rgba = img.into_rgba8().into_raw();

    if let (Some(icc), true) = (icc, is_rgb)
        && let Some(src) = qcms::Profile::new_from_slice(icc, false)
        && !src.is_sRGB()
    {
        let mut dst = qcms::Profile::new_sRGB();
        dst.precache_output_transform();
        if let Some(t) =
            qcms::Transform::new(&src, &dst, qcms::DataType::RGBA8, qcms::Intent::Perceptual)
        {
            t.apply(&mut rgba);
        }
    }

    let mut out = Vec::with_capacity((w * h * 3) as usize);
    for px in rgba.chunks_exact(4) {
        if has_alpha && px[3] != 255 {
            let a = px[3] as u32;
            for &c in &px[..3] {
                out.push(((c as u32 * a + 255 * (255 - a) + 127) / 255) as u8);
            }
        } else {
            out.extend_from_slice(&px[..3]);
        }
    }
    RgbImage::from_raw(w, h, out).expect("buffer size")
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{Rgba, RgbaImage};

    #[test]
    fn transparent_becomes_white() {
        let mut im = RgbaImage::new(2, 1);
        im.put_pixel(0, 0, Rgba([0, 0, 0, 0]));
        im.put_pixel(1, 0, Rgba([0, 0, 0, 128]));
        let out = to_srgb_on_white(DynamicImage::ImageRgba8(im), None);
        assert_eq!(out.get_pixel(0, 0).0, [255, 255, 255]);
        let v = out.get_pixel(1, 0).0[0];
        assert!((126..=128).contains(&v), "{v}");
    }
}
