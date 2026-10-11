// Linux 的原子无覆盖重命名接口由 GNU 扩展声明提供。
#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include "autostart_file.h"

#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>
#ifdef __linux__
#include <linux/fs.h>
#endif

#include <cerrno>
#include <cstdint>
#include <utility>

namespace xduwlan {
namespace {
constexpr const char* kEntry = "XDUWlan.desktop";
constexpr size_t kMaximumEntryBytes = 16384;

class Descriptor {
 public:
  explicit Descriptor(int value = -1) : value_(value) {}
  ~Descriptor() { if (value_ >= 0) close(value_); }
  Descriptor(const Descriptor&) = delete;
  Descriptor& operator=(const Descriptor&) = delete;
  int get() const { return value_; }
  void reset(int value) {
    if (value_ >= 0) close(value_);
    value_ = value;
  }
 private:
  int value_;
};

const char* IoError() {
  return errno == EACCES || errno == EPERM || errno == EROFS
             ? "startup_permission_denied" : "startup_io_failed";
}

bool SafeAbsolutePath(const std::string& path) {
  if (path.empty() || path.front() != '/' || path.size() >= 4096) return false;
  for (unsigned char character : path) {
    if (character < 0x20 || character == 0x7f) return false;
  }
  return true;
}

bool SameObject(const struct stat& left, const struct stat& right) {
  return left.st_dev == right.st_dev && left.st_ino == right.st_ino;
}

bool SameSnapshot(const struct stat& left, const struct stat& right) {
#ifdef __APPLE__
  bool times_match = left.st_mtimespec.tv_sec == right.st_mtimespec.tv_sec &&
      left.st_mtimespec.tv_nsec == right.st_mtimespec.tv_nsec &&
      left.st_ctimespec.tv_sec == right.st_ctimespec.tv_sec &&
      left.st_ctimespec.tv_nsec == right.st_ctimespec.tv_nsec;
#else
  bool times_match = left.st_mtim.tv_sec == right.st_mtim.tv_sec &&
      left.st_mtim.tv_nsec == right.st_mtim.tv_nsec &&
      left.st_ctim.tv_sec == right.st_ctim.tv_sec &&
      left.st_ctim.tv_nsec == right.st_ctim.tv_nsec;
#endif
  return SameObject(left, right) && left.st_mode == right.st_mode &&
      left.st_uid == right.st_uid && left.st_nlink == right.st_nlink &&
      left.st_size == right.st_size && times_match;
}

// 每一级都通过目录描述符和 O_NOFOLLOW 打开，拒绝路径重定向。
const char* OpenDirectory(const std::string& path, bool create,
                          Descriptor* result, bool* missing) {
  *missing = false;
  if (!SafeAbsolutePath(path)) return "startup_path_unavailable";
  // 创建任何目录前先验证完整路径，错误不得留下部分目录树。
  size_t checked = 1;
  while (checked < path.size()) {
    size_t slash = path.find('/', checked);
    std::string component = path.substr(checked, slash - checked);
    if (component == "." || component == "..") return "startup_path_unavailable";
    checked = slash == std::string::npos ? path.size() : slash + 1;
  }
  Descriptor directory(open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC));
  if (directory.get() < 0) return IoError();
  size_t offset = 1;
  while (offset < path.size()) {
    size_t slash = path.find('/', offset);
    std::string component = path.substr(offset, slash - offset);
    offset = slash == std::string::npos ? path.size() : slash + 1;
    if (component.empty()) continue;
    if (component == "." || component == "..") return "startup_path_unavailable";
    struct stat attributes;
    if (fstatat(directory.get(), component.c_str(), &attributes,
                AT_SYMLINK_NOFOLLOW) != 0) {
      if (errno != ENOENT) return IoError();
      if (!create) { *missing = true; return nullptr; }
      if (mkdirat(directory.get(), component.c_str(), 0700) != 0 && errno != EEXIST) {
        return IoError();
      }
    }
    int next = openat(directory.get(), component.c_str(),
                      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (next < 0) {
      return errno == ELOOP || errno == ENOTDIR
                 ? "startup_unexpected_entry" : IoError();
    }
    directory.reset(next);
    if (fstat(directory.get(), &attributes) != 0) return IoError();
    bool is_final = offset == path.size();
    bool owner_safe = attributes.st_uid == geteuid() ||
                      (!is_final && attributes.st_uid == 0);
    bool permissions_safe = (attributes.st_mode & 0022) == 0 ||
        (!is_final && attributes.st_uid == 0 && (attributes.st_mode & S_ISVTX));
    if (!owner_safe || !permissions_safe) return "startup_unexpected_entry";
  }
  struct stat final_attributes;
  if (fstat(directory.get(), &final_attributes) != 0) return IoError();
  if (final_attributes.st_uid != geteuid() || (final_attributes.st_mode & 0022) != 0) {
    return "startup_unexpected_entry";
  }
  // 交接描述符而不通过路径重开，并保留执行新进程时关闭的属性。
  result->reset(fcntl(directory.get(), F_DUPFD_CLOEXEC, 0));
  if (result->get() < 0) return IoError();
  return nullptr;
}

const char* OpenAutostart(const std::string& config_home, bool create,
                          Descriptor* result, bool* missing) {
  Descriptor config;
  const char* error = OpenDirectory(config_home, create, &config, missing);
  if (error || *missing) return error;
  if (create && mkdirat(config.get(), "autostart", 0700) != 0 && errno != EEXIST) {
    return IoError();
  }
  int value = openat(config.get(), "autostart",
                     O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (value < 0) {
    if (errno == ENOENT) { *missing = true; return nullptr; }
    return errno == ELOOP || errno == ENOTDIR
               ? "startup_unexpected_entry" : IoError();
  }
  result->reset(value);
  struct stat attributes;
  if (fstat(value, &attributes) != 0) return IoError();
  if (attributes.st_uid != geteuid() || (attributes.st_mode & 0022) != 0) {
    return "startup_unexpected_entry";
  }
  return nullptr;
}

const char* ValidateExecutable(const std::string& executable) {
  if (!SafeAbsolutePath(executable) || executable.find('=') != std::string::npos) {
    return "startup_path_unavailable";
  }
  struct stat attributes;
  if (stat(executable.c_str(), &attributes) != 0 || !S_ISREG(attributes.st_mode) ||
      (attributes.st_mode & 0111) == 0 || access(executable.c_str(), X_OK) != 0 ||
      (attributes.st_uid != geteuid() && attributes.st_uid != 0) ||
      (attributes.st_mode & 0022) != 0) {
    return "startup_path_unavailable";
  }
  return nullptr;
}

std::string QuotedExecutable(const std::string& executable) {
  std::string quoted = "\"";
  for (char character : executable) {
    // Desktop Entry 的字符串解码先于 Exec 解码；百分号单独转义字段码。
    if (character == '\\') quoted += "\\\\\\\\";
    else if (character == '"' || character == '`' || character == '$') {
      quoted += "\\\\";
      quoted += character;
    } else if (character == '%') quoted += "%%";
    else quoted += character;
  }
  return quoted + "\"";
}

std::string Contents(const std::string& exec) {
  return "[Desktop Entry]\nType=Application\nName=XDUWlan\n"
      "Comment=XDUWlan startup script\nExec=" + exec +
      " --background\nStartupNotify=false\nTerminal=false\n";
}

bool IsOurContent(const std::string& content, const std::string& executable) {
  if (content == Contents(QuotedExecutable(executable))) return true;
  // 兼容插件更早生成的不带引号格式，只接受无 Exec 保留字符的路径。
  for (unsigned char character : executable) {
    if (!((character >= 'a' && character <= 'z') ||
          (character >= 'A' && character <= 'Z') ||
          (character >= '0' && character <= '9') ||
          character == '/' || character == '.' || character == '_' ||
          character == '-')) return false;
  }
  return content == Contents(executable);
}

const char* ReadEntry(int directory, const char* name,
                      const std::string& executable, bool* missing,
                      struct stat* snapshot) {
  *missing = false;
  struct stat before;
  if (fstatat(directory, name, &before, AT_SYMLINK_NOFOLLOW) != 0) {
    if (errno == ENOENT) { *missing = true; return nullptr; }
    return IoError();
  }
  if (!S_ISREG(before.st_mode) || before.st_uid != geteuid() ||
      (before.st_mode & 0022) != 0 || before.st_nlink != 1 ||
      before.st_size < 0 || static_cast<uint64_t>(before.st_size) > kMaximumEntryBytes) {
    return "startup_unexpected_entry";
  }
  Descriptor file(openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC));
  if (file.get() < 0) {
    return errno == ELOOP ? "startup_unexpected_entry" : IoError();
  }
  struct stat opened;
  if (fstat(file.get(), &opened) != 0) return IoError();
  if (!SameSnapshot(before, opened)) return "startup_conflict";
  std::string content;
  char buffer[1024];
  for (;;) {
    ssize_t count = read(file.get(), buffer, sizeof(buffer));
    if (count < 0) {
      if (errno == EINTR) continue;
      return IoError();
    }
    if (count == 0) break;
    content.append(buffer, static_cast<size_t>(count));
    if (content.size() > kMaximumEntryBytes) return "startup_unexpected_entry";
  }
  struct stat after;
  if (fstat(file.get(), &after) != 0) return IoError();
  if (!SameSnapshot(opened, after)) return "startup_conflict";
  if (!IsOurContent(content, executable)) return "startup_unexpected_entry";
  if (snapshot) *snapshot = after;
  return nullptr;
}

const char* RandomName(std::string* result) {
  Descriptor random(open("/dev/urandom", O_RDONLY | O_CLOEXEC));
  if (random.get() < 0) return IoError();
  unsigned char bytes[16];
  size_t offset = 0;
  while (offset < sizeof(bytes)) {
    ssize_t count = read(random.get(), bytes + offset, sizeof(bytes) - offset);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return "startup_io_failed";
    offset += static_cast<size_t>(count);
  }
  constexpr char digits[] = "0123456789abcdef";
  *result = ".xduwlan-startup-";
  for (unsigned char value : bytes) {
    *result += digits[value >> 4];
    *result += digits[value & 15];
  }
  *result += ".tmp";
  return nullptr;
}

const char* WriteAll(int file, const std::string& content) {
  size_t offset = 0;
  while (offset < content.size()) {
    ssize_t count = write(file, content.data() + offset, content.size() - offset);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return IoError();
    offset += static_cast<size_t>(count);
  }
  if (fchmod(file, 0600) != 0 || fsync(file) != 0) return IoError();
  return nullptr;
}

// Linux 和 macOS 的离线文件测试均使用原子无覆盖重命名。
int MoveNoReplace(int from, const char* source, int to, const char* destination) {
#ifdef __linux__
  return renameat2(from, source, to, destination, RENAME_NOREPLACE);
#elif defined(__APPLE__)
  return renameatx_np(from, source, to, destination, RENAME_EXCL);
#else
  errno = ENOTSUP;
  return -1;
#endif
}

StartupResult Enable(int directory, const std::string& executable) {
  Descriptor file;
#ifndef __linux__
  Descriptor stage;
  std::string temporary;
  const char* error = RandomName(&temporary);
  if (error) return {false, error};
  if (mkdirat(directory, temporary.c_str(), 0700) != 0) return {false, IoError()};
  stage.reset(openat(directory, temporary.c_str(),
                      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
  if (stage.get() < 0) return {false, IoError()};
  file.reset(openat(stage.get(), "entry",
                    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600));
#else
  // 无命名临时 inode 位于同一目录：失败时关闭描述符即可，没有共享名称清理竞争。
  file.reset(openat(directory, ".", O_WRONLY | O_TMPFILE | O_CLOEXEC, 0600));
  const char* error = nullptr;
#endif
  if (file.get() < 0) return {false, IoError()};
  error = WriteAll(file.get(), Contents(QuotedExecutable(executable)));
  int published = -1;
  if (!error) {
#ifdef __linux__
    // 持有的描述符固定 inode；不需要访问能力缺失时退回不安全的命名发布。
    std::string descriptor_path = "/proc/self/fd/" + std::to_string(file.get());
    published = linkat(AT_FDCWD, descriptor_path.c_str(), directory, kEntry,
                       AT_SYMLINK_FOLLOW);
#else
    // 仅供 macOS 离线检查；临时名称在应用创建的私有操作目录中。
    published = linkat(stage.get(), "entry", directory, kEntry, 0);
#endif
  }
  if (!error && published != 0) {
    error = errno == EEXIST ? "startup_conflict" : IoError();
  }
#ifndef __linux__
  if (unlinkat(stage.get(), "entry", 0) != 0 && !error) error = IoError();
  if (unlinkat(directory, temporary.c_str(), AT_REMOVEDIR) != 0 && !error) error = IoError();
#endif
  if (error) return {false, error};
  if (fsync(directory) != 0) return {false, IoError()};
  return {true, nullptr};
}

StartupResult Disable(int directory, const std::string& executable,
                       const struct stat& original) {
  std::string temporary;
  const char* error = RandomName(&temporary);
  if (error) return {false, error};
  if (mkdirat(directory, temporary.c_str(), 0700) != 0) return {false, IoError()};
  Descriptor stage(openat(directory, temporary.c_str(),
                          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
  if (stage.get() < 0) return {false, IoError()};
  // 先原子捕获当前目录项，再复核；避免校验和 unlink 之间删除被换入的文件。
  if (MoveNoReplace(directory, kEntry, stage.get(), "entry") != 0) {
    error = errno == ENOENT || errno == EEXIST ? "startup_conflict" : IoError();
  } else {
    struct stat moved;
    bool missing = false;
    error = ReadEntry(stage.get(), "entry", executable, &missing, &moved);
    // rename 修改 ctime，因此复核内容和 inode，不沿用原来的时间戳。
    if (!error && (missing || !SameObject(original, moved))) error = "startup_conflict";
    if (error) {
      // 竞争换入的未知文件原样恢复；新目标已存在时保留私有目录中的原文件。
      // 恢复也禁止覆盖，不会销毁任何竞争者的内容。
      MoveNoReplace(stage.get(), "entry", directory, kEntry);
      error = "startup_conflict";
    } else if (unlinkat(stage.get(), "entry", 0) != 0) {
      error = IoError();
      MoveNoReplace(stage.get(), "entry", directory, kEntry);
    }
  }
  // 非空目录必须保留；其中可能保存竞争期间捕获的未知文件。
  unlinkat(directory, temporary.c_str(), AT_REMOVEDIR);
  if (!error && fsync(directory) != 0) error = IoError();
  return {false, error};
}

StartupResult Inspect(const std::string& config_home, const std::string& executable,
                       bool change, bool enabled) {
  const char* error = ValidateExecutable(executable);
  if (error) return {false, error};
  Descriptor directory;
  bool missing = false;
  error = OpenAutostart(config_home, change && enabled, &directory, &missing);
  if (error || missing) return {false, error};
  struct stat original;
  error = ReadEntry(directory.get(), kEntry, executable, &missing, &original);
  if (error) return {false, error};
  if (!change) return {!missing, nullptr};
  if (enabled) return missing ? Enable(directory.get(), executable)
                              : StartupResult{true, nullptr};
  return missing ? StartupResult{false, nullptr}
                 : Disable(directory.get(), executable, original);
}
}  // namespace

AutostartFile::AutostartFile(std::string config_home, std::string executable)
    : config_home_(std::move(config_home)), executable_(std::move(executable)) {}
StartupResult AutostartFile::IsEnabled() const {
  return Inspect(config_home_, executable_, false, false);
}
StartupResult AutostartFile::SetEnabled(bool enabled) const {
  return Inspect(config_home_, executable_, true, enabled);
}
std::string StartupConfigHome(const std::string& xdg_config_home,
                              const std::string& home) {
  if (SafeAbsolutePath(xdg_config_home)) return xdg_config_home;
  return SafeAbsolutePath(home) ? home + "/.config" : std::string();
}
}  // namespace xduwlan
