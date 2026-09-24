# HEARTBEAT.md — 로컬 하트비트 수신 API

> 앱: Relay Console | 포트 기본 **8787** | 바인드 **127.0.0.1 고정** (외부 노출 금지)
> 오류: `E-MAC-JOB-0001` 바인드 실패 · `E-MAC-JOB-0002` 알 수 없는 토큰

## 엔드포인트

```
GET|POST http://127.0.0.1:{port}/hb/{token}
```

| 항목 | 값 |
|------|-----|
| Host | `127.0.0.1` (loopback only) |
| Path | `/hb/{token}` — Job 생성 시 UUID 앞 8자리 소문자 |
| Body | 무시 (비어 있어도 OK) |
| 성공 | `200` `text/plain` `ok` |
| 토큰 없음 | `404` `E-MAC-JOB-0002` |
| 잘못된 요청 | `400` |

## 사용 예 (cron)

```bash
# 매시간 하트비트
0 * * * * curl -fsS "http://127.0.0.1:8787/hb/ab12cd34" || true
```

## 판정

- `Job.isOverdue(now:)`
  - 미수신: 생성 후 `expectEverySec` 경과 시 overdue, 그 전은 유보(`nil`)
  - 수신 후: `elapsed > expectEverySec * 1.5` → overdue
  - `elapsed <= expectEverySec` → 정상
  - 그 사이 → 유보(`nil`, 주기 미도래)

## 보안

- 루프백 전용 · 인증 헤더 없음 (로컬 크론 전제)
- 토큰은 랜덤 8자 — 외부에서 알 수 없음
- 포트 충돌 시 `E-MAC-JOB-0001` + 설정에서 변경
