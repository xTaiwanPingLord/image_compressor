//! JPEG 無損最佳化：直接搬 DCT 係數（不重新解碼），只重做霍夫曼最佳化 / progressive。
//! 等同 jpegtran -optimize -progressive -copy none|all。

use crate::{Error, Result};
use mozjpeg_sys as ffi;
use std::mem;
use std::os::raw::{c_int, c_uint, c_ulong};

const JPEG_APP0: c_int = 0xE0;
const JPEG_COM: c_int = 0xFE;

#[allow(unpredictable_function_pointer_comparisons)]
unsafe fn std_err() -> Box<ffi::jpeg_error_mgr> {
    unsafe {
        let mut err: Box<ffi::jpeg_error_mgr> = Box::new(mem::zeroed());
        ffi::jpeg_std_error(&mut err);
        err.error_exit = Some(error_exit);
        err.emit_message = Some(emit_message);
        err
    }
}

extern "C-unwind" fn error_exit(cinfo: &mut ffi::jpeg_common_struct) {
    let code = unsafe { cinfo.err.as_ref().map(|e| e.msg_code).unwrap_or(-1) };
    std::panic::resume_unwind(Box::new(format!("libjpeg error code {code}")));
}

extern "C-unwind" fn emit_message(_cinfo: &mut ffi::jpeg_common_struct, _level: c_int) {}

/// 無損最佳化 JPEG。`keep_metadata`：保留 EXIF/XMP（APP1）與註解；ICC（APP2）一律保留。
pub fn optimize(data: &[u8], keep_metadata: bool) -> Result<Vec<u8>> {
    std::panic::catch_unwind(|| unsafe { optimize_inner(data, keep_metadata) }).map_err(|e| {
        let msg = e
            .downcast_ref::<String>()
            .cloned()
            .unwrap_or_else(|| "libjpeg panic".into());
        Error::Encode(msg)
    })
}

unsafe fn optimize_inner(data: &[u8], keep_metadata: bool) -> Vec<u8> {
    unsafe {
        let mut derr = std_err();
        let mut cerr = std_err();
        let mut d: Box<ffi::jpeg_decompress_struct> = Box::new(mem::zeroed());
        d.common.err = &mut *derr;
        ffi::jpeg_create_decompress(&mut *d);

        struct Guard<'a> {
            d: &'a mut ffi::jpeg_decompress_struct,
        }
        impl Drop for Guard<'_> {
            fn drop(&mut self) {
                unsafe { ffi::jpeg_destroy_decompress(self.d) }
            }
        }
        let g = Guard { d: &mut d };
        let d = &mut *g.d;

        ffi::jpeg_mem_src(d, data.as_ptr(), data.len() as c_ulong);
        // ICC 一律保留；其他 APPn / COM 依設定
        ffi::jpeg_save_markers(d, JPEG_APP0 + 2, 0xFFFF);
        if keep_metadata {
            ffi::jpeg_save_markers(d, JPEG_APP0 + 1, 0xFFFF);
            ffi::jpeg_save_markers(d, JPEG_COM, 0xFFFF);
        }
        ffi::jpeg_read_header(d, 1);
        let coefs = ffi::jpeg_read_coefficients(d);

        let mut c: Box<ffi::jpeg_compress_struct> = Box::new(mem::zeroed());
        c.common.err = &mut *cerr;
        ffi::jpeg_create_compress(&mut *c);
        struct CGuard<'a> {
            c: &'a mut ffi::jpeg_compress_struct,
        }
        impl Drop for CGuard<'_> {
            fn drop(&mut self) {
                unsafe { ffi::jpeg_destroy_compress(self.c) }
            }
        }
        let cg = CGuard { c: &mut c };
        let c = &mut *cg.c;

        ffi::jpeg_copy_critical_parameters(d, c);
        c.optimize_coding = 1;
        ffi::jpeg_simple_progression(c);

        let mut out_ptr: *mut u8 = std::ptr::null_mut();
        let mut out_len: c_ulong = 0;
        ffi::jpeg_mem_dest(c, &mut out_ptr, &mut out_len);
        ffi::jpeg_write_coefficients(c, coefs);

        let mut m = d.marker_list;
        while !m.is_null() {
            let mk = &*m;
            ffi::jpeg_write_marker(c, mk.marker as c_int, mk.data, mk.data_length as c_uint);
            m = mk.next;
        }

        ffi::jpeg_finish_compress(c);
        ffi::jpeg_finish_decompress(d);
        let out = std::slice::from_raw_parts(out_ptr, out_len as usize).to_vec();
        libc::free(out_ptr as *mut libc::c_void);
        drop(cg);
        drop(g);
        drop(cerr);
        drop(derr);
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::encode::{Mode, encode_jpeg};
    use image::{Rgb, RgbImage};

    #[test]
    fn lossless_keeps_pixels() {
        let img = RgbImage::from_fn(320, 240, |x, y| {
            Rgb([(x % 256) as u8, (y % 256) as u8, ((x + y) % 256) as u8])
        });
        // 用 libjpeg 預設（非最佳化）產生來源
        let src = encode_jpeg(&img, 90, Mode::Chroma444Plain).unwrap();
        let out = optimize(&src, false).unwrap();
        assert!(out.len() < src.len(), "{} vs {}", out.len(), src.len());
        let a = image::load_from_memory(&src).unwrap().to_rgb8();
        let b = image::load_from_memory(&out).unwrap().to_rgb8();
        assert_eq!(a.as_raw(), b.as_raw());
    }

    #[test]
    fn garbage_is_error_not_crash() {
        assert!(optimize(b"not a jpeg", false).is_err());
    }
}
