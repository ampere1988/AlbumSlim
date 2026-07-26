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
                LoadingState(AppStrings.loading)
            } else if viewModel.isFinished || viewModel.totalCount == 0 {
                finishedState
            } else {
                cardStack
                actionBar
            }
        }
        .background(Theme.background)
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
                .accessibilityLabel("撤销上一步")
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
        VStack(spacing: Spacing.s) {
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.surfaceSunken)
                Rectangle()
                    .fill(Theme.accentGradient)
                    .scaleEffect(x: min(max(viewModel.progress, 0), 1), y: 1, anchor: .leading)
            }
            .frame(height: 6)
            .clipShape(.capsule)
            .motion(Motion.standard, value: viewModel.progress)

            HStack {
                Text(String(localized: "\(viewModel.processedCount) / \(viewModel.totalCount)"))
                    .font(AppFont.metricSmall)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if viewModel.trashedSizeInSession > 0 {
                    MetaChip(text: viewModel.trashedSizeText, systemImage: "trash", tint: Theme.danger)
                }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.m)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 卡片堆

    private var cardStack: some View {
        ZStack {
            // 下一张垫在底下，制造纵深；再往下垫一层纯色，让"还有很多"这件事可见
            RoundedRectangle(cornerRadius: Radius.hero)
                .fill(Theme.surfaceSunken)
                .scaleEffect(0.88)
                .opacity(0.5)
                .padding(.top, Spacing.m)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.m)
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
        HStack(spacing: Spacing.xxxl) {
            circleButton(icon: "trash.fill", tint: Theme.danger, label: "删除") { commit(.trash) }
                .disabled(isCommitting)
            circleButton(icon: "checkmark", tint: Theme.success, label: "保留") { commit(.keep) }
                .disabled(isCommitting)
        }
        .padding(.bottom, Spacing.xxl)
    }

    private func circleButton(icon: String, tint: Color,
                              label: LocalizedStringKey,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.s) {
                Image(systemName: icon)
                    .font(.title2.bold())
                    .foregroundStyle(tint)
                    .frame(width: 68, height: 68)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay { Circle().strokeBorder(tint.opacity(0.45), lineWidth: 2) }
                    .elevation(.card)
                Text(label)
                    .font(AppFont.label)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel(label)
    }

    // MARK: - 完成态

    private var finishedState: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            GlowIcon(systemImage: "checkmark.seal.fill", tint: Theme.success, size: 92)
            Text("这一堆清完了")
                .font(AppFont.screenTitle)
                .foregroundStyle(Theme.textPrimary)
            if viewModel.trashedSizeInSession > 0 {
                Text(viewModel.trashedSizeText)
                    .font(AppFont.display)
                    .foregroundStyle(Theme.accentGradient)
                Text("本次可释放，去垃圾桶确认删除")
                    .font(AppFont.meta)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }
            Spacer()
            Button("重新清理这一堆", action: restart)
                .font(AppFont.label)
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: 44)
            Button("完成") { dismiss() }
                .primaryActionStyle()
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
        }
    }

    private func restart() {
        Task { await viewModel.restart(services: services) }
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
