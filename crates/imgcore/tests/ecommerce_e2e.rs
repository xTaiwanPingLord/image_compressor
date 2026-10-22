//! 端對端規格測試：產生合成圖 → 執行 → 驗證輸出符合 plan.md 平台規則。

use image::{Rgb, RgbImage, Rgba, RgbaImage};
use imgcore::cleanup::Disposal;
use imgcore::ecommerce::{self, InputImage, Job, Platform, Settings};
use imgcore::geom::Fit;
use std::path::{Path, PathBuf};

/// 類似商品照：漸層 + 雜訊 + 色塊，壓縮後大小接近真實照片。
fn photo(w: u32, h: u32, seed: u32) -> RgbImage {
    let mut s = seed.wrapping_mul(2654435761) | 1;
    RgbImage::from_fn(w, h, |x, y| {
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        let n = (s % 48) as i32 - 24;
        let block = (((x / 37) + (y / 53)) % 5) as i32 * 20;
        let c = |base: i32| (base + n + block).clamp(0, 255) as u8;
        Rgb([c((x * 255 / w) as i32), c((y * 255 / h) as i32), c(128)])
    })
}

fn save(dir: &Path, name: &str, img: &RgbImage) -> PathBuf {
    let p = dir.join(name);
    img.save(&p).unwrap();
    p
}

fn job(name: &str, main: Vec<PathBuf>, variant: Vec<PathBuf>, desc: Vec<PathBuf>) -> Job {
    Job {
        name: name.into(),
        main: main.into_iter().map(InputImage::new).collect(),
        variant: variant.into_iter().map(InputImage::new).collect(),
        desc,
        platforms: vec![Platform::Shopee, Platform::Momo],
        settings: Settings::default(),
        output_root: None,
    }
}

fn dims(p: &Path) -> (u32, u32) {
    image::image_dimensions(p).unwrap()
}

fn list(dir: &Path) -> Vec<String> {
    let mut v: Vec<String> = std::fs::read_dir(dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_file())
        .map(|e| e.file_name().to_string_lossy().to_string())
        .collect();
    v.sort();
    v
}

#[test]
fn full_run_meets_platform_specs() {
    let d = tempfile::tempdir().unwrap();
    let src = d.path();
    let m1 = save(src, "main_1.png", &photo(1600, 900, 1)); // 寬 → 1:1
    let m2 = save(src, "main_2.jpg", &photo(750, 1000, 2)); // 3:4，Shopee 保持
    let v1 = save(src, "var_1.jpg", &photo(800, 600, 3));
    let d1 = save(src, "desc_1.jpg", &photo(1000, 1800, 4));
    let d2 = save(src, "desc_2.jpg", &photo(1000, 800, 5));

    let mut j = job("223_ssd", vec![m1, m2], vec![v1], vec![d1, d2]);
    j.main[0].fit = Fit::Crop;
    let rep = ecommerce::run(&j, Disposal::OldFolder, false).unwrap();
    assert!(rep.overflow.is_empty());
    assert_eq!(rep.output_root, src);

    let shopee = src.join("shopee");
    let momo = src.join("momo");
    assert_eq!(
        list(&momo),
        [
            "223_ssd_desc_01.jpg",
            "223_ssd_desc_02.jpg",
            "223_ssd_main_01.jpg",
            "223_ssd_main_02.jpg",
            "223_ssd_variant_01.jpg"
        ]
    );

    // momo：主/選項 1000x1000、51,200–1,000,000；詳情寬 1000、1800+800 → 1500+1100
    for f in [
        "223_ssd_main_01.jpg",
        "223_ssd_main_02.jpg",
        "223_ssd_variant_01.jpg",
    ] {
        let p = momo.join(f);
        assert_eq!(dims(&p), (1000, 1000), "{f}");
        let n = std::fs::metadata(&p).unwrap().len();
        assert!((51_200..=1_000_000).contains(&n), "{f} {n}");
    }
    assert_eq!(dims(&momo.join("223_ssd_desc_01.jpg")), (1000, 1500));
    assert_eq!(dims(&momo.join("223_ssd_desc_02.jpg")), (1000, 1100));
    for f in list(&momo) {
        assert!(std::fs::metadata(momo.join(&f)).unwrap().len() <= 1_000_000);
    }

    // Shopee：主圖 1 裁成 1:1（900x900）、主圖 2 維持 3:4；選項 1:1 補白；詳情比例都 OK 各自保留
    assert_eq!(dims(&shopee.join("223_ssd_main_01.jpg")), (900, 900));
    assert_eq!(dims(&shopee.join("223_ssd_main_02.jpg")), (750, 1000));
    assert_eq!(dims(&shopee.join("223_ssd_variant_01.jpg")), (800, 800));
    assert_eq!(dims(&shopee.join("223_ssd_desc_01.jpg")), (1000, 1800));
    assert_eq!(dims(&shopee.join("223_ssd_desc_02.jpg")), (1000, 800));
    for f in list(&shopee) {
        assert!(std::fs::metadata(shopee.join(&f)).unwrap().len() <= 2_000_000);
    }

    // 原檔不動
    assert_eq!(dims(&src.join("main_1.png")), (1600, 900));
}

