import Foundation
import Combine

/// 状态监控页的视图模型：定时采样 + 维护图表历史。
@MainActor
final class StatusViewModel: ObservableObject {
    @Published private(set) var sample: SystemSample?
    @Published private(set) var cpuHistory: [HistoryPoint] = []
    @Published private(set) var memoryHistory: [HistoryPoint] = []
    @Published private(set) var diskHistory: [HistoryPoint] = []
    @Published private(set) var networkHistory: [NetworkPoint] = []
    @Published private(set) var isPaused = false

    private let monitor = SystemMonitor()
    private var timer: Timer?
    private let interval: TimeInterval = 1.5
    private let maxHistory = 60

    func start() {
        guard timer == nil else { return }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func togglePaused() {
        isPaused.toggle()
        if isPaused {
            stop()
        } else {
            start()
        }
    }

    private func tick() {
        let newSample = monitor.sample()
        let now = newSample.timestamp
        sample = newSample
        append(&cpuHistory, value: newSample.cpuUsage, at: now)
        append(&memoryHistory, value: newSample.memoryUsedPercent, at: now)
        append(&diskHistory, value: newSample.diskUsedPercent, at: now)
        networkHistory.append(NetworkPoint(time: now, down: newSample.networkDownBytesPerSec, up: newSample.networkUpBytesPerSec))
        if networkHistory.count > maxHistory {
            networkHistory.removeFirst(networkHistory.count - maxHistory)
        }
    }

    private func append(_ array: inout [HistoryPoint], value: Double, at date: Date) {
        array.append(HistoryPoint(time: date, value: value))
        if array.count > maxHistory {
            array.removeFirst(array.count - maxHistory)
        }
    }
}
