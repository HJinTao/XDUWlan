// Linux 的原子无覆盖重命名接口由 GNU 扩展声明提供。
#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include "autostart_file.h"

#include <dlfcn.h>
#include <dirent.h>
#include <fcntl.h>
#include <functional>
#include <sys/stat.h>
#include <unistd.h>

#include <cerrno>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

// 在系统调用边界注入竞争，生产文件类没有测试钩子。
#ifdef __linux__
#define XDUWLAN_SYSCALL_NOEXCEPT noexcept
#else
#define XDUWLAN_SYSCALL_NOEXCEPT
#endif

bool fail_next_write = false;
extern "C" ssize_t write(int file, const void* buffer, size_t count) {
  if (fail_next_write) {
    fail_next_write = false;
    errno = EIO;
    return -1;
  }
  auto real = reinterpret_cast<ssize_t (*)(int, const void*, size_t)>(
      dlsym(RTLD_NEXT, "write"));
  return real(file, buffer, count);
}
std::function<void()> before_publish;
std::function<void()> before_capture;
std::function<void(int, const char*, int)> before_cleanup;
extern "C" int unlinkat(int directory, const char* name, int flags)
    XDUWLAN_SYSCALL_NOEXCEPT {
  if (before_cleanup) before_cleanup(directory, name, flags);
  auto real = reinterpret_cast<int (*)(int, const char*, int)>(
      dlsym(RTLD_NEXT, "unlinkat"));
  return real(directory, name, flags);
}
uid_t owner_override = static_cast<uid_t>(-1);
ino_t owner_override_inode = 0;
extern "C" int fstat(int file, struct stat* attributes) XDUWLAN_SYSCALL_NOEXCEPT {
  auto real = reinterpret_cast<int (*)(int, struct stat*)>(dlsym(RTLD_NEXT, "fstat"));
  int result = real(file, attributes);
  if (result == 0 && attributes->st_ino == owner_override_inode &&
      owner_override != static_cast<uid_t>(-1)) attributes->st_uid = owner_override;
  return result;
}
extern "C" int fstatat(int directory, const char* name, struct stat* attributes,
                        int flags) XDUWLAN_SYSCALL_NOEXCEPT {
  auto real = reinterpret_cast<int (*)(int, const char*, struct stat*, int)>(
      dlsym(RTLD_NEXT, "fstatat"));
  int result = real(directory, name, attributes, flags);
  if (result == 0 && attributes->st_ino == owner_override_inode &&
      owner_override != static_cast<uid_t>(-1)) attributes->st_uid = owner_override;
  return result;
}
extern "C" int linkat(int from, const char* source, int to,
                       const char* destination, int flags) XDUWLAN_SYSCALL_NOEXCEPT {
  if (before_publish) {
    auto action = std::move(before_publish);
    before_publish = nullptr;
    action();
  }
  auto real = reinterpret_cast<int (*)(int, const char*, int, const char*, int)>(
      dlsym(RTLD_NEXT, "linkat"));
  return real(from, source, to, destination, flags);
}
#ifdef __linux__
extern "C" int renameat2(int from, const char* source, int to,
                          const char* destination, unsigned int flags) XDUWLAN_SYSCALL_NOEXCEPT {
  if (before_capture) {
    auto action = std::move(before_capture);
    before_capture = nullptr;
    action();
  }
  auto real = reinterpret_cast<int (*)(int, const char*, int, const char*, unsigned int)>(
      dlsym(RTLD_NEXT, "renameat2"));
  return real(from, source, to, destination, flags);
}
#else
extern "C" int renameatx_np(int from, const char* source, int to,
                             const char* destination, unsigned int flags) XDUWLAN_SYSCALL_NOEXCEPT {
  if (before_capture) {
    auto action = std::move(before_capture);
    before_capture = nullptr;
    action();
  }
  auto real = reinterpret_cast<int (*)(int, const char*, int, const char*, unsigned int)>(
      dlsym(RTLD_NEXT, "renameatx_np"));
  return real(from, source, to, destination, flags);
}
#endif

