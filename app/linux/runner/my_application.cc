#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <unistd.h>

#include <cstdlib>
#include <memory>
#include <string>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "autostart_file.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  gboolean background;
  GtkWindow* window;
  FlMethodChannel* lifecycle_channel;
  FlMethodChannel* startup_channel;
  GCancellable* lifecycle_cancellable;
  GDBusConnection* sleep_connection;
  guint sleep_subscription;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// 首帧可以在未映射的窗口内渲染，后台启动不会先显示再隐藏。
static void first_frame_cb(MyApplication* self, FlView* view) {
  if (!self->background) {
    gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  }
}

struct TrayHostCheck {
  FlMethodCall* call;
  GDBusConnection* connection;
  guint watcher_index;
};

static const char* kTrayWatchers[] = {"org.kde.StatusNotifierWatcher",
                                     "com.canonical.StatusNotifierWatcher"};

static void complete_tray_host_check(TrayHostCheck* check, gboolean available) {
  g_autoptr(FlValue) value = fl_value_new_bool(available);
  fl_method_call_respond_success(check->call, value, nullptr);
  g_clear_object(&check->call);
  g_clear_object(&check->connection);
  delete check;
}

static void request_tray_host(TrayHostCheck* check);

static void tray_host_property_cb(GObject* object, GAsyncResult* result,
                                  gpointer data) {
  TrayHostCheck* check = static_cast<TrayHostCheck*>(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(object), result, &error);
  if (reply != nullptr) {
    g_autoptr(GVariant) value = nullptr;
    g_variant_get(reply, "(v)", &value);
    if (g_variant_is_of_type(value, G_VARIANT_TYPE_BOOLEAN) &&
        g_variant_get_boolean(value)) {
      complete_tray_host_check(check, TRUE);
      return;
    }
  }
  check->watcher_index++;
  request_tray_host(check);
}

static void request_tray_host(TrayHostCheck* check) {
  if (check->watcher_index >= G_N_ELEMENTS(kTrayWatchers)) {
    complete_tray_host_check(check, FALSE);
    return;
  }
  const char* watcher = kTrayWatchers[check->watcher_index];
  g_dbus_connection_call(
      check->connection, watcher, "/StatusNotifierWatcher",
      "org.freedesktop.DBus.Properties", "Get",
      g_variant_new("(ss)", watcher, "IsStatusNotifierHostRegistered"),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 1000, nullptr,
      tray_host_property_cb, check);
}

static void tray_host_bus_cb(GObject* object, GAsyncResult* result,
                             gpointer data) {
  TrayHostCheck* check = static_cast<TrayHostCheck*>(data);
  g_autoptr(GError) error = nullptr;
  check->connection = g_bus_get_finish(result, &error);
  if (check->connection == nullptr) {
    complete_tray_host_check(check, FALSE);
    return;
  }
  request_tray_host(check);
}

static void lifecycle_method_cb(FlMethodChannel* channel, FlMethodCall* call,
                                gpointer data) {
  const gchar* method = fl_method_call_get_name(call);
  if (g_strcmp0(method, "trayHostAvailable") == 0) {
    auto* check = new TrayHostCheck{FL_METHOD_CALL(g_object_ref(call)), nullptr, 0};
    g_bus_get(G_BUS_TYPE_SESSION, nullptr, tray_host_bus_cb, check);
  } else if (g_strcmp0(method, "windowReady") == 0) {
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

struct StartupRequest {
  FlMethodCall* call;
  std::string config_home;
  std::string executable;
  bool change;
  bool enabled;
};

static void startup_request_free(gpointer data) {
  auto* request = static_cast<StartupRequest*>(data);
  g_clear_object(&request->call);
  delete request;
}

static void startup_worker(GTask* task, gpointer source, gpointer data,
                           GCancellable* cancellable) {
  if (g_task_return_error_if_cancelled(task)) return;
  auto* request = static_cast<StartupRequest*>(data);
  xduwlan::AutostartFile startup(request->config_home, request->executable);
  auto* result = new xduwlan::StartupResult(request->change
      ? startup.SetEnabled(request->enabled) : startup.IsEnabled());
  g_task_return_pointer(task, result, [](gpointer value) {
    delete static_cast<xduwlan::StartupResult*>(value);
  });
}

static void startup_complete(GObject* source, GAsyncResult* response,
                             gpointer data) {
  GTask* task = G_TASK(response);
  auto* request = static_cast<StartupRequest*>(g_task_get_task_data(task));
  // GTask 数据析构可能在工作线程执行；Flutter 对象由完成回调在主线程释放。
  g_autoptr(FlMethodCall) call = request->call;
  request->call = nullptr;
  g_autoptr(GError) error = nullptr;
  std::unique_ptr<xduwlan::StartupResult> result(
      static_cast<xduwlan::StartupResult*>(g_task_propagate_pointer(task, &error)));
  if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED)) return;
  if (result == nullptr) {
    fl_method_call_respond_error(call, "startup_io_failed", nullptr,
                                nullptr, nullptr);
  } else if (result->error != nullptr) {
    fl_method_call_respond_error(call, result->error, nullptr,
                                nullptr, nullptr);
  } else {
    g_autoptr(FlValue) value = fl_value_new_bool(result->enabled);
    fl_method_call_respond_success(call, value, nullptr);
  }
}

