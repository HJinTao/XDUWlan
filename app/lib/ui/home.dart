import 'package:flutter/material.dart';

import '../application/recovery_controller.dart';
import '../core/domain.dart';

const _canvas = Color(0xFFF8F9F6);
const _blue = Color(0xFF3867B0);
const _ink = Color(0xFF22324A);
const _muted = Color(0xFF657185);

/// 主界面只展示安全结果，探测与凭据访问由控制器按需执行。
class XduwlanHome extends StatelessWidget {
  const XduwlanHome({super.key, required this.controller});

  final RecoveryController controller;

  Future<void> _configure(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AccountDialog(controller: controller),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('账号已保存至本机配置文件')));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6EDF8),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.wifi_rounded, color: _blue),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'XDUWlan',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: _ink,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '西电校园网',
                              style: TextStyle(color: _muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _NetworkCard(controller: controller),
                  if (controller.failure case final failure?) ...[
                    const SizedBox(height: 14),
                    _FailureNotice(failure: failure),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: controller.busy ? null : controller.login,
                    icon: const Icon(Icons.login_rounded, size: 20),
                    label: const Text('一键认证'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 18,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    children: [
                      TextButton.icon(
                        onPressed: controller.busy ? null : controller.refresh,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('检查网络'),
                        style: TextButton.styleFrom(foregroundColor: _muted),
                      ),
                      TextButton.icon(
                        onPressed: controller.busy
                            ? null
                            : () => _configure(context),
                        icon: const Icon(
                          Icons.manage_accounts_outlined,
                          size: 18,
                        ),
                        label: const Text('配置账号'),
                        style: TextButton.styleFrom(foregroundColor: _muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({required this.controller});
  final RecoveryController controller;

  @override
  Widget build(BuildContext context) {
    final (title, detail, icon, color) = switch (controller.network) {
      NetworkState.online => (
        '网络已连接',
        controller.outcome == RecoveryOutcome.alreadyOnline
            ? '当前网络已连接，无需认证。'
            : controller.outcome == RecoveryOutcome.restored
            ? '认证成功，已确认可以联网。'
            : '现在可以正常访问网络。',
        Icons.check_circle_outline_rounded,
        const Color(0xFF2F7B62),
      ),
      NetworkState.portalRequired => (
        '需要校园网认证',
        '点击一键认证，连接校园网络。',
        Icons.wifi_lock_rounded,
        _blue,
      ),
      NetworkState.unavailable => (
        '网络暂不可达',
        '请确认已连接校园网，再检查网络。',
        Icons.wifi_off_rounded,
        const Color(0xFF9A7439),
      ),
      NetworkState.unknown => (
        '网络状态未确认',
        '检查当前网络，或尝试一键认证。',
        Icons.wifi_find_rounded,
        _muted,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EAEF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0622324A),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (controller.busy)
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: _blue),
            )
          else
            Icon(icon, size: 32, color: color),
          const SizedBox(height: 20),
          Text(
            controller.busy ? _stageMessage(controller.stage) : title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: _ink, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            controller.busy ? '请稍候，正在处理本次操作。' : detail,
            style: const TextStyle(color: _muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.failure});
  final FailureCode failure;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF5EEE4),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 20,
          color: Color(0xFF866638),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _failureMessage(failure),
            style: const TextStyle(color: Color(0xFF6D5635), height: 1.5),
          ),
        ),
      ],
    ),
  );
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.controller});
  final RecoveryController controller;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _suffix = TextEditingController();
  bool _saving = false;
  bool _loading = true;
  bool _obscurePassword = false;
  FailureCode? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final credentials = await widget.controller.loadAccount();
    if (!mounted) return;
    if (credentials != null) {
      _username.text = credentials.username;
      _password.text = credentials.password;
      _suffix.text = credentials.operatorSuffix;
    }
    setState(() {
      _loading = false;
      _failure = credentials == null ? widget.controller.failure : null;
    });
  }

  @override
  void dispose() {
    _username.clear();
    _password.clear();
    _suffix.clear();
    _username.dispose();
    _password.dispose();
    _suffix.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving ||
        widget.controller.busy ||
        !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _failure = null;
    });
    final saved = await widget.controller.saveAccount(
      Credentials(_username.text, _password.text, operatorSuffix: _suffix.text),
    );
    if (!mounted) return;
    if (saved) {
      _username.clear();
      _password.clear();
      _suffix.clear();
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _failure = widget.controller.failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final enabled = !_loading && !_saving && !widget.controller.busy;
      return PopScope(
        canPop: enabled,
        child: AlertDialog(
          backgroundColor: _canvas,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          title: const Text('配置账号'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '账号密码仅保存于本机配置文件。',
                      style: TextStyle(color: _muted, height: 1.5),
                    ),
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: _username,
                      enabled: enabled,
                      autofocus: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      enableIMEPersonalizedLearning: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '账号',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '请输入账号'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      enabled: enabled,
                      obscureText: _obscurePassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      enableIMEPersonalizedLearning: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: '密码',
                        border: OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) =>
                          value == null || value.isEmpty ? '请输入密码' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _suffix,
                      enabled: enabled,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _save(),
                      decoration: const InputDecoration(
                        labelText: '运营商后缀（可选）',
                        helperText: '不需要时留空',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_failure case final failure?) ...[
                      const SizedBox(height: 16),
                      _FailureNotice(failure: failure),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: enabled
                  ? () => Navigator.of(context).pop(false)
                  : null,
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: enabled ? _save : null,
              style: FilledButton.styleFrom(backgroundColor: _blue),
              child: Text(_saving ? '正在保存' : '保存'),
            ),
          ],
        ),
      );
    },
  );
}

String _stageMessage(RecoveryStage? stage) => switch (stage) {
  RecoveryStage.checking => '正在检查网络',
  RecoveryStage.preparing => '正在准备认证',
  RecoveryStage.authenticating => '正在提交认证',
  RecoveryStage.verifying => '正在确认联网',
  null => '正在处理',
};

String _failureMessage(FailureCode failure) => switch (failure) {
  FailureCode.credentialsMissing => '尚未配置账号。请先配置账号密码，再尝试认证。',
  FailureCode.credentialsInvalid => '账号信息格式不正确。请检查账号、密码与运营商后缀。',
  FailureCode.credentialStoreUnavailable => '账号配置无法保存或读取。请检查应用目录权限后重试。',
  FailureCode.credentialFileUnavailable => '账号配置无法保存或读取。请检查应用目录权限后重试。',
  FailureCode.networkUnavailable => '网络暂不可达。请确认已连接校园网，再重试。',
  FailureCode.protocol => '校园网认证页面与预期不符。请稍后重试或联系维护者。',
  FailureCode.authRejected => '认证未通过。请核对账号密码与运营商后缀后重试。',
  FailureCode.verificationFailed => '已完成认证，但尚未确认联网。请检查网络后再试。',
  FailureCode.cancelled => '操作已取消。回到应用后可以重新检查网络。',
  FailureCode.timeout => '操作超时。请检查网络后重试。',
  FailureCode.submittedUnconfirmed => '认证请求已提交，结果尚未确认。请先检查网络，避免重复认证。',
};
