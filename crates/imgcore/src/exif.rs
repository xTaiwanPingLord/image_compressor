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

/// JPEG APP1 marker 的 payload 上限（65535 − 2 bytes 長度欄位）。
pub const APP1_MAX: usize = 65533;

/// 讓 EXIF 能放進單一 APP1：太大時先拿掉 IFD1 縮圖，仍太大回傳 None。
/// 回傳 (APP1 payload, 是否有刪減)。
pub fn fit_app1(tiff: &[u8]) -> (Option<Vec<u8>>, bool) {
    let app1 = to_app1(tiff);
    if app1.len() <= APP1_MAX {
        return (Some(app1), false);
    }
    match strip_thumbnail(tiff) {
        Some(t) if t.len() + 6 <= APP1_MAX => (Some(to_app1(&t)), true),
        _ => (None, true),
    }
}

/// 拿掉 IFD1（縮圖）：IFD0 的 next 指標設 0，並截掉放在最後的縮圖資料。
fn strip_thumbnail(tiff: &[u8]) -> Option<Vec<u8>> {
    let le = match tiff.get(..2)? {
        b"II" => true,
        b"MM" => false,
        _ => return None,
    };
    let rd16 = |o: usize| -> Option<usize> {
        let b = tiff.get(o..o + 2)?;
        Some(if le { u16::from_le_bytes([b[0], b[1]]) } else { u16::from_be_bytes([b[0], b[1]]) } as usize)
    };
    let rd32 = |o: usize| -> Option<usize> {
        let b = tiff.get(o..o + 4)?;
        let a = [b[0], b[1], b[2], b[3]];
        Some(if le { u32::from_le_bytes(a) } else { u32::from_be_bytes(a) } as usize)
    };
    let ifd0 = rd32(4)?;
    let n0 = rd16(ifd0)?;
    let next_pos = ifd0 + 2 + n0 * 12;
    let ifd1 = rd32(next_pos)?;
    if ifd1 == 0 {
        return None;
    }
    // 縮圖起點：JPEGInterchangeFormat (0x0201)；沒有就從 IFD1 起截
    let mut thumb = None;
    if let Some(n1) = rd16(ifd1) {
        for i in 0..n1 {
            let e = ifd1 + 2 + i * 12;
            if rd16(e) == Some(0x0201) {
                thumb = rd32(e + 8);
            }
        }
    }
    let cut = thumb.unwrap_or(ifd1);
    if cut < next_pos + 4 || cut > tiff.len() {
        return None;
    }
    let mut out = tiff[..cut].to_vec();
    out[next_pos..next_pos + 4].copy_from_slice(&[0, 0, 0, 0]);
    Some(out)
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
    fn oversized_exif_drops_thumbnail_or_all() {
        // IFD0 一個欄位，next 指向 IFD1（含 0x0201 縮圖偏移），縮圖 70 KB 放最後
        let mut v = sample(true, 6);
        let next_pos = 8 + 2 + 2 * 12;
        let ifd1 = v.len();
        v[next_pos..next_pos + 4].copy_from_slice(&(ifd1 as u32).to_le_bytes());
        let thumb_off = ifd1 + 2 + 12 + 4;
        v.extend(1u16.to_le_bytes());
        v.extend(0x0201u16.to_le_bytes());
        v.extend(4u16.to_le_bytes());
        v.extend(1u32.to_le_bytes());
        v.extend((thumb_off as u32).to_le_bytes());
        v.extend(0u32.to_le_bytes());
        v.resize(thumb_off + 70_000, 0xAB);
        let (app1, cut) = fit_app1(&v);
        let app1 = app1.unwrap();
        assert!(cut && app1.len() <= APP1_MAX && app1.len() < 200);
        // 沒有縮圖可拿：整段放不下就丟掉
        let mut big = sample(true, 1);
        big.resize(80_000, 0);
        assert_eq!(fit_app1(&big), (None, true));
        // 小的不動
        assert_eq!(fit_app1(&sample(true, 1)).1, false);
    }

    #[test]
    fn junk_is_untouched() {
        assert_eq!(reset_orientation(b"xyz"), b"xyz");
    }
}
