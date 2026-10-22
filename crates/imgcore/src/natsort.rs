//! 自然排序：數字段依數值比較（img_2 < img_10），文字段不分大小寫。

use std::cmp::Ordering;
use std::path::Path;

fn chunks(s: &str) -> Vec<(bool, &str)> {
    let mut out = Vec::new();
    let mut start = 0;
    let mut prev: Option<bool> = None;
    for (i, c) in s.char_indices() {
        let d = c.is_ascii_digit();
        if let Some(p) = prev
            && p != d
        {
            out.push((p, &s[start..i]));
            start = i;
        }
        prev = Some(d);
    }
    if let Some(p) = prev {
        out.push((p, &s[start..]));
    }
    out
}

pub fn natural_cmp(a: &str, b: &str) -> Ordering {
    let (ca, cb) = (chunks(a), chunks(b));
    for (x, y) in ca.iter().zip(cb.iter()) {
        let ord = match (x.0, y.0) {
            (true, true) => {
                let xs = x.1.trim_start_matches('0');
                let ys = y.1.trim_start_matches('0');
                xs.len()
                    .cmp(&ys.len())
                    .then_with(|| xs.cmp(ys))
                    .then_with(|| x.1.len().cmp(&y.1.len()))
            }
            (false, false) => x.1.to_lowercase().cmp(&y.1.to_lowercase()),
            (true, false) => Ordering::Less,
            (false, true) => Ordering::Greater,
        };
        if ord != Ordering::Equal {
            return ord;
        }
    }
    ca.len().cmp(&cb.len()).then_with(|| a.cmp(b))
}

/// 依檔名（不含資料夾）自然排序。
pub fn sort_paths<P: AsRef<Path>>(v: &mut [P]) {
    v.sort_by(|a, b| {
        let fa = a
            .as_ref()
            .file_name()
            .map(|s| s.to_string_lossy())
            .unwrap_or_default();
        let fb = b
            .as_ref()
            .file_name()
            .map(|s| s.to_string_lossy())
            .unwrap_or_default();
        natural_cmp(&fa, &fb)
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn numbers_by_value() {
        let mut v = vec!["img_10.jpg", "img_2.jpg", "img_1.jpg", "IMG_3.png", "a.jpg"];
        v.sort_by(|a, b| natural_cmp(a, b));
        assert_eq!(
            v,
            ["a.jpg", "img_1.jpg", "img_2.jpg", "IMG_3.png", "img_10.jpg"]
        );
    }

    #[test]
    fn leading_zeros() {
        assert_eq!(natural_cmp("p_01", "p_1"), Ordering::Greater);
        assert_eq!(natural_cmp("p_02", "p_10"), Ordering::Less);
    }

    #[test]
    fn chinese_names() {
        let mut v = vec!["詳情12.png", "詳情3.png"];
        v.sort_by(|a, b| natural_cmp(a, b));
        assert_eq!(v, ["詳情3.png", "詳情12.png"]);
    }
}
