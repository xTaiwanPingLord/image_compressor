//! 幾何處理：補白 / 置中裁切到指定比例、Lanczos3 縮放、垂直接合、切段。

use fast_image_resize as fr;
use image::{Rgb, RgbImage, imageops};
use serde::{Deserialize, Serialize};

pub const WHITE: Rgb<u8> = Rgb([255, 255, 255]);

/// 比例不符時的處理方式。
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Fit {
    /// 補白邊（不損失內容）
    #[default]
    Pad,
    /// 置中裁切
    Crop,
}

fn gcd(a: u32, b: u32) -> u32 {
    if b == 0 { a } else { gcd(b, a % b) }
}

/// 寬高是否符合 rw:rh（允許 1px 誤差）。
pub fn matches_ratio(w: u32, h: u32, rw: u32, rh: u32) -> bool {
    let target_w = h as f64 * rw as f64 / rh as f64;
    (w as f64 - target_w).abs() <= 1.0
}

/// 補白或裁切成剛好 rw:rh。
pub fn fit_ratio(img: &RgbImage, rw: u32, rh: u32, fit: Fit) -> RgbImage {
    let (w, h) = img.dimensions();
    let g = gcd(rw, rh);
    let (rw, rh) = (rw / g, rh / g);
    if w as u64 * rh as u64 == h as u64 * rw as u64 {
        return img.clone();
    }
    match fit {
        Fit::Pad => {
            let k = w.div_ceil(rw).max(h.div_ceil(rh));
            let (cw, ch) = (rw * k, rh * k);
            let mut canvas = RgbImage::from_pixel(cw, ch, WHITE);
            imageops::replace(
                &mut canvas,
                img,
                ((cw - w) / 2) as i64,
                ((ch - h) / 2) as i64,
            );
            canvas
        }
        Fit::Crop => {
            let k = (w / rw).min(h / rh).max(1);
            let (cw, ch) = ((rw * k).min(w), (rh * k).min(h));
            imageops::crop_imm(img, (w - cw) / 2, (h - ch) / 2, cw, ch).to_image()
        }
    }
}

/// Lanczos3 縮放到指定尺寸。
pub fn resize(img: &RgbImage, w: u32, h: u32) -> RgbImage {
    let (w, h) = (w.max(1), h.max(1));
    if img.dimensions() == (w, h) {
        return img.clone();
    }
    let src = fr::images::Image::from_vec_u8(
        img.width(),
        img.height(),
        img.as_raw().clone(),
        fr::PixelType::U8x3,
    )
    .expect("src image");
    let mut dst = fr::images::Image::new(w, h, fr::PixelType::U8x3);
    let opts =
        fr::ResizeOptions::new().resize_alg(fr::ResizeAlg::Convolution(fr::FilterType::Lanczos3));
    fr::Resizer::new()
        .resize(&src, &mut dst, &opts)
        .expect("resize");
    RgbImage::from_raw(w, h, dst.into_vec()).expect("dst buffer")
}

/// 等比縮放到指定寬度（可放大）。
pub fn resize_to_width(img: &RgbImage, w: u32) -> RgbImage {
    let h = ((img.height() as f64 * w as f64 / img.width() as f64).round() as u32).max(1);
    resize(img, w, h)
}

/// 等比縮放比例 s。
pub fn scale(img: &RgbImage, s: f64) -> RgbImage {
    let w = ((img.width() as f64 * s).round() as u32).max(1);
    let h = ((img.height() as f64 * s).round() as u32).max(1);
    resize(img, w, h)
}

/// 垂直接合（寬度須一致；不一致者以白底靠左）。
pub fn concat_vertical(imgs: &[RgbImage]) -> RgbImage {
    let w = imgs.iter().map(|i| i.width()).max().unwrap_or(1);
    let h: u32 = imgs.iter().map(|i| i.height()).sum();
    let mut out = RgbImage::from_pixel(w, h.max(1), WHITE);
    let mut y = 0i64;
    for i in imgs {
        imageops::replace(&mut out, i, 0, y);
        y += i.height() as i64;
    }
    out
}

/// 依邊界 [0, c1, …, H] 切成多段。
pub fn split_at(img: &RgbImage, bounds: &[u32]) -> Vec<RgbImage> {
    bounds
        .windows(2)
        .map(|b| imageops::crop_imm(img, 0, b[0], img.width(), b[1] - b[0]).to_image())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn solid(w: u32, h: u32) -> RgbImage {
        RgbImage::from_pixel(w, h, Rgb([10, 20, 30]))
    }

    #[test]
    fn pad_to_square() {
        let o = fit_ratio(&solid(800, 600), 1, 1, Fit::Pad);
        assert_eq!(o.dimensions(), (800, 800));
        assert_eq!(o.get_pixel(400, 0).0, [255, 255, 255]);
        assert_eq!(o.get_pixel(400, 400).0, [10, 20, 30]);
    }

    #[test]
    fn crop_to_square() {
        assert_eq!(
            fit_ratio(&solid(800, 600), 1, 1, Fit::Crop).dimensions(),
            (600, 600)
        );
    }

    #[test]
    fn exact_3_4() {
        let p = fit_ratio(&solid(301, 400), 3, 4, Fit::Pad);
        assert_eq!(p.width() * 4, p.height() * 3);
        assert!(p.width() >= 301 && p.height() >= 400);
        let c = fit_ratio(&solid(301, 400), 3, 4, Fit::Crop);
        assert_eq!(c.width() * 4, c.height() * 3);
        assert!(c.width() <= 301 && c.height() <= 400);
    }

    #[test]
    fn ratio_tolerance() {
        assert!(matches_ratio(1000, 1000, 1, 1));
        assert!(matches_ratio(1001, 1000, 1, 1));
        assert!(!matches_ratio(1003, 1000, 1, 1));
        assert!(matches_ratio(750, 1000, 3, 4));
    }

    #[test]
    fn concat_and_split() {
        let c = concat_vertical(&[solid(100, 30), solid(100, 50)]);
        assert_eq!(c.dimensions(), (100, 80));
        let parts = split_at(&c, &[0, 40, 80]);
        assert_eq!(parts.len(), 2);
        assert_eq!(parts[1].height(), 40);
    }

    #[test]
    fn upscale_width() {
        assert_eq!(
            resize_to_width(&solid(500, 333), 1000).dimensions(),
            (1000, 666)
        );
    }
}
