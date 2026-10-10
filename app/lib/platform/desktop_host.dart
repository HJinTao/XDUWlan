import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import '../application/desktop_host.dart';
import '../core/domain.dart';
import '../core/presentation.dart';

/// 插件及原生生命周期的边界；构造只保存依赖，首帧后才访问平台能力。
class PluginDesktopHost with WindowListener implements DesktopHost {
  PluginDesktopHost({
    LaunchAtStartup? startup,
    TargetPlatform? targetPlatform,
    this.executable,
  }) : _startupOverride = startup,
       _platform = targetPlatform ?? defaultTargetPlatform;

  static const _lifecycle = MethodChannel('xduwlan/lifecycle');
  static const _linuxStartup = MethodChannel('xduwlan/startup');
  final LaunchAtStartup? _startupOverride;
  final TargetPlatform _platform;
  final String? executable;
  LaunchAtStartup get _startup => _startupOverride ?? launchAtStartup;
  bool _closed = false;
  bool _windowListening = false;
  bool _notificationsReady = false;
  void Function()? _onClose;
  tray.TrayIcon? _trayIcon;
  tray.Image? _trayImage;
  tray.Menu? _menu;
  tray.MenuItem? _statusItem;
  final Map<TrayAction, tray.MenuItem> _items = {};
  final Map<TrayAction, tray.ListenerId> _itemListeners = {};
  tray.ListenerId? _trayListener;
  LocalNotification? _notification;
  String? _trayAdvice;

  @override
  String? get trayAdvice => _trayAdvice;

