import Flutter
import UIKit
import ExternalAccessory

// MARK: - Plugin
// iOS only exposes Bluetooth Classic to apps through ExternalAccessory (MFi accessories).
// The app must list the accessory's protocol strings under UISupportedExternalAccessoryProtocols.
public class SwiftFlutterBluetoothClassicPlugin: NSObject, FlutterPlugin {
  private let methodChannel: FlutterMethodChannel
  private let stateChannel: FlutterEventChannel
  private let connectionChannel: FlutterEventChannel
  private let dataChannel: FlutterEventChannel

  private let stateStreamHandler = BluetoothStateStreamHandler()
  private let connectionStreamHandler = BluetoothConnectionStreamHandler()
  private let dataStreamHandler = BluetoothDataStreamHandler()

  private var accessoryManager: AccessoryManager?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SwiftFlutterBluetoothClassicPlugin(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: instance.methodChannel)
  }

  init(registrar: FlutterPluginRegistrar) {
    methodChannel = FlutterMethodChannel(name: "com.flutter_bluetooth_classic.plugin/flutter_bluetooth_classic", binaryMessenger: registrar.messenger())
    stateChannel = FlutterEventChannel(name: "com.flutter_bluetooth_classic.plugin/flutter_bluetooth_classic_state", binaryMessenger: registrar.messenger())
    connectionChannel = FlutterEventChannel(name: "com.flutter_bluetooth_classic.plugin/flutter_bluetooth_classic_connection", binaryMessenger: registrar.messenger())
    dataChannel = FlutterEventChannel(name: "com.flutter_bluetooth_classic.plugin/flutter_bluetooth_classic_data", binaryMessenger: registrar.messenger())

    super.init()

    stateChannel.setStreamHandler(stateStreamHandler)
    connectionChannel.setStreamHandler(connectionStreamHandler)
    dataChannel.setStreamHandler(dataStreamHandler)

    accessoryManager = AccessoryManager(
      stateHandler: stateStreamHandler,
      connectionHandler: connectionStreamHandler,
      dataHandler: dataStreamHandler
    )
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isBluetoothSupported":
      result(true)

    case "isBluetoothEnabled":
      // ExternalAccessory exposes no radio state; reading it would need CoreBluetooth and its permission prompt.
      result(true)

    case "enableBluetooth":
      result(FlutterError(code: "UNSUPPORTED",
                         message: "Cannot enable Bluetooth programmatically on iOS",
                         details: nil))

    case "getPairedDevices":
      accessoryManager?.getPairedDevices(completion: result)

    case "getDiscoveredDevices":
      accessoryManager?.getDiscoveredDevices(completion: result)

    case "startDiscovery":
      accessoryManager?.startDiscovery(completion: result)

    case "stopDiscovery":
      // The system accessory picker is modal and cannot be dismissed programmatically.
      result(true)

    case "connect":
      guard let args = call.arguments as? [String: Any],
            let address = args["address"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT",
                           message: "Device address is required",
                           details: nil))
        return
      }
      accessoryManager?.connect(address: address, completion: result)

    case "disconnect":
      accessoryManager?.disconnect(completion: result)

    case "sendData":
      // A Dart Uint8List arrives as FlutterStandardTypedData, a plain List<int> as [Int].
      let args = call.arguments as? [String: Any]
      let payload: Data
      if let typed = args?["data"] as? FlutterStandardTypedData {
        payload = typed.data
      } else if let list = args?["data"] as? [Int] {
        payload = Data(list.map { UInt8(truncatingIfNeeded: $0) })
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT",
                           message: "Data is required",
                           details: nil))
        return
      }
      accessoryManager?.sendData(payload, protocolString: args?["protocol"] as? String, completion: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// MARK: - Stream Handlers
class BluetoothStateStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func send(_ data: Any) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(data)
    }
  }
}

class BluetoothConnectionStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func send(_ data: Any) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(data)
    }
  }
}

class BluetoothDataStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func send(_ data: Any) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(data)
    }
  }
}

// MARK: - Accessory Manager
// All state here is touched on the main thread only; stream I/O lives on StreamThread.
class AccessoryManager: NSObject {
  private let stateHandler: BluetoothStateStreamHandler
  private let connectionHandler: BluetoothConnectionStreamHandler
  private let dataHandler: BluetoothDataStreamHandler

  private let ioThread = StreamThread()
  private var sessions: [AccessorySession] = []
  private var connectedAccessory: EAAccessory?
  private var discoveredDevices: [[String: Any]] = []
  private var discoveredIds = Set<Int>()

  // Declaration order in Info.plist decides the default write target for sendData.
  private let declaredProtocols: [String] =
    Bundle.main.object(forInfoDictionaryKey: "UISupportedExternalAccessoryProtocols") as? [String] ?? []

