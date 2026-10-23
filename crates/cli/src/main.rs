//! imgc — image_compressor 命令列工具（第一階段：電商模式）。

use clap::{Parser, Subcommand, ValueEnum};
use imgcore::cleanup::Disposal;
use imgcore::ecommerce::{self, Category, InputImage, Job, Platform, Settings};
use imgcore::geom::Fit;
use imgcore::{load, natsort};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

#[derive(Parser)]
#[command(
    name = "imgc",
    version,
    about = "圖片壓縮工具（電商模式：Shopee / momo）"
)]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Clone, Copy, ValueEnum)]
enum PlatformArg {
    Shopee,
    Momo,
}

#[derive(Clone, Copy, ValueEnum)]
enum FitArg {
    Pad,
    Crop,
}

#[derive(Subcommand)]
enum Cmd {
    /// 產生電商平台用圖
    Ecommerce {
        /// 檔名前綴，例如 223_ssd
        #[arg(long)]
        name: String,
        /// 主圖（檔案或資料夾，可多個）
        #[arg(long, num_args = 1..)]
        main: Vec<PathBuf>,
        /// 選項圖
        #[arg(long, num_args = 1..)]
        variant: Vec<PathBuf>,
        /// 詳情圖
        #[arg(long, num_args = 1..)]
        desc: Vec<PathBuf>,
        /// 平台（預設兩者）
        #[arg(long, value_enum, num_args = 1..)]
        platform: Vec<PlatformArg>,
        /// 主圖/選項圖比例不符時的預設處理
        #[arg(long, value_enum, default_value = "pad")]
        fit: FitArg,
        /// 指定改用裁切的檔案（檔名或路徑，可多個）
        #[arg(long, num_args = 1..)]
        crop: Vec<String>,
        /// 指定改用補白的檔案
        #[arg(long, num_args = 1..)]
        pad: Vec<String>,
        #[arg(long, default_value_t = 12)]
        shopee_max: usize,
        #[arg(long, default_value_t = 18)]
        momo_max: usize,
        /// Shopee 輸出最大寬度（0 = 不限制）
        #[arg(long, default_value_t = 2000)]
        shopee_max_width: u32,
        /// momo 詳情圖尾段低於此高度時從前一段挪高度（0 = 保持實際高度）
        #[arg(long, default_value_t = 300)]
        momo_min_last: u32,
        /// 智慧切點（切段處往上 150px 找最接近純色的橫列）
        #[arg(long)]
        smart_cut: bool,
        /// 品質上限（每張圖各自找符合大小限制的最高品質，不超過此值）
        #[arg(long, default_value_t = 92)]
        max_quality: u8,
        /// 色度 4:4:4（文字邊緣較清晰、檔案較大）
        #[arg(long)]
        chroma444: bool,
        /// 輸出根目錄（預設：圖片最多的來源資料夾）
        #[arg(long)]
        out: Option<PathBuf>,
        /// 保持輸入順序（預設依檔名自然排序）
        #[arg(long)]
        keep_order: bool,
        /// 只預檢與壓縮，不寫檔
        #[arg(long)]
        dry_run: bool,
        /// 舊檔移到 _old/ 而非系統垃圾桶
        #[arg(long)]
        no_trash: bool,
        /// 以 JSON 輸出結果
        #[arg(long)]
        json: bool,
    },
    /// 用 JSON 工作檔執行（格式同 imgcore::ecommerce::Job）
    Job {
        file: PathBuf,
        #[arg(long)]
        dry_run: bool,
        #[arg(long)]
        no_trash: bool,
        #[arg(long)]
        json: bool,
    },
    /// 普通模式：壓縮圖片（檔案或資料夾，資料夾含子資料夾）
    Compress {
        #[arg(required = true)]
        paths: Vec<PathBuf>,
        /// 品質 1–100
        #[arg(short, long, default_value_t = 80)]
        quality: u8,
        /// 無損
        #[arg(long)]
        lossless: bool,
        /// 目標大小（KB），指定時改為依大小搜尋品質
        #[arg(long)]
        max_kb: Option<u64>,
        /// 輸出格式：same / jpeg / png / webp
        #[arg(long, default_value = "same")]
        format: String,
        /// 長邊縮放到此像素（不放大）
        #[arg(long)]
        long_edge: Option<u32>,
        /// 輸出資料夾（預設與原檔相同）
        #[arg(long)]
        out: Option<PathBuf>,
        /// 檔名後綴
        #[arg(long, default_value = "_compressed")]
        suffix: String,
        /// 不保留 EXIF
        #[arg(long)]
        strip: bool,
        #[arg(long)]
        json: bool,
    },
    /// 顯示圖片尺寸及各平台是否需選擇補白/裁切
    Info { files: Vec<PathBuf> },
    /// 檢查此電腦能否解碼 HEIC（系統解碼器自我測試）
    HeifCheck,
}

