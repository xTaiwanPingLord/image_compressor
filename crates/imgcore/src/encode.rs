//! mozjpeg 編碼與檔案大小目標搜尋。

use crate::{Error, Result, geom};
use image::RgbImage;
use serde::Serialize;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub enum Mode {
    /// 4:2:0 + mozjpeg 最佳化（最小檔）
    Normal,
    /// 4:4:4 + mozjpeg 最佳化
    Chroma444,
    /// 4:4:4 + libjpeg 預設（關閉最佳化，檔案較大）
    Chroma444Plain,
}

/// 編碼成 baseline/progressive JPEG，不含 metadata（EXIF / ICC），色彩為 sRGB。
pub fn encode_jpeg(img: &RgbImage, quality: u8, mode: Mode) -> Result<Vec<u8>> {
    let (w, h) = img.dimensions();
    let data = img.as_raw();
    std::panic::catch_unwind(|| -> std::io::Result<Vec<u8>> {
        let mut c = mozjpeg::Compress::new(mozjpeg::ColorSpace::JCS_RGB);
        if mode == Mode::Chroma444Plain {
            c.set_fastest_defaults();
        }
        c.set_size(w as usize, h as usize);
        c.set_quality(quality as f32);
        if mode != Mode::Normal {
            c.set_chroma_sampling_pixel_sizes((1, 1), (1, 1));
        }
        let mut s = c.start_compress(Vec::new())?;
        s.write_scanlines(data)?;
        s.finish()
    })
    .map_err(|_| Error::Encode("mozjpeg panic".into()))?
    .map_err(|e| Error::Encode(e.to_string()))
}

#[derive(Clone, Debug)]
pub struct Target {
    pub max_bytes: u64,
    pub min_bytes: Option<u64>,
    pub min_quality: u8,
    pub max_quality: u8,
    /// 品質到下限仍超標時，每次縮小 10% 解析度
    pub allow_downscale: bool,
    /// 色度 4:4:4（文字 / 細線邊緣較清晰，檔案較大）
    pub chroma444: bool,
}

#[derive(Clone, Debug)]
pub struct Encoded {
    pub data: Vec<u8>,
    pub quality: u8,
    pub mode: Mode,
    pub width: u32,
    pub height: u32,
    pub warnings: Vec<String>,
}

/// 在 [lo, hi] 中找出大小 ≤ max 的最高品質；回傳 (品質, 資料)。lo 也超標則 None。
fn search(
    img: &RgbImage,
    lo: u8,
    hi: u8,
    max: u64,
    mode: Mode,
) -> Result<(Option<(u8, Vec<u8>)>, Vec<u8>)> {
    let top = encode_jpeg(img, hi, mode)?;
    if top.len() as u64 <= max {
        return Ok((Some((hi, top)), vec![]));
    }
    let bottom = encode_jpeg(img, lo, mode)?;
    if bottom.len() as u64 > max {
        return Ok((None, bottom));
    }
    let (mut ok_q, mut ok) = (lo, bottom);
    let (mut l, mut h) = (lo, hi); // l 通過、h 不通過
    while h - l > 1 {
        let m = l + (h - l) / 2;
        let d = encode_jpeg(img, m, mode)?;
        if d.len() as u64 <= max {
            l = m;
            ok_q = m;
            ok = d;
        } else {
            h = m;
        }
    }
    Ok((Some((ok_q, ok)), vec![]))
}