namespace {
void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

class Fixture {
 public:
  Fixture() {
    char pattern[] = "/tmp/xduwlan-autostart-test.XXXXXX";
    char* created = mkdtemp(pattern);
    Check(created != nullptr, "创建临时目录失败");
    char resolved[4096];
    Check(realpath(created, resolved) != nullptr, "临时目录解析失败");
    root = resolved;
    config = root + "/config";
    executable = root + "/xduwlan_app";
    std::ofstream(executable) << "虚构可执行文件";
    Check(chmod(executable.c_str(), 0700) == 0, "临时可执行权限失败");
  }
  ~Fixture() {
    // 测试所有输入都位于新建临时目录，清理不会访问用户启动项。
    std::string command = "rm -rf '" + root + "'";
    std::system(command.c_str());
  }
  std::string root;
  std::string config;
  std::string executable;
  void Prepare() const {
    Check(mkdir(config.c_str(), 0700) == 0, "创建临时配置目录失败");
    Check(mkdir((config + "/autostart").c_str(), 0700) == 0,
          "创建临时启动目录失败");
  }
  std::string File() const { return config + "/autostart/XDUWlan.desktop"; }
};

std::string Read(const std::string& path) {
  std::ifstream file(path);
  return {std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>()};
}
void Success(xduwlan::StartupResult result, bool enabled, const char* message) {
  Check(result.error == nullptr && result.enabled == enabled, message);
}

void Basic() {
  Fixture fixture;
  xduwlan::AutostartFile entry(fixture.config, fixture.executable);
  Success(entry.IsEnabled(), false, "缺少启动项应关闭");
  Check(access(fixture.config.c_str(), F_OK) != 0, "查询不应创建目录");
  Success(entry.SetEnabled(false), false, "重复关闭应成功且不创建目录");
  Success(entry.SetEnabled(true), true, "启用应原子发布文件");
  Success(entry.IsEnabled(), true, "启用后应读回真实状态");
  Check(Read(fixture.File()) ==
        "[Desktop Entry]\nType=Application\nName=XDUWlan\n"
        "Comment=XDUWlan startup script\nExec=\"" + fixture.executable +
        "\" --background\nStartupNotify=false\nTerminal=false\n",
        "生成内容应只有当前应用和后台参数");
  struct stat attributes;
  Check(lstat(fixture.File().c_str(), &attributes) == 0 &&
        (attributes.st_mode & 0777) == 0600 && attributes.st_nlink == 1,
        "发布文件应仅当前用户可写且无遗留硬链接");
  ino_t original_inode = attributes.st_ino;
  Success(entry.SetEnabled(true), true, "重复启用应成功");
  Check(lstat(fixture.File().c_str(), &attributes) == 0 &&
        attributes.st_ino == original_inode, "重复启用不得重写既有文件");
  Success(entry.SetEnabled(false), false, "关闭应移除本应用文件");
  Check(access(fixture.File().c_str(), F_OK) != 0, "关闭后文件应消失");
  Success(entry.SetEnabled(false), false, "重复关闭应成功");
}
void Failure(xduwlan::StartupResult result, const char* expected,
             const char* message) {
  Check(result.error != nullptr && std::string(result.error) == expected, message);
}
std::string LegacyContent(const std::string& executable) {
  return "[Desktop Entry]\nType=Application\nName=XDUWlan\n"
      "Comment=XDUWlan startup script\nExec=" + executable +
      " --background\nStartupNotify=false\nTerminal=false\n";
}
std::vector<std::string> Entries(const std::string& path) {
  std::vector<std::string> entries;
  DIR* directory = opendir(path.c_str());
  Check(directory != nullptr, "读取临时目录失败");
  while (auto* entry = readdir(directory)) {
    std::string name = entry->d_name;
    if (name != "." && name != "..") entries.push_back(name);
  }
  closedir(directory);
  return entries;
}

void Legacy() {
  Fixture fixture;
  fixture.Prepare();
  std::string content = LegacyContent(fixture.executable);
  std::ofstream(fixture.File()) << content;
  xduwlan::AutostartFile entry(fixture.config, fixture.executable);
  Success(entry.IsEnabled(), true, "应识别指向当前应用的旧插件文件");
  Success(entry.SetEnabled(true), true, "既有插件文件重复启用应成功");
  Check(Read(fixture.File()) == content, "旧插件文件不得被重写");
  Success(entry.SetEnabled(false), false, "应能删除确认属于本应用的旧格式");
}

void SpecialCharacters() {
  Fixture fixture;
  std::string executable = fixture.root + "/空 格100%\\\"$`';<&|>.bin";
  Check(rename(fixture.executable.c_str(), executable.c_str()) == 0,
        "创建特殊路径失败");
  xduwlan::AutostartFile entry(fixture.config, executable);
  Success(entry.SetEnabled(true), true, "特殊字符路径应能启用");
  Check(Read(fixture.File()) == LegacyContent(
      "\"" + fixture.root + "/空 格100%%\\\\\\\\\\\\\"\\\\$\\\\`';<&|>.bin\""),
      "特殊字符应按字符串和 Exec 两级规则编码");
  Success(entry.IsEnabled(), true, "特殊路径应可识别");
  Success(entry.SetEnabled(false), false, "特殊路径应可关闭");
}

void UnknownContents() {
  const std::vector<std::string> contents = {
      "虚构未知配置",
      "[Desktop Entry]\nExec=/虚构其他程序 --background\n",
      "[Desktop Entry]\nType=Application\nName=XDUWlan\n",
      std::string(20000, 'x'),
      std::string("[Desktop Entry]\0\n", 18),
  };
  for (const auto& content : contents) {
    Fixture fixture;
    fixture.Prepare();
    std::ofstream(fixture.File(), std::ios::binary) << content;
    xduwlan::AutostartFile entry(fixture.config, fixture.executable);
    Failure(entry.IsEnabled(), "startup_unexpected_entry", "损坏内容应拒绝查询");
    Failure(entry.SetEnabled(true), "startup_unexpected_entry", "未知内容不得覆盖");
    Failure(entry.SetEnabled(false), "startup_unexpected_entry", "未知内容不得删除");
    Check(Read(fixture.File()) == content, "未知文件内容应原样保留");
  }
}

void WrongExecutableOrArguments() {
  Fixture fixture;
  fixture.Prepare();
  xduwlan::AutostartFile entry(fixture.config, fixture.executable);
  std::ofstream(fixture.File()) << LegacyContent("\"/虚构旧安装/xduwlan_app\"");
  Failure(entry.SetEnabled(false), "startup_unexpected_entry", "其他安装路径不得删除");
  std::string changed = LegacyContent("\"" + fixture.executable + "\"");
  changed.replace(changed.find("--background"), 12, "--unknown");
  std::ofstream(fixture.File()) << changed;
  Failure(entry.IsEnabled(), "startup_unexpected_entry", "额外参数不得识别为本应用");
  std::ofstream(fixture.File()) << LegacyContent("\"" + fixture.executable + "\"") + "Hidden=true\n";
  Failure(entry.SetEnabled(true), "startup_unexpected_entry", "额外字段不得被忽略");
}

void SymbolicLinks() {
  Fixture fixture;
  fixture.Prepare();
  const std::string target = fixture.root + "/untouched";
  std::ofstream(target) << "虚构未知内容";
  Check(symlink(target.c_str(), fixture.File().c_str()) == 0, "创建文件符号链接失败");
  xduwlan::AutostartFile entry(fixture.config, fixture.executable);
  Failure(entry.IsEnabled(), "startup_unexpected_entry", "文件符号链接应拒绝");
  Failure(entry.SetEnabled(true), "startup_unexpected_entry", "不得覆盖符号链接");
  Failure(entry.SetEnabled(false), "startup_unexpected_entry", "不得删除符号链接");
  Check(Read(target) == "虚构未知内容", "链接目标应保留");
  Check(unlink(fixture.File().c_str()) == 0, "清理临时符号链接失败");
  Check(rmdir((fixture.config + "/autostart").c_str()) == 0, "清理临时目录失败");
  Check(symlink(fixture.root.c_str(), (fixture.config + "/autostart").c_str()) == 0,
        "创建目录符号链接失败");
  Failure(entry.SetEnabled(true), "startup_unexpected_entry", "启动目录符号链接应拒绝");
  Check(access((fixture.root + "/XDUWlan.desktop").c_str(), F_OK) != 0,
        "重定向目录不得写入");
  Check(unlink((fixture.config + "/autostart").c_str()) == 0, "清理目录符号链接失败");
  Check(rmdir(fixture.config.c_str()) == 0, "清理配置目录失败");
  Check(symlink(fixture.root.c_str(), fixture.config.c_str()) == 0,
        "创建配置符号链接失败");
  Failure(entry.SetEnabled(true), "startup_unexpected_entry", "配置目录符号链接应拒绝");
}

void NonRegularAndHardLinks() {
  Fixture fixture;
  fixture.Prepare();
  xduwlan::AutostartFile entry(fixture.config, fixture.executable);
  Check(mkfifo(fixture.File().c_str(), 0600) == 0, "创建临时 FIFO 失败");
  Failure(entry.SetEnabled(false), "startup_unexpected_entry", "FIFO 不得打开或删除");
  Check(unlink(fixture.File().c_str()) == 0, "清理临时 FIFO 失败");
  Check(mkdir(fixture.File().c_str(), 0700) == 0, "创建临时目录文件失败");
  Failure(entry.SetEnabled(true), "startup_unexpected_entry", "同名目录不得修改");
  Check(rmdir(fixture.File().c_str()) == 0, "清理临时目录文件失败");
  std::ofstream(fixture.File()) << LegacyContent("\"" + fixture.executable + "\"");
  Check(link(fixture.File().c_str(), (fixture.root + "/hardlink").c_str()) == 0,
        "创建临时硬链接失败");
  Failure(entry.SetEnabled(false), "startup_unexpected_entry", "多链接文件不得删除");
}

void PermissionsAndOwnership() {
  Fixture fixture;
  fixture.Prepare();
  xduwlan::AutostartFile entry(fixture.config, fixture.executable);
  Success(entry.SetEnabled(true), true, "准备权限测试失败");
  Check(chmod(fixture.File().c_str(), 0666) == 0, "设置临时文件权限失败");
  Failure(entry.IsEnabled(), "startup_unexpected_entry", "其他用户可写的文件应拒绝");
  Check(chmod(fixture.File().c_str(), 0600) == 0, "恢复临时文件权限失败");
  uid_t actual_uid = geteuid();
  struct stat attributes;
  Check(stat(fixture.config.c_str(), &attributes) == 0, "读取所有权测试目录失败");
  owner_override_inode = attributes.st_ino;
  owner_override = actual_uid == 0 ? 1 : actual_uid + 1;
  auto result = entry.SetEnabled(false);
  owner_override = static_cast<uid_t>(-1);
  Failure(result, "startup_unexpected_entry", "不同用户所有权的目录应拒绝");
  Check(access(fixture.File().c_str(), F_OK) == 0, "不同所有权的目录不得被修改");
  Check(stat(fixture.File().c_str(), &attributes) == 0, "读取所有权测试文件失败");
  owner_override_inode = attributes.st_ino;
  owner_override = actual_uid == 0 ? 1 : actual_uid + 1;
  result = entry.SetEnabled(false);
  owner_override = static_cast<uid_t>(-1);
  Failure(result, "startup_unexpected_entry", "不同用户所有权的文件应拒绝");
  Check(access(fixture.File().c_str(), F_OK) == 0, "不同所有权的文件不得被删除");
  Check(chmod((fixture.config + "/autostart").c_str(), 0777) == 0,
        "设置临时目录权限失败");
  Failure(entry.SetEnabled(false), "startup_unexpected_entry", "其他用户可写的目录应拒绝");
}

void WriteFailure() {
  Fixture fixture;
  fixture.Prepare();
  xduwlan::AutostartFile entry(fixture.config, fixture.executable);
  Check(chmod((fixture.config + "/autostart").c_str(), 0500) == 0,
        "设置只读临时目录失败");
  if (geteuid() != 0) {
    Failure(entry.SetEnabled(true), "startup_permission_denied", "目录无法写入应返回安全错误");
    Check(access(fixture.File().c_str(), F_OK) != 0, "写失败不得留下半成品");
    Success(entry.IsEnabled(), false, "写失败后读回应为关闭");
  }
  Check(chmod((fixture.config + "/autostart").c_str(), 0700) == 0,
        "恢复临时目录权限失败");
  fail_next_write = true;
  Failure(entry.SetEnabled(true), "startup_io_failed", "文件写入失败应返回安全分类");
  Check(Entries(fixture.config + "/autostart").empty(), "文件写入失败不得留下半成品");
  Success(entry.IsEnabled(), false, "写入失败后应读回关闭");
}

void PathAndXdg() {
  Check(xduwlan::StartupConfigHome("/虚构配置", "/虚构用户") == "/虚构配置",
        "应采用绝对 XDG_CONFIG_HOME");
  Check(xduwlan::StartupConfigHome("", "/虚构用户") == "/虚构用户/.config",
        "空 XDG 应使用默认目录");
  Check(xduwlan::StartupConfigHome("相对配置", "/虚构用户") == "/虚构用户/.config",
        "相对 XDG 应按规范忽略");
  Check(xduwlan::StartupConfigHome("", "相对用户").empty(), "无合法用户目录应拒绝");
  Fixture fixture;
  xduwlan::AutostartFile equal_sign(fixture.config, fixture.root + "/a=b");
  Failure(equal_sign.SetEnabled(true), "startup_path_unavailable", "等号路径不符合 Exec 规范");
  xduwlan::AutostartFile controls(fixture.config, fixture.executable + "\n");
  Failure(controls.SetEnabled(true), "startup_path_unavailable", "路径控制字符应拒绝");
  xduwlan::AutostartFile traversal(fixture.root + "/../config", fixture.executable);
  Failure(traversal.SetEnabled(true), "startup_path_unavailable", "目录上跳应拒绝");
  const std::string new_prefix = fixture.root + "/uncreated";
  xduwlan::AutostartFile late_traversal(new_prefix + "/../config", fixture.executable);
  Failure(late_traversal.SetEnabled(true), "startup_path_unavailable", "目录上跳应在写入前拒绝");
  Check(access(new_prefix.c_str(), F_OK) != 0, "无效路径不应提前创建前缀目录");
  Check(chmod(fixture.executable.c_str(), 0600) == 0, "设置临时非执行文件失败");
  xduwlan::AutostartFile no_execute(fixture.config, fixture.executable);
  Failure(no_execute.IsEnabled(), "startup_path_unavailable", "当前路径应能实际执行");
}

void PublishCompetition() {
  Fixture fixture;
  fixture.Prepare();
  xduwlan::AutostartFile entry(fixture.config, fixture.executable);
  before_publish = [&] { std::ofstream(fixture.File()) << "竞争中新出现的未知内容"; };
  Failure(entry.SetEnabled(true), "startup_conflict", "原子发布不得覆盖竞争者");
  Check(Read(fixture.File()) == "竞争中新出现的未知内容", "发布竞争中的未知内容应保留");
  Check(Entries(fixture.config + "/autostart").size() == 1,
        "发布冲突后应清理自己的临时文件");
}

void DisableCompetition() {
  Fixture fixture;
  fixture.Prepare();
  xduwlan::AutostartFile entry(fixture.config, fixture.executable);
  Success(entry.SetEnabled(true), true, "准备删除竞争失败");
  before_capture = [&] {
    Check(unlink(fixture.File().c_str()) == 0, "竞争换入准备失败");
    std::ofstream(fixture.File()) << "竞争中新换入的未知内容";
  };
  Failure(entry.SetEnabled(false), "startup_conflict", "禁用竞争换入的文件应拒绝");
  Check(Read(fixture.File()) == "竞争中新换入的未知内容", "捕获后的未知内容应原样恢复");
  Check(Entries(fixture.config + "/autostart").size() == 1,
        "成功恢复后应清理空暂存目录");
}

void RestoreCompetition() {
  Fixture fixture;
  fixture.Prepare();
  xduwlan::AutostartFile entry(fixture.config, fixture.executable);
  Success(entry.SetEnabled(true), true, "准备恢复竞争失败");
  before_capture = [&] {
    Check(unlink(fixture.File().c_str()) == 0, "捕获竞争准备失败");
    std::ofstream(fixture.File()) << "捕获的未知内容";
    before_capture = [&] { std::ofstream(fixture.File()) << "恢复前新出现的内容"; };
  };
  Failure(entry.SetEnabled(false), "startup_conflict", "恢复竞争应返回安全冲突");
  Check(Read(fixture.File()) == "恢复前新出现的内容", "恢复不得覆盖新出现的内容");
  auto entries = Entries(fixture.config + "/autostart");
  Check(entries.size() == 2, "恢复受阻时捕获内容必须保留");
  for (const auto& name : entries) {
    if (name != "XDUWlan.desktop") {
      Check(Read(fixture.config + "/autostart/" + name + "/entry") == "捕获的未知内容",
            "恢复受阻的未知内容不得丢失");
    }
  }
}

void CleanupCompetition() {
  Fixture fixture;
  fixture.Prepare();
  xduwlan::AutostartFile entry(fixture.config, fixture.executable);
  bool shared_temporary_file = false;
  std::string replaced;
  before_publish = [&] {
    for (const auto& name : Entries(fixture.config + "/autostart")) {
      struct stat attributes;
      std::string path = fixture.config + "/autostart/" + name;
      Check(lstat(path.c_str(), &attributes) == 0, "读取发布竞争目录失败");
      if (S_ISREG(attributes.st_mode)) shared_temporary_file = true;
    }
  };
  before_cleanup = [&](int directory, const char* name, int flags) {
    if (flags != 0 || std::string(name).find(".xduwlan-startup-") != 0) return;
    before_cleanup = nullptr;
    auto real_unlink = reinterpret_cast<int (*)(int, const char*, int)>(
        dlsym(RTLD_NEXT, "unlinkat"));
    Check(real_unlink(directory, name, 0) == 0, "清理竞争换入准备失败");
    int file = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL, 0600);
    Check(file >= 0, "创建清理竞争文件失败");
    const std::string foreign = "清理前换入的未知内容";
    Check(write(file, foreign.data(), foreign.size()) == static_cast<ssize_t>(foreign.size()),
          "写入清理竞争文件失败");
    close(file);
    replaced = fixture.config + "/autostart/" + name;
  };
  auto result = entry.SetEnabled(true);
  before_cleanup = nullptr;
  Success(result, true, "启用发布应完成");
  if (!replaced.empty()) {
    Check(Read(replaced) == "清理前换入的未知内容", "临时清理不得删除竞争换入的未知文件");
  }
  Check(!shared_temporary_file, "启用不应暴露需要按共享名称清理的临时文件");
  Success(entry.IsEnabled(), true, "发布后本应用启动项应保持有效");
}
}  // namespace

int main() {
  try {
    Basic();
    Legacy();
    SpecialCharacters();
    UnknownContents();
    WrongExecutableOrArguments();
    SymbolicLinks();
    NonRegularAndHardLinks();
    PermissionsAndOwnership();
    WriteFailure();
    PathAndXdg();
    PublishCompetition();
    DisableCompetition();
    RestoreCompetition();
    CleanupCompetition();
#ifdef __linux__
    std::cout << "AutostartFile：14组临时目录检查通过\n";
#else
    std::cout << "AutostartFile：14组临时目录检查通过（macOS离线子集）\n";
#endif
    return 0;
  } catch (const std::exception& error) {
    // 只有测试断言文本会输出；生产接口没有底层异常文本。
    std::cerr << "AutostartFile 测试失败：" << error.what() << '\n';
    return 1;
  }
}