// 路径由宿主读取；文件 I/O 在工作线程执行，不阻塞账号配置和窗口交互。
static void startup_method_cb(FlMethodChannel* channel, FlMethodCall* call,
                              gpointer data) {
  const gchar* method = fl_method_call_get_name(call);
  gboolean change = g_strcmp0(method, "setEnabled") == 0;
  if (!change && g_strcmp0(method, "isEnabled") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* arguments = fl_method_call_get_args(call);
  if (change && (arguments == nullptr ||
                 fl_value_get_type(arguments) != FL_VALUE_TYPE_BOOL)) {
    fl_method_call_respond_error(call, "startup_change_failed", nullptr,
                                nullptr, nullptr);
    return;
  }
  char path[4096];
  ssize_t length = readlink("/proc/self/exe", path, sizeof(path));
  if (length <= 0 || static_cast<size_t>(length) >= sizeof(path)) {
    fl_method_call_respond_error(call, "startup_path_unavailable", nullptr,
                                nullptr, nullptr);
    return;
  }
  const char* xdg = std::getenv("XDG_CONFIG_HOME");
  const char* home = std::getenv("HOME");
  auto* request = new StartupRequest{
      FL_METHOD_CALL(g_object_ref(call)),
      xduwlan::StartupConfigHome(xdg == nullptr ? "" : xdg,
                                 home == nullptr ? "" : home),
      std::string(path, static_cast<size_t>(length)),
      static_cast<bool>(change),
      change ? static_cast<bool>(fl_value_get_bool(arguments)) : false};
  MyApplication* self = MY_APPLICATION(data);
  g_autoptr(GTask) task = g_task_new(nullptr, self->lifecycle_cancellable,
                                   startup_complete, nullptr);
  g_task_set_task_data(task, request, startup_request_free);
  g_task_run_in_thread(task, startup_worker);
}

static void sleep_signal_cb(GDBusConnection* connection, const gchar* sender,
                            const gchar* path, const gchar* interface,
                            const gchar* signal, GVariant* parameters,
                            gpointer data) {
  MyApplication* self = MY_APPLICATION(data);
  gboolean sleeping = FALSE;
  g_variant_get(parameters, "(b)", &sleeping);
  if (self->lifecycle_channel != nullptr) {
    fl_method_channel_invoke_method(self->lifecycle_channel,
                                   sleeping ? "suspend" : "resume", nullptr,
                                   self->lifecycle_cancellable, nullptr, nullptr);
  }
}

static void sleep_bus_cb(GObject* object, GAsyncResult* result, gpointer data) {
  g_autoptr(MyApplication) self = MY_APPLICATION(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) connection = g_bus_get_finish(result, &error);
  if (connection == nullptr ||
      g_cancellable_is_cancelled(self->lifecycle_cancellable)) {
    return;
  }
  self->sleep_connection = G_DBUS_CONNECTION(g_object_ref(connection));
  self->sleep_subscription = g_dbus_connection_signal_subscribe(
      connection, "org.freedesktop.login1", "org.freedesktop.login1.Manager",
      "PrepareForSleep", "/org/freedesktop/login1", nullptr,
      G_DBUS_SIGNAL_FLAGS_NONE, sleep_signal_cb, self, nullptr);
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  // GtkApplication 的 D-Bus 唯一实例再次激活时复用已有窗口和 Dart 引擎。
  if (self->window != nullptr) {
    gtk_window_present(self->window);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  g_object_add_weak_pointer(G_OBJECT(window),
                          reinterpret_cast<gpointer*>(&self->window));

  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) use_header_bar = FALSE;
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "XDUWlan");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "XDUWlan");
  }
  gtk_window_set_default_size(window, 800, 600);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);
  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  gtk_widget_show(GTK_WIDGET(view));
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->lifecycle_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "xduwlan/lifecycle", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->lifecycle_channel,
                                          lifecycle_method_cb, self, nullptr);
  self->startup_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "xduwlan/startup", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->startup_channel,
                                          startup_method_cb, self, nullptr);
  g_bus_get(G_BUS_TYPE_SYSTEM, self->lifecycle_cancellable, sleep_bus_cb,
            g_object_ref(self));

  // 给未映射的视图明确的非零布局，然后 realize 以启动引擎和首帧初始化。
  GtkAllocation allocation = {0, 0, 800, 600};
  gtk_widget_size_allocate(GTK_WIDGET(window), &allocation);
  gtk_widget_realize(GTK_WIDGET(window));
  gtk_widget_size_allocate(GTK_WIDGET(view), &allocation);
  gtk_widget_realize(GTK_WIDGET(view));
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);
  self->background = FALSE;
  for (gchar** argument = self->dart_entrypoint_arguments;
       *argument != nullptr; argument++) {
    if (g_strcmp0(*argument, "--background") == 0) self->background = TRUE;
  }
  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("应用实例注册失败");
    *exit_status = 1;
    return TRUE;
  }
  g_application_activate(application);
  *exit_status = 0;
  return TRUE;
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  if (self->lifecycle_cancellable != nullptr) {
    g_cancellable_cancel(self->lifecycle_cancellable);
  }
  if (self->sleep_connection != nullptr && self->sleep_subscription != 0) {
    g_dbus_connection_signal_unsubscribe(self->sleep_connection,
                                        self->sleep_subscription);
    self->sleep_subscription = 0;
  }
  g_clear_object(&self->sleep_connection);
  if (self->lifecycle_channel != nullptr) {
    fl_method_channel_set_method_call_handler(self->lifecycle_channel, nullptr,
                                            nullptr, nullptr);
  }
  g_clear_object(&self->lifecycle_channel);
  if (self->startup_channel != nullptr) {
    fl_method_channel_set_method_call_handler(self->startup_channel, nullptr,
                                            nullptr, nullptr);
  }
  g_clear_object(&self->startup_channel);
  g_clear_object(&self->lifecycle_cancellable);
  if (self->window != nullptr) {
    g_object_remove_weak_pointer(G_OBJECT(self->window),
                                reinterpret_cast<gpointer*>(&self->window));
    self->window = nullptr;
  }
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->lifecycle_cancellable = g_cancellable_new();
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     static_cast<GApplicationFlags>(0), nullptr));
}
