import Flutter
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let voiceAudio = IOSVoiceAudioEngine()
  private let secureSession = SecureSessionBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    voiceAudio.register(with: engineBridge.applicationRegistrar.messenger())
    secureSession.register(with: engineBridge.applicationRegistrar.messenger())
  }
}

private final class SecureSessionBridge {
  private let service = "com.coderpwh.agent_voice_app.auth"
  private let account = "current_session"

  func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(
      name: "agent_voice/secure_session",
      binaryMessenger: messenger
    ).setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "secure_session", message: "Storage unavailable", details: nil))
        return
      }
      switch call.method {
      case "read":
        self.read(result: result)
      case "write":
        guard let value = call.arguments as? String else {
          result(FlutterError(code: "secure_session", message: "Value is required", details: nil))
          return
        }
        self.write(value, result: result)
      case "delete":
        self.delete()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func query() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  private func read(result: FlutterResult) {
    var item = query()
    item[kSecReturnData as String] = true
    item[kSecMatchLimit as String] = kSecMatchLimitOne
    var value: CFTypeRef?
    let status = SecItemCopyMatching(item as CFDictionary, &value)
    if status == errSecItemNotFound {
      result(nil)
      return
    }
    guard status == errSecSuccess,
      let data = value as? Data,
      let string = String(data: data, encoding: .utf8)
    else {
      result(FlutterError(code: "secure_session", message: "Keychain read failed", details: status))
      return
    }
    result(string)
  }

  private func write(_ value: String, result: FlutterResult) {
    delete()
    var item = query()
    item[kSecValueData as String] = Data(value.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    if status == errSecSuccess {
      result(nil)
    } else {
      result(FlutterError(code: "secure_session", message: "Keychain write failed", details: status))
    }
  }

  private func delete() {
    SecItemDelete(query() as CFDictionary)
  }
}
