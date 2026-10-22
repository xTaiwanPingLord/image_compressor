//! 詳情圖排版：Shopee / momo 的縮放、接合、切段與智慧切點。

use crate::geom::{self, WHITE};
use image::RgbImage;

/// 智慧切點往上搜尋的範圍（px）。
pub const SMART_CUT_WINDOW: u32 = 150;

pub const SHOPEE_MIN_WIDTH: u32 = 700;
pub const SHOPEE_UPSCALE_WIDTH: u32 = 750;
pub const SHOPEE_MIN_RATIO: f64 = 0.5; // 寬/高
pub const SHOPEE_MAX_RATIO: f64 = 32.0;
pub const SHOPEE_MIN_LAST: u32 = 32;

pub const MOMO_WIDTH: u32 = 1000;
pub const MOMO_SEG_HEIGHT: u32 = 1500;
/// momo 最後一段低於此高度時從前一段挪高度
pub const MOMO_DEFAULT_MIN_LAST: u32 = 300;

/// 某橫列的亮度變異數（越低越接近純色）。
fn row_variance(img: &RgbImage, y: u32) -> f64 {
    let w = img.width() as usize;
    let row = &img.as_raw()[y as usize * w * 3..(y as usize + 1) * w * 3];
    let (mut s, mut s2) = (0f64, 0f64);
    for p in row.chunks_exact(3) {
        let l = 0.299 * p[0] as f64 + 0.587 * p[1] as f64 + 0.114 * p[2] as f64;
        s += l;
        s2 += l * l;
    }
    let n = w as f64;
    (s2 / n - (s / n).powi(2)).max(0.0)
}

/// 在 planned 上方 window 內（不低於 lo）找最平坦的切點；同分取最接近 planned。
pub fn smart_cut(img: &RgbImage, planned: u32, lo: u32, window: u32) -> u32 {
    let start = planned.saturating_sub(window).max(lo + 1).max(1);
    let mut best = planned;
    let mut best_v = f64::MAX;
    let mut y = planned;
    while y >= start {
        // 切在第 y-1 與第 y 列之間：兩列都平坦才算好
        let v = row_variance(img, y - 1)
            + if y < img.height() {
                row_variance(img, y)
            } else {
                0.0
            };
        if v < best_v - 1e-9 {
            best_v = v;
            best = y;
        }
        y -= 1;
    }
    best
}

/// 計算切段邊界 [0, c1, …, H]。
///
/// - `seg_h`：每段最大高度
/// - `min_last`：最後一段最小高度，不足時從前一段挪（0 = 不限制）
pub fn plan_cuts(img: &RgbImage, seg_h: u32, min_last: u32, smart: bool) -> Vec<u32> {
    let h = img.height();
    let mut b = vec![0u32];
    let mut y = 0u32;
    while h - y > seg_h {
        let mut c = y + seg_h;
        if smart {
            c = smart_cut(img, c, y, SMART_CUT_WINDOW.min(seg_h - 1));
        }
        b.push(c);
        y = c;
    }
    b.push(h);
    let n = b.len();
    if n >= 3 && min_last > 0 && h - b[n - 2] < min_last {
        let mut nc = h - min_last;
        if smart {
            // 往上找平坦處，仍保證最後一段 ≥ min_last
            nc = smart_cut(img, nc, b[n - 3], SMART_CUT_WINDOW.min(seg_h - 1));
        }
        if nc > b[n - 3] {
            b[n - 2] = nc;
        }
    }
    b
}

fn pad_bottom(img: RgbImage, min_h: u32) -> RgbImage {
    if img.height() >= min_h {
        return img;
    }
    let mut c = RgbImage::from_pixel(img.width(), min_h, WHITE);
    image::imageops::replace(&mut c, &img, 0, 0);
    c
}

fn ratio_ok_shopee(i: &RgbImage) -> bool {
    let r = i.width() as f64 / i.height() as f64;
    (SHOPEE_MIN_RATIO..=SHOPEE_MAX_RATIO).contains(&r)
}