  init(stateHandler: BluetoothStateStreamHandler,
       connectionHandler: BluetoothConnectionStreamHandler,
       dataHandler: BluetoothDataStreamHandler) {
    self.stateHandler = stateHandler
    self.connectionHandler = connectionHandler
    self.dataHandler = dataHandler
    super.init()

    let manager = EAAccessoryManager.shared()
    NotificationCenter.default.addObserver(self, selector: #selector(accessoryDidConnect(_:)),
                                           name: .EAAccessoryDidConnect, object: manager)
    NotificationCenter.default.addObserver(self, selector: #selector(accessoryDidDisconnect(_:)),
                                           name: .EAAccessoryDidDisconnect, object: manager)
    manager.registerForLocalNotifications()
    ioThread.start()
  }

  func getPairedDevices(completion: @escaping FlutterResult) {
    completion(supportedAccessories().map(deviceMap))
  }

  func getDiscoveredDevices(completion: @escaping FlutterResult) {
    completion(discoveredDevices)
  }

  func startDiscovery(completion: @escaping FlutterResult) {
    discoveredDevices.removeAll()
    discoveredIds.removeAll()
    supportedAccessories().forEach(reportDiscovered)

    // Pairing a new accessory is only possible through the system picker; a successful pick
    // surfaces as EAAccessoryDidConnect, so the completion's error is not needed here.
    EAAccessoryManager.shared().showBluetoothAccessoryPicker(withNameFilter: nil, completion: nil)
    completion(true)
  }

  func connect(address: String, completion: @escaping FlutterResult) {
    guard let accessory = supportedAccessories().first(where: {
      self.address(of: $0) == address || String($0.connectionID) == address
    }) else {
      completion(FlutterError(code: "DEVICE_NOT_FOUND",
                            message: "Accessory not connected to this device. Pair it in Settings or via startDiscovery.",
                            details: nil))
      return
    }

    closeSessions()

    let deviceAddress = self.address(of: accessory)
    let connectionID = accessory.connectionID
    let dataHandler = self.dataHandler

    // EASession is per protocol, e.g. Emlid reads com.emlid.nmea and writes com.emlid.corrections.
    sessions = declaredProtocols
      .filter { accessory.protocolStrings.contains($0) }
      .compactMap { protocolString in
        AccessorySession(
          accessory: accessory,
          protocolString: protocolString,
          thread: ioThread,
          onData: { data in
            dataHandler.send([
              "deviceAddress": deviceAddress,
              "data": FlutterStandardTypedData(bytes: data)
            ])
          },
          onFailure: { [weak self] in
            DispatchQueue.main.async { self?.handleLinkLost(connectionID: connectionID) }
          })
      }

    guard !sessions.isEmpty else {
      completion(FlutterError(code: "SESSION_FAILED",
                            message: "Could not open a session for any declared protocol",
                            details: nil))
      return
    }

    connectedAccessory = accessory
    sessions.forEach { $0.open() }

    connectionHandler.send([
      "isConnected": true,
      "deviceAddress": deviceAddress,
      "status": "CONNECTED"
    ])
    completion(true)
  }

  func disconnect(completion: @escaping FlutterResult) {
    // Only closes our sessions; iOS owns the Bluetooth link itself and keeps it up.
    if let accessory = connectedAccessory {
      closeSessions()
      sendDisconnected(address(of: accessory))
    }
    completion(true)
  }

  func sendData(_ data: Data, protocolString: String?, completion: @escaping FlutterResult) {
    let target: AccessorySession?
    if let protocolString = protocolString {
      target = sessions.first { $0.protocolString == protocolString }
    } else {
      target = sessions.first
    }

    guard let session = target else {
      completion(FlutterError(code: "NOT_CONNECTED",
                            message: "No open session for the requested protocol",
                            details: nil))
      return
    }

    session.write(data)
    completion(true)
  }

  // MARK: - Helpers
  private func supportedAccessories() -> [EAAccessory] {
    EAAccessoryManager.shared().connectedAccessories.filter {
      !Set($0.protocolStrings).isDisjoint(with: declaredProtocols)
    }
  }

  // serialNumber survives reconnects; connectionID is reassigned every time the link comes up.
  private func address(of accessory: EAAccessory) -> String {
    accessory.serialNumber.isEmpty ? String(accessory.connectionID) : accessory.serialNumber
  }

  private func deviceMap(_ accessory: EAAccessory) -> [String: Any] {
    [
      "name": accessory.name,
      "address": address(of: accessory),
      "paired": true
    ]
  }

  private func reportDiscovered(_ accessory: EAAccessory) {
    guard discoveredIds.insert(accessory.connectionID).inserted else { return }

    let device = deviceMap(accessory)
    discoveredDevices.append(device)
    stateHandler.send([
      "event": "deviceFound",
      "device": device
    ])
  }

