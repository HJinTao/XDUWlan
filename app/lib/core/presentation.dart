import 'domain.dart';

/// 所有界面、托盘和通知共用脱敏文案，不使用服务器业务消息。
String networkMessage(NetworkState network) => switch (network) {
  NetworkState.online => '网络已连接',
  NetworkState.portalRequired => '需要校园网认证',
  NetworkState.unavailable => '网络暂不可达',
  NetworkState.unknown => '网络状态未确认',
};

String linkMessage(NetworkLink link) => switch (link) {
  NetworkLink.cellular => '蜂窝网络',
  NetworkLink.wifi => 'Wi-Fi',
  NetworkLink.wired => '有线网络',
  NetworkLink.other => '其他网络',
  NetworkLink.none => '无网络',
  NetworkLink.unknown => '网络类型未确认',
};

String campusMessage(CampusNetworkState campus) => switch (campus) {
  CampusNetworkState.unconfirmed => '校园网未确认',
  CampusNetworkState.authenticationRequired => '需要校园网认证',
  CampusNetworkState.online => '校园网已连接',
  CampusNetworkState.unavailable => '校园网络暂不可达',
  CampusNetworkState.unknown => '校园网状态未确认',
};

String stageMessage(RecoveryStage? stage) => switch (stage) {
  RecoveryStage.checking => '正在检查网络',
  RecoveryStage.preparing => '正在准备认证',
  RecoveryStage.authenticating => '正在提交认证',
  RecoveryStage.verifying => '正在确认联网',
  null => '正在处理',
};

String failureMessage(FailureCode failure) => switch (failure) {
  FailureCode.credentialsMissing => '尚未配置账号。请先配置账号密码，再尝试认证。',
  FailureCode.credentialsInvalid => '账号信息格式不正确。请检查账号、密码与运营商后缀。',
  FailureCode.credentialStoreUnavailable ||
  FailureCode.credentialFileUnavailable => '账号配置无法保存或读取。请检查应用目录权限后重试。',
  FailureCode.networkUnavailable => '网络暂不可达。请确认已连接校园网，再重试。',
  FailureCode.protocol => '校园网认证页面与预期不符。请稍后重试或联系维护者。',
  FailureCode.authRejected => '认证未通过。请核对账号密码与运营商后缀后重试。',
  FailureCode.verificationFailed => '已完成认证，但尚未确认联网。请检查网络后再试。',
  FailureCode.cancelled => '操作已取消，可以重新检查网络。',
  FailureCode.timeout => '操作超时。请检查网络后重试。',
  FailureCode.submittedUnconfirmed => '认证请求已提交，结果尚未确认。请先检查网络，避免重复认证。',
  FailureCode.authenticationNotAllowed => '当前网络不允许认证。请连接已确认的校园 Wi-Fi 后重试。',
};