/// Shopee 詳情圖排版。`max_width` > 0 時寬度超過者縮小到該寬度。
pub fn shopee_layout(imgs: &[RgbImage], smart: bool, max_width: u32) -> Vec<RgbImage> {
    if imgs.is_empty() {
        return vec![];
    }
    let up: Vec<RgbImage> = imgs
        .iter()
        .map(|i| {
            if i.width() < SHOPEE_MIN_WIDTH {
                geom::resize_to_width(i, SHOPEE_UPSCALE_WIDTH)
            } else if max_width > 0 && i.width() > max_width {
                geom::resize_to_width(i, max_width)
            } else {
                i.clone()
            }
        })
        .collect();
    if up.iter().all(ratio_ok_shopee) {
        return up;
    }
    let w = up.iter().map(|i| i.width()).max().unwrap();
    let unified: Vec<RgbImage> = up
        .iter()
        .map(|i| {
            if i.width() == w {
                i.clone()
            } else {
                geom::resize_to_width(i, w)
            }
        })
        .collect();
    let min_last = SHOPEE_MIN_LAST.max(w.div_ceil(SHOPEE_MAX_RATIO as u32));
    let tall = pad_bottom(geom::concat_vertical(&unified), min_last);
    let bounds = plan_cuts(&tall, 2 * w, min_last, smart);
    geom::split_at(&tall, &bounds)
}