pub fn compress_to_target(img: &RgbImage, t: &Target) -> Result<Encoded> {
    let mut cur = img.clone();
    let mut warnings = Vec::new();
    let mut downscaled = 0;
    let base_mode = if t.chroma444 {
        Mode::Chroma444
    } else {
        Mode::Normal
    };
    let (q, data) = loop {
        let (found, smallest) = search(&cur, t.min_quality, t.max_quality, t.max_bytes, base_mode)?;
        match found {
            Some(r) => break r,
            None if t.allow_downscale && cur.width() > 16 && cur.height() > 16 => {
                cur = geom::scale(&cur, 0.9);
                downscaled += 1;
            }
            None => {
                warnings.push(format!(
                    "品質 {} 仍有 {} bytes，超過上限 {}",
                    t.min_quality,
                    smallest.len(),
                    t.max_bytes
                ));
                break (t.min_quality, smallest);
            }
        }
    };
    if downscaled > 0 {
        warnings.push(format!(
            "品質降到 {} 仍超標，解析度縮小 {} 次至 {}×{}",
            t.min_quality,
            downscaled,
            cur.width(),
            cur.height()
        ));
    }
    let mut out = Encoded {
        data,
        quality: q,
        mode: base_mode,
        width: cur.width(),
        height: cur.height(),
        warnings,
    };

    if let Some(min) = t.min_bytes
        && (out.data.len() as u64) < min
    {
        // 改 4:4:4、再關閉最佳化，品質往上找（仍需 ≤ 上限）
        let modes: &[Mode] = if t.chroma444 {
            &[Mode::Chroma444, Mode::Chroma444Plain]
        } else {
            &[Mode::Normal, Mode::Chroma444, Mode::Chroma444Plain]
        };
        for &mode in modes {
            let (found, _) = search(&cur, out.quality.max(t.max_quality), 100, t.max_bytes, mode)?;
            if let Some((q, d)) = found {
                if d.len() > out.data.len() {
                    out.data = d;
                    out.quality = q;
                    out.mode = mode;
                }
                if out.data.len() as u64 >= min {
                    break;
                }
            }
        }
        if (out.data.len() as u64) < min {
            out.warnings.push(format!(
                "檔案 {} bytes 低於下限 {}（已用品質 100、4:4:4 並關閉最佳化）",
                out.data.len(),
                min
            ));
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgb;

    pub(crate) fn noise(w: u32, h: u32, seed: u32) -> RgbImage {
        let mut s = seed.wrapping_mul(2654435761).max(1);
        RgbImage::from_fn(w, h, |_, _| {
            s ^= s << 13;
            s ^= s >> 17;
            s ^= s << 5;
            Rgb([s as u8, (s >> 8) as u8, (s >> 16) as u8])
        })
    }

    #[test]
    fn output_is_jpeg_without_exif() {
        let d = encode_jpeg(&noise(64, 64, 1), 80, Mode::Normal).unwrap();
        assert_eq!(&d[..2], &[0xFF, 0xD8]);
        assert!(!d.windows(4).any(|w| w == b"Exif"));
        assert!(!d.windows(11).any(|w| w == b"ICC_PROFILE"));
        let back = image::load_from_memory(&d).unwrap();
        assert_eq!((back.width(), back.height()), (64, 64));
    }

    #[test]
    fn respects_max_bytes() {
        let img = noise(800, 800, 2);
        let t = Target {
            max_bytes: 150_000,
            min_bytes: None,
            min_quality: 10,
            max_quality: 92,
            allow_downscale: false,
            chroma444: false,
        };
        let e = compress_to_target(&img, &t).unwrap();
        assert!(e.data.len() <= 150_000);
        assert!(e.quality < 92 && e.quality >= 10);
        // 再高一級品質就會超標（確認為最高可行品質）
        let next = encode_jpeg(&img, e.quality + 1, Mode::Normal).unwrap();
        assert!(next.len() > 150_000);
    }

    #[test]
    fn downscale_when_quality_floor_fails() {
        let img = noise(1000, 1000, 3);
        let t = Target {
            max_bytes: 100_000,
            min_bytes: None,
            min_quality: 60,
            max_quality: 92,
            allow_downscale: true,
            chroma444: false,
        };
        let e = compress_to_target(&img, &t).unwrap();
        assert!(e.data.len() <= 100_000);
        assert!(e.width < 1000);
        assert_eq!(e.width, e.height);
    }

    #[test]
    fn min_bytes_boost() {
        // 純色 1000x1000 通常遠小於 50KB → 會嘗試加大並警告
        let img = RgbImage::from_pixel(1000, 1000, Rgb([240, 240, 240]));
        let t = Target {
            max_bytes: 1_000_000,
            min_bytes: Some(51_200),
            min_quality: 10,
            max_quality: 92,
            allow_downscale: false,
            chroma444: false,
        };
        let e = compress_to_target(&img, &t).unwrap();
        assert!(e.data.len() <= 1_000_000);
        assert!(!e.warnings.is_empty());
        assert_eq!(e.quality, 100);
    }

    #[test]
    fn min_bytes_reached_by_444() {
        // 找一張 4:2:0 q92 略低於下限、但 4:4:4 可達標的圖
        let img = noise(260, 260, 4);
        let base = encode_jpeg(&img, 92, Mode::Normal).unwrap().len() as u64;
        let t = Target {
            max_bytes: 1_000_000,
            min_bytes: Some(base + 1),
            min_quality: 10,
            max_quality: 92,
            allow_downscale: false,
            chroma444: false,
        };
        let e = compress_to_target(&img, &t).unwrap();
        assert!(e.data.len() as u64 > base);
        assert!(e.warnings.is_empty());
    }

    /// 讀出 SOF 中第一個色度元件的取樣係數（1x1 = 4:4:4）。
    fn chroma_sampling(jpeg: &[u8]) -> (u8, u8) {
        let mut i = 2;
        while i + 4 < jpeg.len() {
            let marker = jpeg[i + 1];
            let len = u16::from_be_bytes([jpeg[i + 2], jpeg[i + 3]]) as usize;
            if (0xC0..=0xC2).contains(&marker) {
                let luma = jpeg[i + 4 + 6 + 1];
                let cb = jpeg[i + 4 + 6 + 3 + 1];
                return (luma, cb);
            }
            i += 2 + len;
        }
        (0, 0)
    }

    #[test]
    fn chroma444_option() {
        let img = noise(300, 300, 7);
        let mut t = Target {
            max_bytes: 10_000_000,
            min_bytes: None,
            min_quality: 10,
            max_quality: 92,
            allow_downscale: false,
            chroma444: false,
        };
        let a = compress_to_target(&img, &t).unwrap();
        assert_eq!(chroma_sampling(&a.data), (0x22, 0x11));
        t.chroma444 = true;
        let b = compress_to_target(&img, &t).unwrap();
        assert_eq!(chroma_sampling(&b.data), (0x11, 0x11));
        assert_eq!(b.mode, Mode::Chroma444);
    }
}
