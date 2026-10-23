//! 最小限度的 EXIF 處理：把 Orientation 改為 1（像素已轉正時使用）。

/// 輸入可為 "Exif\0\0" + TIFF 或純 TIFF 資料；回傳純 TIFF 資料（Orientation 已設為 1）。
pub fn reset_orientation(exif: &[u8]) -> Vec<u8> {
    let mut d = exif.strip_prefix(b"Exif\0\0").unwrap_or(exif).to_vec();
    if d.len() < 8 {
        return d;
    }
    let le = match &d[..2] {
        b"II" => true,
        b"MM" => false,
        _ => return d,
    };
    let rd16 = |d: &[u8], o: usize| -> Option<u16> {
        let b = d.get(o..o + 2)?;
        Some(if le {
            u16::from_le_bytes([b[0], b[1]])
        } else {
            u16::from_be_bytes([b[0], b[1]])
        })
    };
    let rd32 = |d: &[u8], o: usize| -> Option<u32> {
        let b = d.get(o..o + 4)?;
        Some(if le {
            u32::from_le_bytes([b[0], b[1], b[2], b[3]])
        } else {
            u32::from_be_bytes([b[0], b[1], b[2], b[3]])
        })
    };
    let Some(ifd) = rd32(&d, 4).map(|v| v as usize) else {
        return d;
    };
    let Some(n) = rd16(&d, ifd) else { return d };
    for i in 0..n as usize {
        let e = ifd + 2 + i * 12;
        if rd16(&d, e) == Some(0x0112) && e + 10 <= d.len() {
            let one = if le {
                1u16.to_le_bytes()
            } else {
                1u16.to_be_bytes()
            };
            d[e + 8..e + 10].copy_from_slice(&one);
            break;
        }
    }
    d
}

/// 包成 JPEG APP1 payload（"Exif\0\0" + TIFF）。
pub fn to_app1(tiff: &[u8]) -> Vec<u8> {
    let mut v = b"Exif\0\0".to_vec();
    v.extend_from_slice(tiff);
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(le: bool, orient: u16) -> Vec<u8> {
        let mut v = Vec::new();
        let p16 =
            |v: &mut Vec<u8>, x: u16| v.extend(if le { x.to_le_bytes() } else { x.to_be_bytes() });
        let p32 =
            |v: &mut Vec<u8>, x: u32| v.extend(if le { x.to_le_bytes() } else { x.to_be_bytes() });
        v.extend(if le { b"II" } else { b"MM" });
        p16(&mut v, 42);
        p32(&mut v, 8);
        p16(&mut v, 2);
        // tag 0x010F Make（ASCII，不影響）
        p16(&mut v, 0x010F);
        p16(&mut v, 2);
        p32(&mut v, 4);
        v.extend(b"ABC\0");
        // Orientation
        p16(&mut v, 0x0112);
        p16(&mut v, 3);
        p32(&mut v, 1);
        p16(&mut v, orient);
        p16(&mut v, 0);
        p32(&mut v, 0);
        v
    }

    #[test]
    fn resets_both_endians() {
        for le in [true, false] {
            let mut src = b"Exif\0\0".to_vec();
            src.extend(sample(le, 6));
            let out = reset_orientation(&src);
            assert_eq!(out, sample(le, 1));
        }
    }

    #[test]
    fn junk_is_untouched() {
        assert_eq!(reset_orientation(b"xyz"), b"xyz");
    }
}