fn expand(paths: &[PathBuf], keep_order: bool) -> Result<Vec<PathBuf>, String> {
    let mut out = Vec::new();
    for p in paths {
        let p = &std::path::absolute(p).unwrap_or_else(|_| p.clone());
        if p.is_dir() {
            let mut v: Vec<PathBuf> = std::fs::read_dir(p)
                .map_err(|e| format!("{}: {e}", p.display()))?
                .filter_map(|e| e.ok().map(|e| e.path()))
                .filter(|p| p.is_file() && load::is_image_path(p))
                .collect();
            natsort::sort_paths(&mut v);
            out.extend(v);
        } else if p.is_file() {
            out.push(p.clone());
        } else {
            return Err(format!("找不到：{}", p.display()));
        }
    }
    if !keep_order {
        natsort::sort_paths(&mut out);
    }
    Ok(out)
}

fn matches_any(p: &Path, list: &[String]) -> bool {
    let fname = p
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    list.iter().any(|s| s == &fname || Path::new(s) == p)
}

fn print_report(rep: &ecommerce::RunReport, json: bool, dry_run: bool) {
    if json {
        println!("{}", serde_json::to_string_pretty(rep).unwrap());
        return;
    }
    for (pf, n) in &rep.desc_counts {
        println!("{} 詳情圖段數：{n}", pf.dir_name());
    }
    if !rep.overflow.is_empty() {
        for o in &rep.overflow {
            eprintln!(
                "⚠ {} 詳情圖會切成 {} 張，超過上限 {} 張。整批未輸出，請刪減詳情圖後重試。",
                o.platform.dir_name(),
                o.count,
                o.limit
            );
        }
        return;
    }
    for o in &rep.outputs {
        println!(
            "{:<7} {:<28} {:>5}×{:<5} {:>9} bytes  q{:<3} {:?}",
            o.platform.dir_name(),
            o.file_name,
            o.width,
            o.height,
            o.bytes,
            o.quality,
            o.mode
        );
        for w in &o.warnings {
            println!("        ⚠ {w}");
        }
    }
    if dry_run {
        println!(
            "（dry-run：未寫入檔案）輸出位置將是 {}",
            rep.output_root.display()
        );
    } else {
        if !rep.disposed.is_empty() {
            println!("已移除舊檔 {} 個", rep.disposed.len());
        }
        println!(
            "已輸出 {} 個檔案到 {}",
            rep.written.len(),
            rep.output_root.display()
        );
    }
}

