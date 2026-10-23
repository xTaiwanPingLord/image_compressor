//! Android：NDK AImageDecoder（API 30+）。以 dlopen 載入，舊版 Android 只是不支援 HEIC。

use super::{Applied, Raw, unsupported};
use crate::Result;
use image::RgbaImage;
use libloading::Library;
use std::ffi::c_void;
use std::sync::OnceLock;

type Dec = c_void;
type Hdr = c_void;

const SUCCESS: i32 = 0;
const FORMAT_RGBA_8888: i32 = 1;
const DATASPACE_SRGB: i32 = 142671872;

struct Api {
    _lib: Library,
    create: unsafe extern "C" fn(*const c_void, usize, *mut *mut Dec) -> i32,
    header: unsafe extern "C" fn(*const Dec) -> *const Hdr,
    width: unsafe extern "C" fn(*const Hdr) -> i32,
    height: unsafe extern "C" fn(*const Hdr) -> i32,
    set_format: unsafe extern "C" fn(*mut Dec, i32) -> i32,
    set_unpremul: unsafe extern "C" fn(*mut Dec, bool) -> i32,
    set_dataspace: unsafe extern "C" fn(*mut Dec, i32) -> i32,
    decode: unsafe extern "C" fn(*mut Dec, *mut c_void, usize, usize) -> i32,
    delete: unsafe extern "C" fn(*mut Dec),
}

fn load() -> Option<Api> {
    unsafe {
        let lib = Library::new("libjnigraphics.so").ok()?;
        macro_rules! sym {
            ($n:literal) => {
                *lib.get($n).ok()?
            };
        }
        Some(Api {
            create: sym!(b"AImageDecoder_createFromBuffer\0"),
            header: sym!(b"AImageDecoder_getHeaderInfo\0"),
            width: sym!(b"AImageDecoderHeaderInfo_getWidth\0"),
            height: sym!(b"AImageDecoderHeaderInfo_getHeight\0"),
            set_format: sym!(b"AImageDecoder_setAndroidBitmapFormat\0"),
            set_unpremul: sym!(b"AImageDecoder_setUnpremultipliedRequired\0"),
            set_dataspace: sym!(b"AImageDecoder_setDataSpace\0"),
            decode: sym!(b"AImageDecoder_decodeImage\0"),
            delete: sym!(b"AImageDecoder_delete\0"),
            _lib: lib,
        })
    }
}

fn api() -> Option<&'static Api> {
    static API: OnceLock<Option<Api>> = OnceLock::new();
    API.get_or_init(load).as_ref()
}

pub fn supported() -> bool {
    api().is_some() && super::self_check()
}

pub fn decode(data: &[u8]) -> Result<Raw> {
    let a = api().ok_or_else(unsupported)?;
    unsafe {
        let mut d: *mut Dec = std::ptr::null_mut();
        let rc = (a.create)(data.as_ptr().cast(), data.len(), &mut d);
        if rc != SUCCESS || d.is_null() {
            // -4 = ANDROID_IMAGE_DECODER_UNSUPPORTED_FORMAT（裝置沒有 HEIF 解碼器）
            return Err(if rc == -4 {
                unsupported()
            } else {
                super::derr(format!("AImageDecoder create: {rc}"))
            });
        }
        struct G<'a>(&'a Api, *mut Dec);
        impl Drop for G<'_> {
            fn drop(&mut self) {
                unsafe { (self.0.delete)(self.1) }
            }
        }
        let _g = G(a, d);
        let h = (a.header)(d);
        let (w, ht) = ((a.width)(h), (a.height)(h));
        if w <= 0 || ht <= 0 {
            return Err(super::derr("AImageDecoder: empty image"));
        }
        for (rc, what) in [
            ((a.set_format)(d, FORMAT_RGBA_8888), "format"),
            ((a.set_unpremul)(d, true), "unpremultiplied"),
            ((a.set_dataspace)(d, DATASPACE_SRGB), "dataspace"),
        ] {
            if rc != SUCCESS {
                return Err(super::derr(format!("AImageDecoder {what}: {rc}")));
            }
        }
        let (w, ht) = (w as usize, ht as usize);
        let stride = w * 4;
        let mut buf = vec![0u8; stride * ht];
        let rc = (a.decode)(d, buf.as_mut_ptr().cast(), stride, buf.len());
        if rc != SUCCESS {
            return Err(super::derr(format!("AImageDecoder decode: {rc}")));
        }
        Ok(Raw {
            rgba: RgbaImage::from_raw(w as u32, ht as u32, buf).expect("size"),
            applied: Applied::All,
            srgb: true,
        })
    }
}
