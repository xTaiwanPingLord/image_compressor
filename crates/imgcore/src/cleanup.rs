//! 舊輸出清理：只處理本次有輸出的類別，移到垃圾桶或 `_old/`。

use crate::ecommerce::Category;
use crate::{Error, Result};
use std::path::{Path, PathBuf};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Disposal {
    /// 系統垃圾桶（桌面）
    Trash,
    /// 移到輸出資料夾下的 `_old/`（無垃圾桶的平台）
    OldFolder,
}

impl Disposal {
    pub fn platform_default() -> Self {
        if cfg!(feature = "trash") {
            Disposal::Trash
        } else {
            Disposal::OldFolder
        }
    }
}

/// 列出 `dir` 中符合 `^name_(cat)_\d+\.jpg$` 的舊檔。
pub fn find_old_outputs(dir: &Path, name: &str, cats: &[Category]) -> Result<Vec<PathBuf>> {
    if cats.is_empty() || !dir.is_dir() {
        return Ok(vec![]);
    }
    let alt = cats
        .iter()
        .map(|c| c.prefix())
        .collect::<Vec<_>>()
        .join("|");
    let re = regex::Regex::new(&format!(r"^{}_({})_\d+\.jpg$", regex::escape(name), alt))
        .map_err(|e| Error::Invalid(e.to_string()))?;
    let mut v: Vec<PathBuf> = std::fs::read_dir(dir)?
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().map(|t| t.is_file()).unwrap_or(false))
        .filter(|e| re.is_match(&e.file_name().to_string_lossy()))
        .map(|e| e.path())
        .collect();
    v.sort();
    Ok(v)
}

pub fn dispose(paths: &[PathBuf], how: Disposal) -> Result<()> {
    if paths.is_empty() {
        return Ok(());
    }
    match how {
        Disposal::Trash => {
            #[cfg(feature = "trash")]
            {
                trash::delete_all(paths).map_err(|e| Error::Trash(e.to_string()))
            }
            #[cfg(not(feature = "trash"))]
            {
                dispose(paths, Disposal::OldFolder)
            }
        }
        Disposal::OldFolder => {
            for p in paths {
                let dir = p.parent().unwrap_or(Path::new(".")).join("_old");
                std::fs::create_dir_all(&dir)?;
                let fname = p.file_name().unwrap().to_string_lossy().to_string();
                let mut dst = dir.join(&fname);
                let mut n = 1;
                while dst.exists() {
                    let stem = fname.trim_end_matches(".jpg");
                    dst = dir.join(format!("{stem} ({n}).jpg"));
                    n += 1;
                }
                std::fs::rename(p, &dst)?;
            }
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_matching_categories() {
        let d = tempfile::tempdir().unwrap();
        for f in [
            "abc_main_01.jpg",
            "abc_desc_01.jpg",
            "abc_desc_12.jpg",
            "abc_variant_1.jpg",
            "abcd_main_01.jpg",
            "abc_main_01.png",
            "abc_main_x.jpg",
            "keep.jpg",
        ] {
            std::fs::write(d.path().join(f), b"x").unwrap();
        }
        let names = |v: Vec<PathBuf>| {
            v.iter()
                .map(|p| p.file_name().unwrap().to_string_lossy().to_string())
                .collect::<Vec<_>>()
        };
        let v = find_old_outputs(d.path(), "abc", &[Category::Desc]).unwrap();
        assert_eq!(names(v), ["abc_desc_01.jpg", "abc_desc_12.jpg"]);
        let v = find_old_outputs(d.path(), "abc", &[Category::Main, Category::Variant]).unwrap();
        assert_eq!(names(v), ["abc_main_01.jpg", "abc_variant_1.jpg"]);
    }

    #[test]
    fn name_is_escaped() {
        let d = tempfile::tempdir().unwrap();
        std::fs::write(d.path().join("a.b_main_01.jpg"), b"x").unwrap();
        std::fs::write(d.path().join("axb_main_01.jpg"), b"x").unwrap();
        let v = find_old_outputs(d.path(), "a.b", &[Category::Main]).unwrap();
        assert_eq!(v.len(), 1);
    }

    #[test]
    fn old_folder_no_overwrite() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join("n_main_01.jpg");
        std::fs::write(&p, b"1").unwrap();
        dispose(std::slice::from_ref(&p), Disposal::OldFolder).unwrap();
        std::fs::write(&p, b"2").unwrap();
        dispose(std::slice::from_ref(&p), Disposal::OldFolder).unwrap();
        assert!(!p.exists());
        assert!(d.path().join("_old/n_main_01.jpg").exists());
        assert!(d.path().join("_old/n_main_01 (1).jpg").exists());
    }
}
