import SwiftUI

struct SwipeCleanSessionView: View {
    let bucket: SwipeCleanBucket

    @Environment(AppServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SwipeCleanViewModel()
    @State private var dragOffset: CGSize = .zero
    @State private var showPaywall = false
    @State private var isCommitting = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if viewModel.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if viewModel.isFinished || viewModel.totalCount == 0 {
                finishedState
            } else {
                cardStack
                actionBar
            }
        }
        .navigationTitle(bucket.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.undo(services: services)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndo || isCommitting)
            }
        }
        .task {
            await viewModel.load(bucket: bucket, services: services)
        }
        .onDisappear {
            viewModel.cancelAllTasks()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - 头部进度

    private var header: some View {
        VStack(spacing: 6) {
            ProgressView(value: viewModel.progress)
                .tint(.accentColor)
            HStack {
                Text(String(localized: "\(viewModel.processedCount) / \(viewModel.totalCount)"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.trashedSizeInSession > 0 {
                    Label(viewModel.trashedSizeText, systemImage: "trash")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - 卡片堆

    private var cardStack: some View {
        GeometryReader { geo in
            ZStack {
                // 下一张垫在底下，制造纵深
                if let upcoming = viewModel.upcoming {
                    SwipeCard(
                        image: viewModel.thumbnail(for: upcoming.id),
                        offset: .zero,
                        isTop: false
                    )
                    .scaleEffect(0.94)
                    .opacity(0.6)
                }

                if let current = viewModel.current {
                    SwipeCard(
                        image: viewModel.thumbnail(for: current.id),
                        offset: dragOffset,
                        isTop: true
                    )
                    .gesture(dragGesture)
                    .allowsHitTesting(!isCommitting)
                    .id(current.id)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isCommitting else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard !isCommitting else { return }
                let width = value.translation.width
                if width < -SwipeCard.decisionThreshold {
                    commit(.trash)
                } else if width > SwipeCard.decisionThreshold {
                    commit(.keep)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    // MARK: - 底部按钮

    private var actionBar: some View {
        HStack(spacing: 40) {
            circleButton(icon: "trash.fill", tint: .red) { commit(.trash) }
                .disabled(isCommitting)
            circleButton(icon: "checkmark", tint: .green) { commit(.keep) }
                .disabled(isCommitting)
        }
        .padding(.bottom, 28)
    }

    private func circleButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.bold())
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1.5) }
        }
    }

    // MARK: - 完成态

    private var finishedState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text(String(localized: "这一堆清完了"))
                .font(.title3.bold())
            if viewModel.trashedSizeInSession > 0 {
                Text(String(localized: "本次可释放 \(viewModel.trashedSizeText)，去垃圾桶确认删除"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
            Button(String(localized: "重新清理这一堆")) {
                Task { await viewModel.restart(services: services) }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Button(String(localized: "完成")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 28)
        }
    }

    // MARK: - 决策落地

    private func commit(_ decision: SwipeDecision) {
        // 重入保护：动画/延迟推进期间（220ms 窗口）忽略后续点击或拖拽，避免误判到下一张卡片
        guard !isCommitting else { return }

        // 门控时点与 ShuffleFeedView.swift:233 保持一致：拦在移入垃圾桶这一步
        if decision == .trash,
           !ProFeatureGate.canClean(isPro: services.subscription.isPro) {
            showPaywall = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                dragOffset = .zero
            }
            return
        }

        isCommitting = true

        // 先把卡片甩出屏幕，再推进队列，避免下一张闪现在旧位置
        withAnimation(.easeOut(duration: 0.22)) {
            dragOffset = CGSize(
                width: decision == .trash ? -700 : 700,
                height: dragOffset.height
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            viewModel.decide(decision, services: services)
            dragOffset = .zero
            isCommitting = false
        }
    }
}
