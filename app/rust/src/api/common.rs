//! 跨模式共用的型別：結構化警告與錯誤（由 UI 翻譯）。

use imgcore::warn::Warn;

/// 警告：code 見 imgcore::warn::Warn::code，args 依 code 固定順序。
pub struct WarningInfo {
    pub code: String,
    pub args: Vec<i64>,
}

impl From<&Warn> for WarningInfo {
    fn from(w: &Warn) -> Self {
        Self {
            code: w.code().into(),
            args: w.args(),
        }
    }
}

pub(crate) fn warnings(v: &[Warn]) -> Vec<WarningInfo> {
    v.iter().map(Into::into).collect()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ErrorKind {
    Io,
    Decode,
    Encode,
    Invalid,
    Trash,
    Other,
}

pub struct AppError {
    pub kind: ErrorKind,
    pub detail: String,
}

impl From<&imgcore::ErrorInfo> for AppError {
    fn from(e: &imgcore::ErrorInfo) -> Self {
        let kind = match e.kind {
            imgcore::ErrorKind::Io => ErrorKind::Io,
            imgcore::ErrorKind::Decode => ErrorKind::Decode,
            imgcore::ErrorKind::Encode => ErrorKind::Encode,
            imgcore::ErrorKind::Invalid => ErrorKind::Invalid,
            imgcore::ErrorKind::Trash => ErrorKind::Trash,
        };
        Self {
            kind,
            detail: e.detail.clone(),
        }
    }
}

impl From<&imgcore::Error> for AppError {
    fn from(e: &imgcore::Error) -> Self {
        (&imgcore::ErrorInfo::from(e)).into()
    }
}
