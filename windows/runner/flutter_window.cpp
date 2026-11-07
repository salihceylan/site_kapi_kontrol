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

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "site_kapi_kontrol/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setFullscreen") {
          bool target = true;
          if (const auto* b = std::get_if<bool>(call.arguments())) {
            target = *b;
          } else if (const auto* m =
                         std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto it = m->find(flutter::EncodableValue("fullscreen"));
            if (it != m->end()) {
              if (const auto* mb = std::get_if<bool>(&it->second)) {
                target = *mb;
              }
            }
          }
          SetFullscreen(target);
          result->Success(flutter::EncodableValue(is_fullscreen_));
        } else if (call.method_name() == "isFullscreen") {
          result->Success(flutter::EncodableValue(is_fullscreen_));
        } else {
          result->NotImplemented();
        }
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

void FlutterWindow::SetFullscreen(bool fullscreen) {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  if (fullscreen && !is_fullscreen_) {
    saved_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
    saved_ex_style_ = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    saved_placement_.length = sizeof(WINDOWPLACEMENT);
    GetWindowPlacement(hwnd, &saved_placement_);

    MONITORINFO mi{sizeof(MONITORINFO)};
    if (GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                       &mi)) {
      SetWindowLongPtr(hwnd, GWL_STYLE,
                       saved_style_ & ~(WS_CAPTION | WS_THICKFRAME));
      SetWindowLongPtr(hwnd, GWL_EXSTYLE,
                       saved_ex_style_ &
                           ~(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE |
                             WS_EX_CLIENTEDGE | WS_EX_STATICEDGE));
      SetWindowPos(hwnd, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top,
                   mi.rcMonitor.right - mi.rcMonitor.left,
                   mi.rcMonitor.bottom - mi.rcMonitor.top,
                   SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
      is_fullscreen_ = true;
    }
  } else if (!fullscreen && is_fullscreen_) {
    SetWindowLongPtr(hwnd, GWL_STYLE, saved_style_);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, saved_ex_style_);
    SetWindowPlacement(hwnd, &saved_placement_);
    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                     SWP_FRAMECHANGED);
    is_fullscreen_ = false;
  }
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
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
