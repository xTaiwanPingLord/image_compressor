#include "flutter_window.h"

#include <commctrl.h>
#include <uiautomation.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Flutter's Windows AccessibilityBridge can dereference a null parent and crash
// (flutter_windows.dll, AccessibilityBridge::CreateRemoveReparentedNodesUpdate;
// see flutter/flutter#182444). The engine only enables semantics when the view
// receives WM_GETOBJECT for UIA / MSAA (screen readers, IMEs, PowerToys, ...),
// so we answer those queries ourselves and the bridge is never created.
// Trade-off: screen readers can't read this app on Windows.
constexpr UINT_PTR kNoA11ySubclassId = 0x494D4743;  // 'IMGC'

LRESULT CALLBACK NoAccessibilityProc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam, UINT_PTR id, DWORD_PTR) {
  if (message == WM_GETOBJECT) {
    const DWORD obj_id = static_cast<DWORD>(static_cast<DWORD_PTR>(lparam));
    if (obj_id == static_cast<DWORD>(UiaRootObjectId) ||
        obj_id == static_cast<DWORD>(OBJID_CLIENT)) {
      return DefWindowProc(hwnd, message, wparam, lparam);
    }
  } else if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(hwnd, NoAccessibilityProc, id);
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  HWND view_hwnd = flutter_controller_->view()->GetNativeWindow();
  SetWindowSubclass(view_hwnd, NoAccessibilityProc, kNoA11ySubclassId, 0);
  SetChildContent(view_hwnd);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