/// momo 詳情圖排版。`min_last`：最後一段最小高度（0 = 保持實際高度）。
pub fn momo_layout(imgs: &[RgbImage], smart: bool, min_last: u32) -> Vec<RgbImage> {
    if imgs.is_empty() {
        return vec![];
    }
    let resized: Vec<RgbImage> = imgs
        .iter()
        .map(|i| geom::resize_to_width(i, MOMO_WIDTH))
        .collect();
    if resized.iter().all(|i| i.height() <= MOMO_SEG_HEIGHT) {
        return resized;
    }
    let tall = geom::concat_vertical(&resized);
    let bounds = plan_cuts(&tall, MOMO_SEG_HEIGHT, min_last, smart);
    geom::split_at(&tall, &bounds)
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::Rgb;

    fn img(w: u32, h: u32) -> RgbImage {
        RgbImage::from_pixel(w, h, Rgb([200, 100, 50]))
    }
    fn heights(v: &[RgbImage]) -> Vec<u32> {
        v.iter().map(|i| i.height()).collect()
    }

    // ---- momo ----
    #[test]
    fn momo_all_short_kept_separately() {
        let out = momo_layout(
            &[img(800, 1000), img(1200, 1800)],
            false,
            MOMO_DEFAULT_MIN_LAST,
        );
        // 1200x1800 → 1000x1500，全部 ≤1500 → 各自輸出
        assert_eq!(heights(&out), [1250, 1500]);
        assert!(out.iter().all(|i| i.width() == 1000));
    }

    #[test]
    fn momo_spec_example_1800_800() {
        let out = momo_layout(
            &[img(1000, 1800), img(1000, 800)],
            false,
            MOMO_DEFAULT_MIN_LAST,
        );
        assert_eq!(heights(&out), [1500, 1100]);
    }

    #[test]
    fn momo_last_keeps_actual_height_when_disabled() {
        let out = momo_layout(&[img(1000, 3005)], false, 0);
        assert_eq!(heights(&out), [1500, 1500, 5]);
    }

    #[test]
    fn momo_short_last_borrows_from_previous() {
        // 1500,1500,5 → 尾段 <300 → 1500,1205,300
        let out = momo_layout(&[img(1000, 3005)], false, MOMO_DEFAULT_MIN_LAST);
        assert_eq!(heights(&out), [1500, 1205, 300]);
        // 尾段 ≥300 不動
        let out = momo_layout(&[img(1000, 3300)], false, MOMO_DEFAULT_MIN_LAST);
        assert_eq!(heights(&out), [1500, 1500, 300]);
    }

    #[test]
    fn shopee_max_width_caps() {
        let out = shopee_layout(&[img(4000, 8000), img(4000, 5000)], false, 2000);
        assert_eq!(out[0].dimensions(), (2000, 4000));
        assert_eq!(out[1].dimensions(), (2000, 2500));
        // 0 = 不限制
        let out = shopee_layout(&[img(4000, 5000)], false, 0);
        assert_eq!(out[0].width(), 4000);
    }

    #[test]
    fn smart_cut_also_applies_to_borrowed_last() {
        // 1000 寬、總高 3100：預設 1500,1500,100 → 挪成尾段 ≥300；
        // 在 2700–2720 放白帶（2800 上方 150 內），應切在白帶且尾段 ≥300
        let mut im = RgbImage::new(1000, 3100);
        for (x, y, p) in im.enumerate_pixels_mut() {
            let v = ((x * 7 + y * 13) % 251) as u8;
            *p = Rgb([v, v.wrapping_mul(3), v.wrapping_add(90)]);
        }
        for y in 2700..2720 {
            for x in 0..1000 {
                im.put_pixel(x, y, Rgb([255, 255, 255]));
            }
        }
        let b = plan_cuts(&im, 1500, 300, true);
        assert_eq!(b.len(), 4);
        assert!((2701..=2719).contains(&b[2]), "{b:?}");
        assert!(3100 - b[2] >= 300);
    }

    // ---- Shopee ----
    #[test]
    fn shopee_upscale_narrow() {
        let out = shopee_layout(&[img(600, 900)], false, 0);
        assert_eq!(out[0].dimensions(), (750, 1125));
    }

    #[test]
    fn shopee_ratio_ok_kept() {
        let out = shopee_layout(&[img(750, 1500), img(800, 400)], false, 0);
        assert_eq!(out.len(), 2);
        assert_eq!(out[0].dimensions(), (750, 1500));
        assert_eq!(out[1].dimensions(), (800, 400));
    }

    #[test]
    fn shopee_tall_stitched_by_2w() {
        // 750x4000 寬/高 < 0.5 → 接合並每 1500 切
        let out = shopee_layout(&[img(750, 4000)], false, 0);
        assert_eq!(heights(&out), [1500, 1500, 1000]);
        assert!(out.iter().all(ratio_ok_shopee));
    }

    #[test]
    fn shopee_unify_width() {
        let out = shopee_layout(&[img(1000, 2500), img(800, 400)], false, 0);
        // 統一寬 1000：2500 + 500 = 3000 → 2000 + 1000
        assert!(out.iter().all(|i| i.width() == 1000));
        assert_eq!(heights(&out), [2000, 1000]);
    }

    #[test]
    fn shopee_short_last_borrows() {
        // 750 寬，總高 3010 → 1500,1500,10；10 < 32 → 1500,1478,32
        let out = shopee_layout(&[img(750, 3010)], false, 0);
        assert_eq!(heights(&out), [1500, 1478, 32]);
        assert!(out.iter().all(ratio_ok_shopee));
    }

    #[test]
    fn shopee_wide_last_min_by_ratio() {
        // 寬 2000 時最後一段至少 ceil(2000/32)=63
        let out = shopee_layout(&[img(2000, 8010)], false, 0);
        assert_eq!(*heights(&out).last().unwrap(), 63);
        assert!(out.iter().all(ratio_ok_shopee));
    }

    // ---- 智慧切點 ----
    #[test]
    fn smart_cut_finds_blank_band() {
        // 1000x3000 雜訊圖，在 y=1420..1430 放白帶
        let mut im = RgbImage::new(1000, 3000);
        for (x, y, p) in im.enumerate_pixels_mut() {
            let v = ((x * 7 + y * 13) % 251) as u8;
            *p = Rgb([v, v.wrapping_mul(3), v.wrapping_add(90)]);
        }
        for y in 1420..1430 {
            for x in 0..1000 {
                im.put_pixel(x, y, Rgb([255, 255, 255]));
            }
        }
        let b = plan_cuts(&im, 1500, 0, true);
        assert!((1421..=1429).contains(&b[1]), "{:?}", b);
        assert!(b[1] >= 1350);
        // 沒有平坦區時維持原切點
        let b2 = plan_cuts(&im, 1500, 0, false);
        assert_eq!(b2[1], 1500);
    }

    #[test]
    fn smart_cut_solid_keeps_planned() {
        let b = plan_cuts(&img(1000, 3200), 1500, 0, true);
        assert_eq!(b, [0, 1500, 3000, 3200]);
    }
}
