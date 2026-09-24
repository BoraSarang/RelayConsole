import SwiftUI
import AppKit

/// Jobs — 하트비트 작업 · overdue · 토큰/curl (PLAN_sites_jobs)
struct JobsView: View {
    @ObservedObject var store: ConsoleStore
    @State private var showingAdd = false
    @State private var name = ""
    @State private var expectSec = 3600
    @State private var curlPaste = ""
    @State private var formError: String?
    @State private var copiedToken: String?

    var body: some View {
        ZStack {
            OPColor.popBG.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().overlay(OPColor.border)
                if store.heartbeatLastError != nil || store.heartbeatPort > 0 {
                    hbBanner
                }
                Divider().overlay(OPColor.border)
                if store.jobs.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.jobs) { job in
                                jobCard(job)
                            }
                        }
                        .padding(OPSpace.md)
                    }
                }
            }
        }
        .background(OPColor.popBG)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
        .navigationTitle(L10n.string("sidebar.jobs"))
        .sheet(isPresented: $showingAdd, onDismiss: resetAddForm) { addSheet }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L10n.format("jobs.count", store.jobs.count))
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.inkDim)
            Spacer()
            Button(L10n.string("jobs.add")) {
                resetAddForm()
                showingAdd = true
            }
            .buttonStyle(.plain)
            .font(OPFont.body(12))
            .foregroundStyle(OPColor.jobs)
        }
        .padding(OPSpace.md)
    }

    private var hbBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: store.heartbeatLastError != nil ? "exclamationmark.triangle" : "heart.circle")
                .font(.system(size: 12))
                .foregroundStyle(store.heartbeatLastError != nil ? OPColor.bad : OPColor.jobs)
            if let err = store.heartbeatLastError {
                Text("\(err) — \(L10n.string("jobs.hb.error"))")
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.bad)
            } else {
                Text(L10n.format("jobs.hb.listening", store.heartbeatPort))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.inkDim)
            }
            Spacer()
        }
        .padding(.horizontal, OPSpace.md)
        .padding(.vertical, 8)
        .background(OPColor.card.opacity(0.6))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(OPColor.inkDim)
            Text(L10n.string("jobs.empty"))
                .font(OPFont.body(13))
                .foregroundStyle(OPColor.inkDim)
            OPSecondaryButton(title: L10n.string("jobs.add")) {
                resetAddForm()
                showingAdd = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    private func jobCard(_ job: Job) -> some View {
        let overdue = job.isOverdue()
        let state: StatusState = {
            if !job.enabled { return .idle }
            switch overdue {
            case .some(true): return .bad
            case .some(false): return .ok
            case nil: return .warn
            }
        }()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(state: state)
                Text(job.name)
                    .font(OPFont.body(13))
                    .foregroundStyle(OPColor.ink)
                if overdue == true {
                    Text(L10n.string("jobs.badge.overdue"))
                        .font(OPFont.number(10))
                        .foregroundStyle(OPColor.bad)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(OPColor.bad.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                } else if overdue == false {
                    Text(L10n.string("jobs.badge.ok"))
                        .font(OPFont.number(10))
                        .foregroundStyle(OPColor.ok)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(OPColor.ok.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { job.enabled },
                    set: { store.toggleJob(id: job.id, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                Button {
                    store.debugInjectBeat(id: job.id)
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(OPColor.jobs)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(L10n.string("jobs.beat.now"))
                Button {
                    store.removeJob(id: job.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OPColor.bad)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Text(L10n.format("jobs.token", job.token))
                    .font(OPFont.number(11))
                    .foregroundStyle(OPColor.inkDim)
                Button {
                    copyToken(job.token)
                } label: {
                    Image(systemName: copiedToken == job.token ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(copiedToken == job.token ? OPColor.ok : OPColor.inkDim)
                }
                .buttonStyle(.plain)
                Spacer()
            }

            // curl 전체 — 선택·복사용 (붙여넣기 대상)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("jobs.copy.curl"))
                    .font(OPFont.body(10))
                    .foregroundStyle(OPColor.inkDim)
                Text(curl(job.token))
                    .font(OPFont.number(10))
                    .foregroundStyle(OPColor.jobs)
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OPColor.popBG, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(OPColor.border, lineWidth: 1))
                HStack {
                    Spacer()
                    Button(L10n.string("jobs.copy.curl")) {
                        copyToken(curl(job.token))
                    }
                    .buttonStyle(.plain)
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.jobs)
                }
            }

            HStack(spacing: 10) {
                Text(L10n.format("jobs.expect", job.expectEverySec))
                    .font(OPFont.body(10))
                    .foregroundStyle(OPColor.inkDim)
                if let last = job.lastBeatAt {
                    Text(L10n.format("jobs.lastBeat", last.formatted(date: .omitted, time: .shortened)))
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.inkDim)
                } else {
                    Text(L10n.string("jobs.noBeat"))
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.warn.opacity(0.9))
                }
                Spacer()
            }
        }
        .padding(OPSpace.md)
        .background(OPColor.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(OPColor.border, lineWidth: 1))
    }

    private func curl(_ token: String) -> String {
        "curl -fsS \"\(hintURL(token))\" || true"
    }

    private func hintURL(_ token: String) -> String {
        "http://127.0.0.1:\(store.heartbeatPort)/hb/\(token)"
    }

    private func copyToken(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        copiedToken = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedToken == s { copiedToken = nil }
        }
    }

    private func resetAddForm() {
        name = ""
        expectSec = 3600
        curlPaste = ""
        formError = nil
    }

    private var addSheet: some View {
        ZStack {
            OPColor.popBG.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.string("jobs.add.title"))
                    .font(OPFont.title(15))
                    .foregroundStyle(OPColor.ink)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("jobs.field.name"))
                        .font(OPFont.body(11))
                        .foregroundStyle(OPColor.inkDim)
                    TextField("", text: $name)
                        .textFieldStyle(.plain)
                        .font(OPFont.body(13))
                        .foregroundStyle(OPColor.ink)
                        .padding(8)
                        .background(OPColor.popBG, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))
                }

                Stepper(
                    "\(L10n.string("jobs.field.expect")): \(expectSec / 60)m",
                    value: $expectSec,
                    in: 30...86400,
                    step: 60
                )
                .font(OPFont.body(12))
                .foregroundStyle(OPColor.ink)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("jobs.field.curl"))
                        .font(OPFont.body(11))
                        .foregroundStyle(OPColor.inkDim)
                    TextEditor(text: $curlPaste)
                        .font(OPFont.number(11))
                        .foregroundStyle(OPColor.ink)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .frame(minHeight: 64, maxHeight: 96)
                        .background(OPColor.popBG, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(OPColor.border, lineWidth: 1))
                    Text(L10n.string("jobs.field.curl.hint"))
                        .font(OPFont.body(10))
                        .foregroundStyle(OPColor.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(L10n.string("jobs.add.hint"))
                    .font(OPFont.body(11))
                    .foregroundStyle(OPColor.inkDim)
                    .fixedSize(horizontal: false, vertical: true)

                if let formError {
                    Text(formError)
                        .font(OPFont.body(11))
                        .foregroundStyle(OPColor.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    OPSecondaryButton(title: L10n.string("alerts.note.cancel")) {
                        showingAdd = false
                    }
                    OPPrimaryButton(title: L10n.string("jobs.add")) {
                        submitAdd()
                    }
                }
            }
            .padding(OPSpace.xl)
        }
        .frame(minWidth: 400, minHeight: 420)
        .preferredColorScheme(ThemeManager.shared.mode.preferred)
    }

    private func submitAdd() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else {
            formError = L10n.string("jobs.error.name")
            return
        }
        var token: String?
        let paste = curlPaste.trimmingCharacters(in: .whitespacesAndNewlines)
        if !paste.isEmpty {
            guard let parsed = SitesJobsLogic.token(fromCurl: paste) else {
                formError = L10n.string("jobs.error.curl")
                return
            }
            if store.jobs.contains(where: { $0.token.lowercased() == parsed.lowercased() }) {
                formError = L10n.string("jobs.error.dup")
                return
            }
            token = parsed
        }
        formError = nil
        store.addJob(name: n, expectEverySec: expectSec, token: token)
        showingAdd = false
    }
}
