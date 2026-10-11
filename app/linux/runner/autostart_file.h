#ifndef XDUWLAN_AUTOSTART_FILE_H_
#define XDUWLAN_AUTOSTART_FILE_H_

#include <string>

namespace xduwlan {

// 错误只含固定分类；调用方不得附带系统异常或文件内容。
struct StartupResult {
  bool enabled;
  const char* error;
};

// 输入由原生宿主提供，文件逻辑不读取环境或访问真实用户目录。
class AutostartFile {
 public:
  AutostartFile(std::string config_home, std::string executable);
  StartupResult IsEnabled() const;
  StartupResult SetEnabled(bool enabled) const;

 private:
  std::string config_home_;
  std::string executable_;
};

std::string StartupConfigHome(const std::string& xdg_config_home,
                              const std::string& home);

}  // namespace xduwlan

#endif  // XDUWLAN_AUTOSTART_FILE_H_