fn exec(job: &Job, no_trash: bool, dry_run: bool, json: bool) -> ExitCode {
    let how = if no_trash {
        Disposal::OldFolder
    } else {
        Disposal::platform_default()
    };
    match ecommerce::run(job, how, dry_run) {
        Ok(rep) => {
            print_report(&rep, json, dry_run);
            if !rep.overflow.is_empty() {
                ExitCode::from(2)
            } else {
                ExitCode::SUCCESS
            }
        }
        Err(e) => {
            eprintln!("錯誤：{e}");
            ExitCode::FAILURE
        }
    }
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match cli.cmd {
        Cmd::Ecommerce {
            name,
            main,
            variant,
            desc,
            platform,
            fit,
            crop,
            pad,
            shopee_max,
            momo_max,
            shopee_max_width,
            momo_min_last,
            smart_cut,
            max_quality,
            chroma444,
            out,
            keep_order,
            dry_run,
            no_trash,
            json,
        } => {
            let default_fit = match fit {
                FitArg::Pad => Fit::Pad,
                FitArg::Crop => Fit::Crop,
            };
            let to_inputs = |v: Vec<PathBuf>| -> Vec<InputImage> {
                v.into_iter()
                    .map(|p| {
                        let fit = if matches_any(&p, &crop) {
                            Fit::Crop
                        } else if matches_any(&p, &pad) {
                            Fit::Pad
                        } else {
                            default_fit
                        };
                        InputImage { path: p, fit }
                    })
                    .collect()
            };
            let (main, variant, desc) = match (
                expand(&main, keep_order),
                expand(&variant, keep_order),
                expand(&desc, keep_order),
            ) {
                (Ok(a), Ok(b), Ok(c)) => (a, b, c),
                (Err(e), _, _) | (_, Err(e), _) | (_, _, Err(e)) => {
                    eprintln!("錯誤：{e}");
                    return ExitCode::FAILURE;
                }
            };
            let platforms = if platform.is_empty() {
                vec![Platform::Shopee, Platform::Momo]
            } else {
                platform
                    .iter()
                    .map(|p| match p {
                        PlatformArg::Shopee => Platform::Shopee,
                        PlatformArg::Momo => Platform::Momo,
                    })
                    .collect()
            };
            let job = Job {
                name,
                main: to_inputs(main),
                variant: to_inputs(variant),
                desc,
                platforms,
                settings: Settings {
                    shopee_max_desc: shopee_max,
                    momo_max_desc: momo_max,
                    smart_cut,
                    max_quality,
                    chroma444,
                    shopee_max_width,
                    momo_min_last,
                    ..Settings::default()
                },
                output_root: out,
            };
            exec(&job, no_trash, dry_run, json)
        }
        Cmd::Job {
            file,
            dry_run,
            no_trash,
            json,
        } => {
            let job: Job = match std::fs::read_to_string(&file)
                .map_err(|e| e.to_string())
                .and_then(|s| serde_json::from_str(&s).map_err(|e| e.to_string()))
            {
                Ok(j) => j,
                Err(e) => {
                    eprintln!("無法讀取工作檔：{e}");
                    return ExitCode::FAILURE;
                }
            };
            exec(&job, no_trash, dry_run, json)
        }
        Cmd::Compress {
            paths,
            quality,
            lossless,
            max_kb,
            format,
            long_edge,
            out,
            suffix,
            strip,
            json,
        } => {
            use imgcore::normal as nm;
            let format = match format.to_ascii_lowercase().as_str() {
                "same" => nm::OutFormat::Same,
                "jpeg" | "jpg" => nm::OutFormat::Jpeg,
                "png" => nm::OutFormat::Png,
                "webp" => nm::OutFormat::Webp,
                other => {
                    eprintln!("不支援的格式：{other}");
                    return ExitCode::FAILURE;
                }
            };
            let mut inputs: Vec<(PathBuf, Option<PathBuf>)> = Vec::new();
            fn walk(d: &Path, base: &Path, out: &mut Vec<(PathBuf, Option<PathBuf>)>) {
                let mut v: Vec<PathBuf> = std::fs::read_dir(d)
                    .map(|rd| rd.filter_map(|e| e.ok().map(|e| e.path())).collect())
                    .unwrap_or_default();
                natsort::sort_paths(&mut v);
                for p in v {
                    if p.is_dir() {
                        walk(&p, base, out);
                    } else if load::is_image_path(&p) {
                        out.push((p, Some(base.to_path_buf())));
                    }
                }
            }
            for p in &paths {
                let p = std::path::absolute(p).unwrap_or_else(|_| p.clone());
                if p.is_dir() {
                    walk(&p, &p, &mut inputs);
                } else if p.is_file() {
                    inputs.push((p, None));
                } else {
                    eprintln!("找不到：{}", p.display());
                    return ExitCode::FAILURE;
                }
            }
            let o = nm::Options {
                quality: quality.clamp(1, 100),
                lossless,
                max_size: max_kb.map(|k| k * 1000),
                format,
                resize: if long_edge.is_some() {
                    nm::ResizeMode::LongEdge
                } else {
                    nm::ResizeMode::None
                },
                resize_value: long_edge.unwrap_or(100),
                output_dir: out,
                keep_structure: true,
                suffix,
                keep_metadata: !strip,
                ..nm::Options::default()
            };
            let res = nm::run_batch(&inputs, &o, Disposal::platform_default(), &|_, _| {});
            if json {
                println!("{}", serde_json::to_string_pretty(&res).unwrap());
            } else {
                for r in &res {
                    let name = r.input.file_name().unwrap_or_default().to_string_lossy();
                    match r.status {
                        nm::Status::Failed => {
                            println!(
                                "✗ {name}：{}",
                                r.error.as_ref().map(|e| e.message.as_str()).unwrap_or("")
                            )
                        }
                        _ => println!(
                            "{} {name}  {} → {} bytes（−{:.1}%）{}",
                            if r.status == nm::Status::Done {
                                "✓"
                            } else {
                                "="
                            },
                            r.original_size,
                            r.new_size,
                            (1.0 - r.new_size as f64 / r.original_size.max(1) as f64) * 100.0,
                            r.output
                                .as_ref()
                                .map(|p| format!(" → {}", p.display()))
                                .unwrap_or_default()
                        ),
                    }
                }
            }
            if res.iter().any(|r| r.status == nm::Status::Failed) {
                ExitCode::FAILURE
            } else {
                ExitCode::SUCCESS
            }
        }
        Cmd::HeifCheck => {
            println!("HEIC supported: {}", imgcore::heif::supported());
            let mut ok = true;
            for (name, r) in imgcore::heif::self_test() {
                match r {
                    Ok(m) => println!("  OK   {name}: {m}"),
                    Err(e) => {
                        ok = false;
                        println!("  FAIL {name}: {e}");
                    }
                }
            }
            if ok { ExitCode::SUCCESS } else { ExitCode::FAILURE }
        }
        Cmd::Info { files } => {
            let mut ok = true;
            for f in files {
                match load::dimensions(&f) {
                    Ok((w, h)) => {
                        let flag = |pf, cat| {
                            if ecommerce::needs_fit_choice(pf, cat, w, h) {
                                "需選"
                            } else {
                                "—"
                            }
                        };
                        println!(
                            "{}  {w}×{h}  Shopee主圖:{} Shopee選項:{} momo主/選項:{}",
                            f.display(),
                            flag(Platform::Shopee, Category::Main),
                            flag(Platform::Shopee, Category::Variant),
                            flag(Platform::Momo, Category::Main),
                        );
                    }
                    Err(e) => {
                        eprintln!("{e}");
                        ok = false;
                    }
                }
            }
            if ok {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            }
        }
    }
}
