#include "flutter_window.h"

#include <optional>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

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
  flutter::MethodChannel<flutter::EncodableValue> window_channel(
      flutter_controller_->engine()->messenger(), "me_vazo/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel.SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "toggleFullscreen") {
      SetFullscreen(!fullscreen_);
      result->Success();
    } else if (call.method_name() == "exitFullscreen") {
      SetFullscreen(false);
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
  flutter::MethodChannel<flutter::EncodableValue> screen_awake(
      flutter_controller_->engine()->messenger(), "me_vazo/screen_awake",
      &flutter::StandardMethodCodec::GetInstance());
  screen_awake.SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "setEnabled") {
      result->NotImplemented();
      return;
    }
    const auto* enabled = call.arguments()
        ? std::get_if<bool>(call.arguments()) : nullptr;
    if (!enabled) {
      result->Error("invalid_argument", "Expected a boolean");
      return;
    }
    const auto flags = ES_CONTINUOUS |
        (*enabled ? ES_DISPLAY_REQUIRED : 0);
    if (!SetThreadExecutionState(flags)) {
      result->Error("screen_awake_failed", "Could not update display idle policy");
      return;
    }
    result->Success();
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    SetFullscreen(true);
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetFullscreen(bool enabled) {
  if (fullscreen_ == enabled) return;
  HWND window = GetHandle();
  if (enabled) {
    MONITORINFO monitor = {sizeof(MONITORINFO)};
    if (!GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor)) return;
    window_style_ = GetWindowLong(window, GWL_STYLE);
    GetWindowPlacement(window, &window_placement_);
    SetWindowLong(window, GWL_STYLE, window_style_ & ~WS_OVERLAPPEDWINDOW);
    SetWindowPos(window, HWND_TOP, monitor.rcMonitor.left, monitor.rcMonitor.top,
        monitor.rcMonitor.right - monitor.rcMonitor.left,
        monitor.rcMonitor.bottom - monitor.rcMonitor.top, SWP_FRAMECHANGED);
  } else {
    SetWindowLong(window, GWL_STYLE, window_style_);
    SetWindowPlacement(window, &window_placement_);
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  }
  fullscreen_ = enabled;
}

void FlutterWindow::OnDestroy() {
  SetThreadExecutionState(ES_CONTINUOUS);
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
