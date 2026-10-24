//! macOS / iOS：ImageIO（macOS 10.13+、iOS 11+ 內建 HEIF 解碼，硬體或軟體 HEVC）。
//!
//! `CGImageSourceCreateImageAtIndex` 不套用 irot / imir（heif_check 實測 raw 維持編碼尺寸），以 Orientation 屬性回報、
//! 不轉像素（同 JPEG 的 EXIF 方向）；clap 預期會套用（待實際檔案驗證），回報 `Applied::Crop`。
//! 像素畫進 sRGB 的 CGBitmapContext，由 ColorSync 轉換色彩空間（Display P3 等）。

use super::{Applied, Raw, unsupported};
use crate::Result;
use image::RgbaImage;
use std::ffi::c_void;

type CFTypeRef = *const c_void;
type CGFloat = f64;

#[repr(C)]
struct CGPoint {
    x: CGFloat,
    y: CGFloat,
}
#[repr(C)]
struct CGSize {
    width: CGFloat,
    height: CGFloat,
}
#[repr(C)]
struct CGRect {
    origin: CGPoint,
    size: CGSize,
}

#[link(name = "CoreFoundation", kind = "framework")]
unsafe extern "C" {
    fn CFDataCreate(alloc: CFTypeRef, bytes: *const u8, len: isize) -> CFTypeRef;
    fn CFRelease(cf: CFTypeRef);
}

#[link(name = "ImageIO", kind = "framework")]
unsafe extern "C" {
    fn CGImageSourceCreateWithData(data: CFTypeRef, options: CFTypeRef) -> CFTypeRef;
    fn CGImageSourceGetCount(src: CFTypeRef) -> usize;
    fn CGImageSourceCreateImageAtIndex(src: CFTypeRef, index: usize, options: CFTypeRef) -> CFTypeRef;
}

#[link(name = "CoreGraphics", kind = "framework")]
unsafe extern "C" {
    static kCGColorSpaceSRGB: CFTypeRef;
    fn CGColorSpaceCreateWithName(name: CFTypeRef) -> CFTypeRef;
    fn CGImageGetWidth(img: CFTypeRef) -> usize;
    fn CGImageGetHeight(img: CFTypeRef) -> usize;
    fn CGBitmapContextCreate(
        data: *mut c_void,
        width: usize,
        height: usize,
        bits_per_component: usize,
        bytes_per_row: usize,
        space: CFTypeRef,
        bitmap_info: u32,
    ) -> CFTypeRef;
    fn CGContextDrawImage(ctx: CFTypeRef, rect: CGRect, img: CFTypeRef);
    fn CGContextRelease(ctx: CFTypeRef);
}

/// kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault → RGBA（預乘）
const RGBA_PREMUL: u32 = 1;

/// CF 物件的 RAII 包裝
struct Cf(CFTypeRef);
impl Drop for Cf {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe { CFRelease(self.0) }
        }
    }
}

pub fn supported() -> bool {
    super::self_check()
}

pub fn decode(data: &[u8]) -> Result<Raw> {
    unsafe {
        let d = Cf(CFDataCreate(std::ptr::null(), data.as_ptr(), data.len() as isize));
        if d.0.is_null() {
            return Err(super::derr("CFDataCreate failed"));
        }
        let src = Cf(CGImageSourceCreateWithData(d.0, std::ptr::null()));
        if src.0.is_null() || CGImageSourceGetCount(src.0) == 0 {
            return Err(unsupported());
        }
        let img = Cf(CGImageSourceCreateImageAtIndex(src.0, 0, std::ptr::null()));
        if img.0.is_null() {
            // 容器能讀但解不出像素：多半是沒有 HEVC 解碼器
            return Err(unsupported());
        }
        let (w, h) = (CGImageGetWidth(img.0), CGImageGetHeight(img.0));
        if w == 0 || h == 0 {
            return Err(super::derr("ImageIO: empty image"));
        }
        let stride = w * 4;
        let mut buf = vec![0u8; stride * h];
        let cs = Cf(CGColorSpaceCreateWithName(kCGColorSpaceSRGB));
        if cs.0.is_null() {
            return Err(super::derr("ImageIO: no sRGB color space"));
        }
        let ctx = CGBitmapContextCreate(buf.as_mut_ptr().cast(), w, h, 8, stride, cs.0, RGBA_PREMUL);
        if ctx.is_null() {
            return Err(super::derr("CGBitmapContextCreate failed"));
        }
        let rect = CGRect {
            origin: CGPoint { x: 0.0, y: 0.0 },
            size: CGSize { width: w as CGFloat, height: h as CGFloat },
        };
        CGContextDrawImage(ctx, rect, img.0);
        CGContextRelease(ctx);
        unpremultiply(&mut buf);
        Ok(Raw {
            rgba: RgbaImage::from_raw(w as u32, h as u32, buf).expect("size"),
            applied: Applied::Crop,
            srgb: true,
        })
    }
}

/// CGBitmapContext 只支援預乘 alpha，轉回一般 RGBA。
fn unpremultiply(buf: &mut [u8]) {
    for p in buf.chunks_exact_mut(4) {
        let a = p[3] as u32;
        if a != 0 && a != 255 {
            for c in &mut p[..3] {
                *c = ((*c as u32 * 255 + a / 2) / a).min(255) as u8;
            }
        }
    }
}
