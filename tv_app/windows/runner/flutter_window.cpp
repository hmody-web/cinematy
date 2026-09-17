#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "cinematy/window",
      &flutter::StandardMethodCodec::GetInstance());

  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "setFullscreen") {
          SetBorderlessFullscreen();
          result->Success();
          return;
        }
        if (call.method_name() == "setWindowedBorderless") {
          SetBorderlessWindowed();
          result->Success();
          return;
        }
        result->NotImplemented();
      });

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
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetBorderlessFullscreen() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }

  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(monitor, &info)) {
    return;
  }

  SetWindowLongPtr(hwnd, GWL_STYLE, WS_POPUP | WS_VISIBLE);
  LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  ex_style &= ~(WS_EX_CLIENTEDGE | WS_EX_WINDOWEDGE | WS_EX_DLGMODALFRAME);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);

  const RECT& r = info.rcMonitor;
  SetWindowPos(hwnd, HWND_TOP, r.left, r.top, r.right - r.left,
               r.bottom - r.top,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOOWNERZORDER);
  ShowWindow(hwnd, SW_SHOW);
  UpdateWindow(hwnd);
  SetForegroundWindow(hwnd);
  SetFocus(hwnd);
}

void FlutterWindow::SetBorderlessWindowed() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }

  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(monitor, &info)) {
    return;
  }

  SetWindowLongPtr(hwnd, GWL_STYLE, WS_POPUP | WS_VISIBLE);
  LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  ex_style &= ~(WS_EX_CLIENTEDGE | WS_EX_WINDOWEDGE | WS_EX_DLGMODALFRAME);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);

  const RECT& work = info.rcWork;
  const int available_width = work.right - work.left;
  const int available_height = work.bottom - work.top;

  // About half the screen area while preserving Cinematy's widescreen layout.
  const int width = static_cast<int>(available_width * 0.72);
  const int height = static_cast<int>(available_height * 0.72);
  const int x = work.left + (available_width - width) / 2;
  const int y = work.top + (available_height - height) / 2;

  SetWindowPos(hwnd, HWND_TOP, x, y, width, height,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOOWNERZORDER);
  ShowWindow(hwnd, SW_SHOW);
  UpdateWindow(hwnd);
  SetForegroundWindow(hwnd);
  SetFocus(hwnd);
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
