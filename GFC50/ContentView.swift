import SwiftUI
import Foundation
import CoreBluetooth
import CoreMIDI
import Combine

struct ContentView: View {
    @StateObject private var viewModel = MIDIViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // Connection Status
            HStack {
                Text("GFC50 Connected:")
                Spacer()
                Toggle("", isOn: $viewModel.isConnected)
                    .labelsHidden()
                    .disabled(true) // Only shows status
            }
            .padding()

            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(viewModel.consoleText.indices, id: \.self) { index in
                            Text(viewModel.consoleText[index])
                                .id(index) // Attach an ID to each Text item
                        }
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity)
                .onChange(of: viewModel.consoleText) { _ in
                    // Scroll to the last line when consoleText is updated
                    if let lastIndex = viewModel.consoleText.indices.last {
                        scrollViewProxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
            .padding()
        }
        .padding()
        .onAppear {
            viewModel.startBluetoothScan() // Start Bluetooth discovery when the view appears
        }
    }
}


class MIDIViewModel: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @Published var isConnected: Bool = false
    @Published var consoleText: [String] = []
    
    private let midiSourceName = "GFC50"
    private let midiClientName = "GFC50"
    
    private var centralManager: CBCentralManager!
    private var restoredPeripherals: [CBPeripheral] = []
    private var hmSoftPeripheral: CBPeripheral?
    private var hmSoftCharacteristic: CBCharacteristic?
    private var midiClient: MIDIClientRef = 0
    private var midiSource: MIDIPortRef = 0

    private var foundDevices: Set<String> = []

    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: "BluetoothCentralManager"])
        setupMIDI()
    }

    func setupMIDI() {
          // Create a MIDI client and check for errors
          let clientStatus = MIDIClientCreate(midiClientName as CFString, nil, nil, &midiClient)
          if clientStatus != noErr {
              logToConsole("Error creating MIDI client: \(clientStatus)")
              return
          }
        
        let MyMIDIReadProc: MIDIReadProc = { packetList, readProcRefCon, srcConnRefCon in }

          // Create a virtual MIDI source and check for errors
            let destinationStatus = MIDIDestinationCreate(midiClient, midiSourceName as CFString, MyMIDIReadProc, nil, &midiSource)
            if destinationStatus != noErr {
                logToConsole("Error creating MIDI destination: \(destinationStatus)")
                return
            }
        
        let sourceStatus = MIDISourceCreate(midiClient, midiSourceName as CFString, &midiSource)
          if sourceStatus != noErr {
              logToConsole("Error creating MIDI source: \(sourceStatus)")
              return
          }
          
        logToConsole("MIDI source created: \(midiSourceName)")
      }
    
    func startBluetoothScan() {
        if centralManager.state == .poweredOn {
            reconnectToRestoredPeripherals()
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        } else {
            logToConsole("Waiting for Bluetooth to power on.")
        }
    }
    
    @objc func stopScan() {
        if centralManager.isScanning {
            logToConsole("Bluetooth scanning stopped.")
            centralManager.stopScan()
        }
    }

    // Central Manager Delegate methods
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            logToConsole("Bluetooth is powered on.")
            startBluetoothScan()
        } else {
            logToConsole("Bluetooth is not available. (state=\(central.state)")
        }
    }
        
    // Call this when the app enters the foreground
    func applicationWillEnterForeground() {
        if centralManager.state == .poweredOn {
            startBluetoothScan()
        }
    }
    
    // Called when the app is being restored after being suspended or in the background
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
         // Restore any previously connected peripherals if available
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            restoredPeripherals = peripherals
            logToConsole("Restored, attempting reconnect to: \(restoredPeripherals)")
        }
       
        if central.state == .poweredOn {
            reconnectToRestoredPeripherals()
        }
    }
        
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let peripheralName = peripheral.name ?? "Unknown"
        let previouslyFound = foundDevices.contains(peripheralName)
        foundDevices.insert(peripheralName)
        if !previouslyFound {
            logToConsole("BlueTooth Discovered: \(peripheralName)")
        }
        if peripheralName.contains("HMSoft") == true {
            self.hmSoftPeripheral = peripheral
            self.centralManager.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
      connectGfc50(peripheral)
    }

    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            for service in services {
                logToConsole("Service discovered: \(service.uuid)")
                peripheral.discoverCharacteristics(nil, for: service) // Discover characteristics for the service
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                logToConsole("Characteristic discovered: \(characteristic.uuid)")
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic) // Read value from characteristic
                }
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic) // Enable notifications
                }
            }
        }
    }

    // Reconnect to the peripherals once Bluetooth is powered on
     func reconnectToRestoredPeripherals() {
         for peripheral in restoredPeripherals {
             logToConsole("Reconnecting to peripheral: \(peripheral.name ?? "Unknown")")
             centralManager?.connect(peripheral, options: nil)
             let peripheralName = peripheral.name ?? "Unknown"
             if peripheralName.contains("HMSoft") == true {
                 connectGfc50(peripheral)
             }
         }
     }
    
    func connectGfc50(_ peripheral: CBPeripheral?) {
        if peripheral == nil {
            
        }
        
        let name = peripheral?.name
        
        if name == "HMSoft" {
            
            if self.isConnected {
                logToConsole("Attempt to connect - already connected")
                stopScan()
                return;
            }
            logToConsole("")
            logToConsole("==================================================")
            logToConsole("===== Connected to GFC50 BlueTooth (HMSoft) ======")
            logToConsole("==================================================")
            logToConsole("")
            
            hmSoftPeripheral = peripheral
            isConnected = peripheral != nil
            hmSoftPeripheral?.delegate = self
            hmSoftPeripheral?.discoverServices(nil)
            stopScan()
        }
        else {
            logToConsole("")
            logToConsole("==================================================")
            logToConsole("===== DISCONNECTED from GFC50 BlueTooth     ======")
            logToConsole("==================================================")
            logToConsole("")

            self.hmSoftPeripheral = nil
            self.isConnected = false
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let value = characteristic.value {
            let midiBytes = [UInt8](value)
            let hexString = midiBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            logToConsole("Received GFC50 Data: \(hexString), forwarding to \(midiSourceName)")
            sendMIDIPacket(midiBytes)
        }
    }

    // Send MIDI data to iOS system
    private func sendMIDIPacket(_ midiBytes: [UInt8]) {
        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, midiBytes.count, midiBytes)
        MIDIReceived(midiSource, &packetList)
    }

    // Logging helper
    private func logToConsole(_ message: String) {
        DispatchQueue.main.async {
            self.consoleText.append(message)
            if self.consoleText.count > 50 {
                self.consoleText.removeFirst(self.consoleText.count - 50)
            }
        }
    }
}
