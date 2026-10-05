import Foundation

/// 발열 자동 진단 — 순수 선택 + 결과 모델 (PLAN_auto_diagnose Phase 2)
///
/// 발열 enter 시점의 메모리 스냅샷(프로세스·충전·핫스팟·thermal zone)으로
/// "주범 후보"를 고른다. 새 adb 명령 0 — 폴링이 이미 먹는 값만 쓴다.
/// 자료가 없으면 해당 줄을 빼고 기록한다 (없는 값 지어내지 않음).
struct ThermalZoneReading: Codable, Equatable, Sendable {
    var name: String
    var celsius: Double
}

struct ThermalDiagnose: Codable, Equatable, Sendable {
    var fingerprint: String
    /// CPU 최상위 프로세스 (자료 없으면 nil — 줄 생략)
    var suspectName: String?
    var suspectCpu: Double?
    var charging: Bool?
    /// 맥 기본 게이트웨이 == 기기 IP (폰이 핫스팟 호스트)
    var hotspot: Bool?
    /// 최고온 3종 (내림차순)
    var hotZones: [ThermalZoneReading]
    var diagnosedAt: Date
}

enum ThermalSuspect {
    /// CPU 최상위 1건 — 자료 없으면 nil (주범을 지어내지 않는다)
    static func pick(from processes: [ProcessRow]?) -> (name: String, cpu: Double)? {
        guard let processes else { return nil }
        let ranked = processes.compactMap { r -> (String, Double)? in
            guard let cpu = r.cpuPercent else { return nil }
            return (r.name, cpu)
        }
        return ranked.max { $0.1 < $1.1 }
    }

    /// 최고온 N종 (내림차순)
    static func topZones(_ zones: [ThermalZone]?, limit: Int = 3) -> [ThermalZoneReading] {
        ((zones ?? []).sorted { $0.tempC > $1.tempC }.prefix(limit))
            .map { ThermalZoneReading(name: $0.name, celsius: $0.tempC) }
    }

    /// 핫스팟 판정 — 순수 함수 (테스트 고정)
    static func isHotspot(gateway: String?, deviceIP: String?) -> Bool {
        guard let gateway, !gateway.isEmpty,
              let deviceIP, !deviceIP.isEmpty else { return false }
        return gateway == deviceIP
    }
}