  private func closeSessions() {
    sessions.forEach { $0.close() }
    sessions.removeAll()
    connectedAccessory = nil
  }

  private func handleLinkLost(connectionID: Int) {
    guard let accessory = connectedAccessory, accessory.connectionID == connectionID else { return }
    closeSessions()
    sendDisconnected(address(of: accessory))
  }

  private func sendDisconnected(_ deviceAddress: String) {
    connectionHandler.send([
      "isConnected": false,
      "deviceAddress": deviceAddress,
      "status": "DISCONNECTED"
    ])
  }

  @objc private func accessoryDidConnect(_ notification: Notification) {
    guard let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory,
          !Set(accessory.protocolStrings).isDisjoint(with: declaredProtocols) else { return }
    reportDiscovered(accessory)
  }

  @objc private func accessoryDidDisconnect(_ notification: Notification) {
    guard let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory else { return }
    handleLinkLost(connectionID: accessory.connectionID)
  }
}

// MARK: - Accessory Session
// One EASession and its streams. Everything below runs on the StreamThread.
final class AccessorySession: NSObject, StreamDelegate {
  let protocolString: String

  private let session: EASession
  private let thread: StreamThread
  private let onData: (Data) -> Void
  private let onFailure: () -> Void

  private var pendingWrite = Data()
  private var readBuffer = [UInt8](repeating: 0, count: 4096)

  init?(accessory: EAAccessory,
        protocolString: String,
        thread: StreamThread,
        onData: @escaping (Data) -> Void,
        onFailure: @escaping () -> Void) {
    guard let session = EASession(accessory: accessory, forProtocol: protocolString) else { return nil }
    self.protocolString = protocolString
    self.session = session
    self.thread = thread
    self.onData = onData
    self.onFailure = onFailure
    super.init()
  }

  private var streams: [Stream] {
    let all: [Stream?] = [session.inputStream, session.outputStream]
    return all.compactMap { $0 }
  }

  func open() {
    thread.enqueue { [self] in
      for stream in streams {
        stream.delegate = self
        stream.schedule(in: .current, forMode: .default)
        stream.open()
      }
    }
  }

  func close() {
    // The block keeps self (and the EASession) alive until the streams are torn down.
    thread.enqueue { [self] in
      for stream in streams {
        stream.close()
        stream.remove(from: .current, forMode: .default)
        stream.delegate = nil
      }
      pendingWrite.removeAll()
    }
  }

  func write(_ data: Data) {
    thread.enqueue { [self] in
      pendingWrite.append(data)
      flush()
    }
  }

  // The output stream may accept only part of the buffer; the rest goes out on the next hasSpaceAvailable.
  private func flush() {
    guard let output = session.outputStream, output.hasSpaceAvailable, !pendingWrite.isEmpty else { return }

    let written = pendingWrite.withUnsafeBytes { raw in
      output.write(raw.bindMemory(to: UInt8.self).baseAddress!, maxLength: raw.count)
    }
    if written > 0 {
      pendingWrite.removeFirst(written)
    }
  }

  func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
    switch eventCode {
    case .hasBytesAvailable:
      guard let input = aStream as? InputStream else { return }
      while input.hasBytesAvailable {
        let count = input.read(&readBuffer, maxLength: readBuffer.count)
        if count <= 0 { break }
        onData(Data(readBuffer[0..<count]))
      }

    case .hasSpaceAvailable:
      flush()

    case .errorOccurred, .endEncountered:
      onFailure()

    default:
      break
    }
  }
}

// MARK: - Stream Thread
// EASession streams deliver events through a run loop. A dedicated one keeps NMEA/RTCM
// flowing even when the main thread stalls on UI work.
final class StreamThread: Thread {
  private var runLoop: RunLoop?
  private let ready = DispatchSemaphore(value: 0)

  override init() {
    super.init()
    name = "flutter_bluetooth_classic.io"
    qualityOfService = .userInitiated
  }

  override func start() {
    super.start()
    ready.wait()
  }

  override func main() {
    runLoop = RunLoop.current
    // A run loop with no input sources returns immediately; the port keeps it alive between sessions.
    RunLoop.current.add(NSMachPort(), forMode: .default)
    ready.signal()

    while !isCancelled {
      RunLoop.current.run(mode: .default, before: .distantFuture)
    }
  }

  func enqueue(_ block: @escaping () -> Void) {
    guard let runLoop = runLoop else { return }
    runLoop.perform(inModes: [.default], block: block)
    // perform(inModes:) does not wake a sleeping run loop by itself.
    CFRunLoopWakeUp(runLoop.getCFRunLoop())
  }
}
