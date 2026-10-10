import Foundation
import Darwin

@main
struct LoginAgentTests {
  static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw NSError(domain: message, code: 1) }
  }

  static func main() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("xduwlan-native-" + UUID().uuidString)
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let executable = URL(fileURLWithPath: "/虚构应用/XDU Wlan.app/Contents/MacOS/XDUWlan")
    let directory = root.appendingPathComponent("LaunchAgents")
    let agent = LoginAgent(directory: directory, executable: executable, label: "test.xduwlan.login")
    try check(!agent.isEnabled(), "缺少配置不应启用")
    try agent.setEnabled(true)
    try check(agent.isEnabled(), "保存后应读回真实状态")
    let file = directory.appendingPathComponent("test.xduwlan.login.plist")
    let properties = try PropertyListSerialization.propertyList(
      from: Data(contentsOf: file), options: [], format: nil) as! [String: Any]
    try check(properties["ProgramArguments"] as? [String] ==
              ["/虚构应用/XDU Wlan.app/Contents/MacOS/XDUWlan", "--background"], "参数应独立编码")
    let attributes = try manager.attributesOfItem(atPath: file.path)
    try check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "配置应仅当前用户可写")
    try agent.setEnabled(false)
    try check(!agent.isEnabled(), "关闭后应移除配置")

    // 同名未知内容或符号链接不得被覆盖，也不得触碰链接目标。
    let foreign = Data("虚构未知配置".utf8)
    try foreign.write(to: file)
    do {
      try agent.setEnabled(false)
      throw NSError(domain: "应拒绝未知配置", code: 1)
    } catch LoginAgent.Failure.unexpectedEntry {}
    try check(try Data(contentsOf: file) == foreign, "未知配置应保留")
    try manager.removeItem(at: file)
    let target = root.appendingPathComponent("target.plist")
    try foreign.write(to: target)
    try manager.createSymbolicLink(at: file, withDestinationURL: target)
    do {
      try agent.setEnabled(true)
      throw NSError(domain: "应拒绝文件符号链接", code: 1)
    } catch LoginAgent.Failure.unexpectedEntry {}
    try check(try Data(contentsOf: target) == foreign, "目标文件应保留")
    try manager.removeItem(at: file)
    try manager.removeItem(at: directory)
    let redirected = root.appendingPathComponent("redirected")
    try manager.createDirectory(at: redirected, withIntermediateDirectories: true)
    try manager.createSymbolicLink(at: directory, withDestinationURL: redirected)
    do {
      try agent.setEnabled(true)
      throw NSError(domain: "应拒绝目录符号链接", code: 1)
    } catch LoginAgent.Failure.unexpectedEntry {}
    try check(try manager.contentsOfDirectory(atPath: redirected.path).isEmpty, "未知目录不得写入")
    print("LoginAgent：临时目录检查通过")
  }
}
