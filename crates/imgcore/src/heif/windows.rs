//! Windows：WIC 的 HEIF 解碼器（需「HEIF 影像擴充功能」＋「HEVC 視訊擴充功能」）。

use super::{Applied, Raw, unsupported};
use crate::Result;
use image::RgbaImage;
use windows::Win32::Graphics::Imaging::{
    CLSID_WICImagingFactory, GUID_WICPixelFormat32bppRGBA, IWICImagingFactory,
    WICBitmapDitherTypeNone, WICBitmapPaletteTypeCustom, WICDecodeMetadataCacheOnDemand,
};
use windows::Win32::System::Com::{
    CLSCTX_INPROC_SERVER, COINIT_MULTITHREADED, CoCreateInstance, CoInitializeEx, CoUninitialize,
};
use windows::core::HRESULT;

/// 缺少解碼元件時常見的錯誤碼
const NOT_INSTALLED: &[u32] = &[
    0x88982F50, // WINCODEC_ERR_COMPONENTNOTFOUND
    0x88982F8B, // WINCODEC_ERR_UNSUPPORTEDOPERATION
    0xC00D5212, // MF_E_TOPO_CODEC_NOT_FOUND
    0xC00D36B4, // MF_E_INVALIDMEDIATYPE
    0x80040154, // REGDB_E_CLASSNOTREG
];

fn map(e: windows::core::Error) -> crate::Error {
    let code = e.code().0 as u32;
    if NOT_INSTALLED.contains(&code) {
        unsupported()
    } else {
        super::derr(format!("WIC 0x{code:08X}: {}", e.message()))
    }
}

pub fn supported() -> bool {
    super::self_check()
}

pub fn decode(data: &[u8]) -> Result<Raw> {
    unsafe {
        // rayon 執行緒可能尚未初始化 COM；已初始化時回傳 S_FALSE，模式不同時回傳錯誤（仍可使用）
        let hr: HRESULT = CoInitializeEx(None, COINIT_MULTITHREADED);
        let res = decode_inner(data);
        if hr.is_ok() {
            CoUninitialize();
        }
        res
    }
}

unsafe fn decode_inner(data: &[u8]) -> Result<Raw> {
    unsafe {
        let f: IWICImagingFactory =
            CoCreateInstance(&CLSID_WICImagingFactory, None, CLSCTX_INPROC_SERVER).map_err(map)?;
        let stream = f.CreateStream().map_err(map)?;
        stream.InitializeFromMemory(data).map_err(map)?;
        let dec = f
            .CreateDecoderFromStream(&stream, std::ptr::null(), WICDecodeMetadataCacheOnDemand)
            .map_err(map)?;
        let frame = dec.GetFrame(0).map_err(map)?;
        let conv = f.CreateFormatConverter().map_err(map)?;
        conv.Initialize(
            &frame,
            &GUID_WICPixelFormat32bppRGBA,
            WICBitmapDitherTypeNone,
            None,
            0.0,
            WICBitmapPaletteTypeCustom,
        )
        .map_err(map)?;
        let (mut w, mut h) = (0u32, 0u32);
        conv.GetSize(&mut w, &mut h).map_err(map)?;
        if w == 0 || h == 0 {
            return Err(super::derr("WIC: empty image"));
        }
        let mut buf = vec![0u8; w as usize * h as usize * 4];
        conv.CopyPixels(std::ptr::null(), w * 4, &mut buf).map_err(map)?;
        Ok(Raw {
            rgba: RgbaImage::from_raw(w, h, buf).expect("size"),
            // 實測（heif_check）：WIC 會套用 clap 與 irot，但不套用 imir
            applied: Applied::CropRotate,
            srgb: false,
        })
    }
}