  @override
  Future<void> initializeWindow({
    required bool background,
    required void Function() onClose,
    required void Function() onSuspend,
    required void Function() onResume,
  }) async {
    if (_closed) return;
    _onClose = onClose;
    _lifecycle.setMethodCallHandler((call) async {
      if (_closed) return;
      if (call.method == 'suspend') onSuspend();
      if (call.method == 'resume') onResume();
    });
    await windowManager.ensureInitialized();
    if (_closed) return;
    if (!_windowListening) {
      windowManager.addListener(this);
      _windowListening = true;
    }
    await windowManager.setPreventClose(true);
    if (_closed) return;
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(title: 'XDUWlan', minimumSize: Size(640, 480)),
    );
    if (_closed) return;
    await _lifecycle.invokeMethod<void>('windowReady');
    if (_closed) return;
    if (background) {
      await hideWindow();
    } else {
      await showWindow();
    }
  }

  @override
  void onWindowClose() {
    if (!_closed) _onClose?.call();
  }

  @override
  Future<void> initializeTray(void Function(TrayAction) onAction) async {
    if (_closed || _trayIcon != null) return;
    try {
      if (_platform == TargetPlatform.linux &&
          await _lifecycle.invokeMethod<bool>('trayHostAvailable') != true) {
        _trayAdvice = '系统托盘不可用。GNOME 用户可启用 AppIndicator 扩展后重启应用。';
        throw PlatformException(code: 'tray_host_unavailable');
      }
      if (_closed) return;
      if (!tray.TrayManager.instance.isSupported()) {
        throw PlatformException(code: 'tray_unavailable');
      }
      _trayIcon = tray.TrayIcon.createWithIdentifier('cn.xduwlan.desktop');
      _trayImage = tray.Image.fromBase64(_trayImagePng);
      _menu = tray.Menu.create();
      if (_trayIcon == null || _trayImage == null || _menu == null) {
        throw PlatformException(code: 'tray_unavailable');
      }
      _trayIcon!.icon = _trayImage;
      _trayIcon!.isIconTemplate = _platform == TargetPlatform.macOS;
      _trayIcon!.setTooltip('XDUWlan');
      _statusItem = tray.MenuItem.createWithLabelAndType(
        '状态：初始化中',
        tray.MenuItemType.normal,
      );
      if (_statusItem == null) {
        throw PlatformException(code: 'tray_unavailable');
      }
      _statusItem!.isEnabled = false;
      _menu!.addItem(_statusItem);
      const labels = {
        TrayAction.show: '显示主窗口',
        TrayAction.check: '立即检查',
        TrayAction.authenticate: '立即认证',
        TrayAction.configure: '配置账号',
        TrayAction.automaticRecovery: '自动恢复',
        TrayAction.launchAtStartup: '登录系统后启动',
        TrayAction.exit: '退出',
      };
      for (final entry in labels.entries) {
        final checkbox =
            entry.key == TrayAction.automaticRecovery ||
            entry.key == TrayAction.launchAtStartup;
        final item = tray.MenuItem.createWithLabelAndType(
          entry.value,
          checkbox ? tray.MenuItemType.checkbox : tray.MenuItemType.normal,
        );
        if (item == null) {
          throw PlatformException(code: 'tray_unavailable');
        }
        _items[entry.key] = item;
        if (checkbox) item.isEnabled = false;
        _itemListeners[entry.key] = item.addListener((event) {
          if (!_closed && event is tray.MenuItemClickedEvent) {
            onAction(entry.key);
          }
        });
        _menu!.addItem(item);
      }
      _trayListener = _trayIcon!.addListener((event) {
        if (!_closed && event is tray.TrayIconDoubleClickedEvent) {
          onAction(TrayAction.show);
        }
      });
      _trayIcon!.setContextMenu(_menu);
      _trayIcon!.setContextMenuTrigger(tray.ContextMenuTrigger.rightClicked);
      if (!_trayIcon!.setVisible(true)) {
        throw PlatformException(code: 'tray_unavailable');
      }
    } catch (_) {
      await disposeTray();
      _trayAdvice ??= '系统托盘不可用，关闭窗口将退出应用。';
      throw PlatformException(code: 'tray_unavailable');
    }
  }

  @override
  Future<void> updateTray(TrayState state) async {
    if (_closed || _trayIcon == null) return;
    _statusItem!.label = '状态：${state.status}';
    _trayIcon!.setTooltip('XDUWlan · ${state.status}');
    final automatic = _items[TrayAction.automaticRecovery]!;
    automatic.state = state.automaticRecovery
        ? tray.MenuItemState.checked
        : tray.MenuItemState.unchecked;
    automatic.isEnabled = state.settingsReady;
    final startup = _items[TrayAction.launchAtStartup]!;
    startup.state = state.launchAtStartup
        ? tray.MenuItemState.checked
        : tray.MenuItemState.unchecked;
    startup.isEnabled = state.startupReady;
  }

  @override
  Future<void> initializeNotifications() async {
    if (_closed) return;
    await localNotifier.setup(appName: 'XDUWlan');
    if (!_closed) _notificationsReady = true;
  }

  @override
  Future<void> notifyAuthentication(OperationReport report) async {
    if (_closed ||
        !_notificationsReady ||
        report.kind != OperationKind.authenticate ||
        report.outcome == RecoveryOutcome.cancelled) {
      return;
    }
    final notification = _notification ??= LocalNotification(
      identifier: 'xduwlan.authentication',
      title: 'XDUWlan',
    );
    notification.body = switch (report.outcome) {
      RecoveryOutcome.restored => '校园网认证成功。',
      RecoveryOutcome.alreadyOnline => networkMessage(report.network),
      _ =>
        report.failure == null
            ? '校园网认证未完成，请打开应用查看安全提示。'
            : failureMessage(report.failure!),
    };
    notification.onClick = () {
      unawaited(showWindow().catchError((Object _) {}));
    };
    await notification.show();
  }

  @override
  Future<bool> initializeStartup() async {
    if (_closed) throw PlatformException(code: 'desktop_closed');
    if (_platform == TargetPlatform.linux) {
      return _invokeLinuxStartup('isEnabled');
    }
    final appExecutable = executable ?? Platform.resolvedExecutable;
    _startup.setup(
      appName: 'XDUWlan',
      appPath: _quoteExecutable(appExecutable),
      args: const ['--background'],
    );
    return _startup.isEnabled();
  }

  String _quoteExecutable(String value) {
    if (value.isEmpty || value.contains(RegExp(r'[\x00-\x1f]'))) {
      throw PlatformException(code: 'startup_path_unavailable');
    }
    if (_platform == TargetPlatform.windows) {
      if (value.contains('"')) {
        throw PlatformException(code: 'startup_path_unavailable');
      }
      return '"$value"';
    }
    return value;
  }

  Future<bool> _invokeLinuxStartup(String method, [bool? enabled]) async {
    try {
      final actual = await _linuxStartup.invokeMethod<bool>(method, enabled);
      if (actual == null) {
        throw PlatformException(code: 'startup_change_failed');
      }
      return actual;
    } on PlatformException catch (error) {
      const safeCodes = {
        'startup_path_unavailable',
        'startup_unexpected_entry',
        'startup_permission_denied',
        'startup_io_failed',
        'startup_conflict',
        'startup_change_failed',
      };
      throw PlatformException(
        code: safeCodes.contains(error.code)
            ? error.code
            : 'startup_change_failed',
      );
    } catch (_) {
      throw PlatformException(code: 'startup_change_failed');
    }
  }

  @override
  Future<bool> setLaunchAtStartup(bool enabled) async {
    if (_closed) throw PlatformException(code: 'desktop_closed');
    if (_platform == TargetPlatform.linux) {
      final changed = await _invokeLinuxStartup('setEnabled', enabled);
      final actual = await _invokeLinuxStartup('isEnabled');
      if (changed != enabled || actual != enabled) {
        throw PlatformException(code: 'startup_change_failed');
      }
      return actual;
    }
    final changed = enabled
        ? await _startup.enable()
        : await _startup.disable();
    final actual = await _startup.isEnabled();
    if (!changed || actual != enabled) {
      throw PlatformException(code: 'startup_change_failed');
    }
    return actual;
  }

  @override
  Future<void> showWindow() async {
    if (_closed) return;
    await windowManager.show();
    if (!_closed) await windowManager.focus();
  }

  @override
  Future<void> hideWindow() async {
    if (!_closed) await windowManager.hide();
  }

  @override
  Future<void> disposeTray() async {
    final icon = _trayIcon;
    _trayIcon = null;
    if (icon != null) {
      if (_trayListener != null) icon.removeListener(_trayListener!);
      icon.setVisible(false);
      icon.setContextMenu(null);
      icon.dispose();
    }
    _trayListener = null;
    for (final entry in _items.entries) {
      final listener = _itemListeners[entry.key];
      if (listener != null) entry.value.removeListener(listener);
    }
    _menu?.clear();
    _menu?.dispose();
    _menu = null;
    for (final item in _items.values) {
      item.dispose();
    }
    _items.clear();
    _itemListeners.clear();
    _statusItem?.dispose();
    _statusItem = null;
    _trayImage?.dispose();
    _trayImage = null;
  }

  @override
  Future<void> exit() async {
    if (_closed) return;
    _closed = true;
    _notificationsReady = false;
    _onClose = null;
    _lifecycle.setMethodCallHandler(null);
    if (_windowListening) {
      windowManager.removeListener(this);
      _windowListening = false;
    }
    await disposeTray();
    final notification = _notification;
    _notification = null;
    if (notification != null) {
      try {
        await notification.destroy();
      } catch (_) {
        // 通知服务不可用时仍须释放 Dart listener，并继续退出窗口。
        localNotifier.removeListener(notification);
      }
    }
    if (_platform == TargetPlatform.macOS) {
      await _lifecycle.invokeMethod<void>('terminate');
    } else {
      await windowManager.destroy();
    }
  }
}

// 内嵌透明 Wi-Fi 图标，避免依赖工作目录或首帧前的磁盘读取。
const _trayImagePng =
    'iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAUklEQVR4nGNgGAUUgP8kYpoZTLRFlLiKoF6yvUuMOdQwGJ9FcAFiXERKuJMcH1RLSaRqItkScuOD2vFIPUC1HEyO4VSzhBy5EQioGu7D04IRCgDq/nmHoTl1wAAAAABJRU5ErkJggg==';
