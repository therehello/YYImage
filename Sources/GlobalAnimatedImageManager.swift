import Foundation
#if os(Linux)
import Glibc
#endif

public protocol AnimatedImagePlayerType: AnyObject {
    var idealBufferSizeBytes: Int { get }
    func updateMaxBufferSize(bytes: Int)
}

public final class GlobalAnimatedImageManager {
    public static let shared = GlobalAnimatedImageManager()

    // MARK: - Configuration
    private let memoryBudgetFraction: Double = 0.2 // 20% of physical memory by default
    private let maxBudgetBytesCap: Int = 512 * 1024 * 1024 // 512MB cap for simplicity
    private let minPerPlayerBufferBytes: Int = 4 * 1024 * 1024 // 4MB floor to avoid thrashing

    private let decodeQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "global.animated-image.decode-queue"
        q.qualityOfService = .userInitiated
        q.maxConcurrentOperationCount = ProcessInfo.processInfo.activeProcessorCount
        return q
    }()

    private let players = NSHashTable<AnyObject>.weakObjects()
    private var timer: DispatchSourceTimer?

    private init() {
        startPeriodicAdjustment()
    }

    // MARK: - Public API
    public func register(player: AnimatedImagePlayerType) {
        players.add(player)
    }

    public func unregister(player: AnimatedImagePlayerType) {
        players.remove(player)
    }

    public func addDecodeOperation(_ op: Operation) {
        decodeQueue.addOperation(op)
    }

    // MARK: - Periodic Adjustment
    private func startPeriodicAdjustment() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 0.5, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.rebalance()
        }
        timer.resume()
        self.timer = timer
    }

    private func rebalance() {
        let currentPlayers = players.allObjects.compactMap { $0 as? AnimatedImagePlayerType }
        guard !currentPlayers.isEmpty else { return }

        // Memory budget heuristic
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        var budget = Int(Double(physicalMemory) * memoryBudgetFraction)
        budget = min(budget, maxBudgetBytesCap)

        // CPU heuristic: if system is under thermal pressure or low power mode, treat as high load
        let cpuHighLoad = isHighLoadHeuristic()

        // If CPU is high, bias towards more caching within a relaxed cap (but still bounded)
        if cpuHighLoad {
            let relaxed = min(Int(Double(physicalMemory) * (memoryBudgetFraction * 1.5)), maxBudgetBytesCap * 2)
            budget = max(budget, relaxed)
        }

        // Sum ideal buffers
        let totalIdeal = currentPlayers.reduce(0) { $0 + max($1.idealBufferSizeBytes, minPerPlayerBufferBytes) }

        // Distribute
        if totalIdeal <= budget {
            // Memory sufficient: let everyone use their ideal buffer
            currentPlayers.forEach { player in
                player.updateMaxBufferSize(bytes: max(player.idealBufferSizeBytes, minPerPlayerBufferBytes))
            }
        } else {
            // Memory constrained: scale proportionally
            let scale = max(0.1, Double(budget) / Double(totalIdeal))
            currentPlayers.forEach { player in
                let ideal = max(player.idealBufferSizeBytes, minPerPlayerBufferBytes)
                let scaled = Int(Double(ideal) * scale)
                let assigned = max(minPerPlayerBufferBytes, scaled)
                player.updateMaxBufferSize(bytes: assigned)
            }
        }

        // Concurrency tuning: lower when high load, raise when low load
        let base = max(1, ProcessInfo.processInfo.activeProcessorCount)
        if cpuHighLoad {
            decodeQueue.maxConcurrentOperationCount = max(1, base / 2)
        } else {
            decodeQueue.maxConcurrentOperationCount = min(8, base * 2)
        }
    }

    private func isHighLoadHeuristic() -> Bool {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let info = ProcessInfo.processInfo
        var thermalIsHigh = false
        if #available(iOS 11.0, tvOS 11.0, watchOS 6.0, *) {
            thermalIsHigh = (info.thermalState == .serious || info.thermalState == .critical)
        }
        let lowPower = info.isLowPowerModeEnabled
        return thermalIsHigh || lowPower
        #elseif os(macOS)
        let info = ProcessInfo.processInfo
        var thermalIsHigh = false
        if #available(macOS 10.10, *) {
            thermalIsHigh = (info.thermalState == .serious || info.thermalState == .critical)
        }
        var lowPower = false
        if #available(macOS 12.0, *) {
            lowPower = info.isLowPowerModeEnabled
        }
        return thermalIsHigh || lowPower
        #else
        // Linux and others: use 1-min load average vs CPU count
        let cpuCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
        var loads = [Double](repeating: 0.0, count: 3)
        let result = loads.withUnsafeMutableBufferPointer { ptr -> Int32 in
            guard let base = ptr.baseAddress else { return -1 }
            return getloadavg(base, 3)
        }
        if result >= 1 {
            return loads[0] > Double(cpuCount) * 0.8
        }
        return false
        #endif
    }
}