#[test]
fn rerun_cleans_only_processed_categories() {
    let d = tempfile::tempdir().unwrap();
    let src = d.path();
    let m = save(src, "m.jpg", &photo(500, 500, 1));
    let tall = save(src, "long.jpg", &photo(800, 4000, 2));
    let j1 = job("p", vec![m.clone()], vec![], vec![tall]);
    ecommerce::run(&j1, Disposal::OldFolder, false).unwrap();
    let momo = src.join("momo");
    // 800x4000 → 1000x5000 → 1500×3 + 500
    assert_eq!(
        list(&momo).iter().filter(|f| f.contains("_desc_")).count(),
        4
    );

    // 第二次只有詳情圖、且變短 → 舊 desc 全清掉，main 保留
    let short = save(src, "short.jpg", &photo(1000, 1200, 3));
    let mut j2 = job("p", vec![], vec![], vec![short]);
    j2.platforms = vec![Platform::Momo];
    let rep = ecommerce::run(&j2, Disposal::OldFolder, false).unwrap();
    assert_eq!(rep.disposed.len(), 4);
    assert_eq!(list(&momo), ["p_desc_01.jpg", "p_main_01.jpg"]);
    assert_eq!(list(&momo.join("_old")).len(), 4);
}

#[test]
fn overflow_blocks_whole_batch() {
    let d = tempfile::tempdir().unwrap();
    let src = d.path();
    let m = save(src, "m.jpg", &photo(500, 500, 1));
    // 1000 寬 × 7000 高 → momo 5 段；上限設 4 → 失敗
    let t = save(
        src,
        "t.jpg",
        &RgbImage::from_pixel(1000, 7000, Rgb([200, 200, 200])),
    );
    let mut j = job("x", vec![m], vec![], vec![t]);
    j.settings.momo_max_desc = 4;
    let rep = ecommerce::run(&j, Disposal::OldFolder, false).unwrap();
    assert_eq!(rep.overflow.len(), 1);
    assert_eq!(rep.overflow[0].count, 5);
    assert_eq!(rep.overflow[0].limit, 4);
    assert!(rep.written.is_empty());
    assert!(!src.join("momo").exists() && !src.join("shopee").exists());
}

#[test]
fn transparent_png_on_white_and_no_metadata() {
    let d = tempfile::tempdir().unwrap();
    let src = d.path();
    let mut im = RgbaImage::from_pixel(600, 600, Rgba([0, 0, 0, 0]));
    for y in 200..400 {
        for x in 200..400 {
            im.put_pixel(x, y, Rgba([255, 0, 0, 255]));
        }
    }
    let p = src.join("logo.png");
    im.save(&p).unwrap();
    let mut j = job("t", vec![p], vec![], vec![]);
    j.platforms = vec![Platform::Shopee];
    ecommerce::run(&j, Disposal::OldFolder, false).unwrap();
    let out = src.join("shopee/t_main_01.jpg");
    let data = std::fs::read(&out).unwrap();
    assert!(!data.windows(4).any(|w| w == b"Exif"));
    let img = image::load_from_memory(&data).unwrap().to_rgb8();
    let corner = img.get_pixel(5, 5).0;
    assert!(corner.iter().all(|&c| c > 245), "{corner:?}");
    let center = img.get_pixel(300, 300).0;
    assert!(center[0] > 200 && center[1] < 60, "{center:?}");
}

#[test]
fn shopee_tall_detail_split_and_smart_cut() {
    let d = tempfile::tempdir().unwrap();
    let src = d.path();
    // 750x3200：寬/高 < 0.5 → 每 1500 切；第 1380–1400 列白帶，開智慧切點應切在白帶
    let mut im = photo(750, 3200, 9);
    for y in 1380..1400 {
        for x in 0..750 {
            im.put_pixel(x, y, Rgb([255, 255, 255]));
        }
    }
    let p = save(src, "d.png", &im);
    let mut j = job("s", vec![], vec![], vec![p]);
    j.platforms = vec![Platform::Shopee];
    j.settings.smart_cut = true;
    let rep = ecommerce::run(&j, Disposal::OldFolder, true).unwrap();
    let hs: Vec<u32> = rep.outputs.iter().map(|o| o.height).collect();
    assert_eq!(hs.len(), 3);
    assert!((1381..=1399).contains(&hs[0]), "{hs:?}");
    assert_eq!(hs.iter().sum::<u32>(), 3200);
    assert!(
        rep.outputs
            .iter()
            .all(|o| o.width == 750 && o.height <= 1500)
    );
    // dry-run 不寫檔
    assert!(!src.join("shopee").exists());
}
