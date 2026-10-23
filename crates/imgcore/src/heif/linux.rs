//! Linux：執行時載入系統 libheif（不需編譯期相依；沒安裝就回報不支援）。

use super::{Applied, Raw, unsupported};
use crate::Result;
use image::RgbaImage;
use libloading::{Library, Symbol};
use std::ffi::{CStr, c_char, c_int, c_void};
use std::sync::OnceLock;

#[repr(C)]
struct HeifError {
    code: c_int,
    subcode: c_int,
    message: *const c_char,
}

type Ctx = c_void;
type Handle = c_void;
type Image = c_void;

const COLORSPACE_RGB: c_int = 1;
const CHROMA_RGBA: c_int = 11;
const CHANNEL_INTERLEAVED: c_int = 10;

struct Api {
    _lib: Library,
    ctx_alloc: unsafe extern "C" fn() -> *mut Ctx,
    ctx_free: unsafe extern "C" fn(*mut Ctx),
    read_mem: unsafe extern "C" fn(*mut Ctx, *const c_void, usize, *const c_void) -> HeifError,
    primary: unsafe extern "C" fn(*mut Ctx, *mut *mut Handle) -> HeifError,
    handle_release: unsafe extern "C" fn(*const Handle),
    decode: unsafe extern "C" fn(*const Handle, *mut *mut Image, c_int, c_int, *const c_void) -> HeifError,
    image_release: unsafe extern "C" fn(*const Image),
    width: unsafe extern "C" fn(*const Image, c_int) -> c_int,
    height: unsafe extern "C" fn(*const Image, c_int) -> c_int,
    plane: unsafe extern "C" fn(*const Image, c_int, *mut c_int) -> *const u8,
    has_hevc: bool,
}

fn load() -> Option<Api> {
    unsafe {
        let lib = ["libheif.so.1", "libheif.so"]
            .iter()
            .find_map(|n| Library::new(n).ok())?;
        macro_rules! sym {
            ($n:literal) => {{
                let s: Symbol<_> = lib.get($n).ok()?;
                *s
            }};
        }
        let api = Api {
            ctx_alloc: sym!(b"heif_context_alloc\0"),
            ctx_free: sym!(b"heif_context_free\0"),
            read_mem: sym!(b"heif_context_read_from_memory_without_copy\0"),
            primary: sym!(b"heif_context_get_primary_image_handle\0"),
            handle_release: sym!(b"heif_image_handle_release\0"),
            decode: sym!(b"heif_decode_image\0"),
            image_release: sym!(b"heif_image_release\0"),
            width: sym!(b"heif_image_get_width\0"),
            height: sym!(b"heif_image_get_height\0"),
            plane: sym!(b"heif_image_get_plane_readonly\0"),
            has_hevc: false,
            _lib: lib,
        };
        // 確認有 HEVC 解碼外掛（libheif-plugin-libde265 / ffmpeg）
        let have: Option<Symbol<unsafe extern "C" fn(c_int) -> c_int>> =
            api._lib.get(b"heif_have_decoder_for_format\0").ok();
        let has_hevc = match have {
            Some(f) => {
                // libheif 1.13+ 需先初始化外掛
                if let Ok(init) = api._lib.get::<unsafe extern "C" fn(*mut c_void) -> HeifError>(b"heif_init\0") {
                    init(std::ptr::null_mut());
                }
                f(1) != 0 // heif_compression_HEVC = 1
            }
            None => true,
        };
        Some(Api { has_hevc, ..api })
    }
}

fn api() -> Option<&'static Api> {
    static API: OnceLock<Option<Api>> = OnceLock::new();
    API.get_or_init(load).as_ref().filter(|a| a.has_hevc)
}

pub fn supported() -> bool {
    api().is_some()
}

fn check(e: HeifError) -> Result<()> {
    if e.code == 0 {
        return Ok(());
    }
    let msg = if e.message.is_null() {
        format!("libheif error {}/{}", e.code, e.subcode)
    } else {
        unsafe { CStr::from_ptr(e.message) }.to_string_lossy().into_owned()
    };
    Err(super::derr(msg))
}

pub fn decode(data: &[u8]) -> Result<Raw> {
    let a = api().ok_or_else(unsupported)?;
    unsafe {
        let ctx = (a.ctx_alloc)();
        struct Guard<'a>(&'a Api, *mut Ctx, *mut Handle, *mut Image);
        impl Drop for Guard<'_> {
            fn drop(&mut self) {
                unsafe {
                    if !self.3.is_null() {
                        (self.0.image_release)(self.3);
                    }
                    if !self.2.is_null() {
                        (self.0.handle_release)(self.2);
                    }
                    (self.0.ctx_free)(self.1);
                }
            }
        }
        let mut g = Guard(a, ctx, std::ptr::null_mut(), std::ptr::null_mut());
        check((a.read_mem)(ctx, data.as_ptr().cast(), data.len(), std::ptr::null()))?;
        check((a.primary)(ctx, &mut g.2))?;
        check((a.decode)(g.2, &mut g.3, COLORSPACE_RGB, CHROMA_RGBA, std::ptr::null()))?;
        let w = (a.width)(g.3, CHANNEL_INTERLEAVED);
        let h = (a.height)(g.3, CHANNEL_INTERLEAVED);
        let mut stride: c_int = 0;
        let p = (a.plane)(g.3, CHANNEL_INTERLEAVED, &mut stride);
        if p.is_null() || w <= 0 || h <= 0 || stride < w * 4 {
            return Err(super::derr("libheif: empty image"));
        }
        let (w, h, stride) = (w as usize, h as usize, stride as usize);
        let src = std::slice::from_raw_parts(p, stride * (h - 1) + w * 4);
        let mut buf = Vec::with_capacity(w * h * 4);
        for y in 0..h {
            buf.extend_from_slice(&src[y * stride..y * stride + w * 4]);
        }
        let rgba = RgbaImage::from_raw(w as u32, h as u32, buf).expect("size");
        Ok(Raw {
            rgba,
            applied: Applied::All,
            srgb: false,
        })
    }
}
