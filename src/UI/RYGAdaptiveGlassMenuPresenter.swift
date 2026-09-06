import SwiftUI
import UIKit

private final class RYGWeakControllerBox {
    weak var value: UIViewController?
}

/// iOS 26 menu presentation used by RyukGram settings.
///
/// UIKit's contextual UIMenu uses a system full-width menu column for the
/// default/large element layout. That width is not exposed as a public sizing
/// knob. This presenter keeps UIMenu as the data/action model, but renders the
/// settings picker as a custom SwiftUI Liquid Glass surface whose width comes
/// from its actual labels.
@objcMembers
public final class RYGAdaptiveGlassMenuPresenter: NSObject {
    @objc(presentFrom:menu:)
    public static func present(from source: UIButton, menu: UIMenu) {
        guard #available(iOS 26.0, *) else { return }
        guard let presenter = owningViewController(for: source),
              let window = source.window else { return }

        let sourceFrame = source.convert(source.bounds, to: window)
        let safeFrame = window.bounds.inset(by: window.safeAreaInsets)
        let metrics = MenuMetrics(menu: menu, sourceFrame: sourceFrame, safeFrame: safeFrame)
        let hostBox = RYGWeakControllerBox()

        let root = AdaptiveGlassMenuView(
            rootMenu: menu,
            source: source,
            sourceFrame: sourceFrame,
            safeFrame: safeFrame,
            metrics: metrics,
            onDismiss: {
                hostBox.value?.dismiss(animated: false)
            }
        )

        let host = UIHostingController(rootView: root)
        hostBox.value = host
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .crossDissolve
        host.view.backgroundColor = .clear
        presenter.present(host, animated: false)
    }

    private static func owningViewController(for view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController {
                return topController(from: controller)
            }
            responder = current.next
        }
        if let root = view.window?.rootViewController {
            return topController(from: root)
        }
        return nil
    }

    private static func topController(from root: UIViewController) -> UIViewController {
        var current = root
        while true {
            if let presented = current.presentedViewController,
               !presented.isBeingDismissed {
                current = presented
                continue
            }
            if let nav = current as? UINavigationController,
               let visible = nav.visibleViewController {
                current = visible
                continue
            }
            if let tab = current as? UITabBarController,
               let selected = tab.selectedViewController {
                current = selected
                continue
            }
            return current
        }
    }
}

@available(iOS 26.0, *)
private struct MenuMetrics {
    let width: CGFloat
    let rowHeight: CGFloat
    let verticalPadding: CGFloat

    init(menu: UIMenu, sourceFrame: CGRect, safeFrame: CGRect) {
        let titles = MenuMetrics.allTitles(in: menu)
        let font = UIFont.systemFont(ofSize: 17.0)
        let measured = titles.reduce(CGFloat.zero) { partial, title in
            max(partial, (title as NSString).size(withAttributes: [.font: font]).width)
        }

        // Leading selection/image slot + text + optional submenu chevron +
        // breathing room. Clamp only to the available screen, never to a fixed
        // context-menu column width.
        let desired = ceil(measured + 76.0)
        let minimum = max(118.0, sourceFrame.width)
        self.width = min(max(minimum, desired), max(118.0, safeFrame.width - 24.0))
        self.rowHeight = 50.0
        self.verticalPadding = 7.0
    }

    private static func allTitles(in menu: UIMenu) -> [String] {
        var result: [String] = []
        if !menu.title.isEmpty { result.append(menu.title) }
        for child in menu.children {
            if let command = child as? UICommand {
                result.append(command.title)
            } else if let submenu = child as? UIMenu {
                result.append(contentsOf: allTitles(in: submenu))
            }
        }
        return result
    }
}

@available(iOS 26.0, *)
private struct AdaptiveGlassMenuView: View {
    let rootMenu: UIMenu
    let source: UIButton
    let sourceFrame: CGRect
    let safeFrame: CGRect
    let metrics: MenuMetrics
    let onDismiss: () -> Void

    @State private var menuStack: [UIMenu] = []
    @State private var expanded = false
    @State private var contentVisible = false

    private var currentMenu: UIMenu { menuStack.last ?? rootMenu }
    private var elements: [UIMenuElement] { flattenedElements(currentMenu) }
    private var visibleRows: CGFloat {
        CGFloat(elements.count + (menuStack.isEmpty ? 0 : 1))
    }
    private var targetHeight: CGFloat {
        let desired = visibleRows * metrics.rowHeight + metrics.verticalPadding * 2.0
        return min(desired, max(120.0, safeFrame.height - 24.0))
    }

    private var targetFrame: CGRect {
        let width = metrics.width
        let height = targetHeight
        let edge: CGFloat = 12.0

        var x = sourceFrame.maxX - width
        x = min(max(x, safeFrame.minX + edge), safeFrame.maxX - width - edge)

        let belowY = sourceFrame.maxY + 8.0
        let aboveY = sourceFrame.minY - height - 8.0
        let y: CGFloat
        if belowY + height <= safeFrame.maxY - edge {
            y = belowY
        } else if aboveY >= safeFrame.minY + edge {
            y = aboveY
        } else {
            y = min(max(sourceFrame.midY - height * 0.5, safeFrame.minY + edge),
                    safeFrame.maxY - height - edge)
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { dismissAnimated() }

            GlassEffectContainer(spacing: 0) {
                menuSurface
                    .frame(width: expanded ? targetFrame.width : max(sourceFrame.width, 44.0),
                           height: expanded ? targetFrame.height : max(sourceFrame.height, 36.0),
                           alignment: .top)
                    .glassEffect(.regular.interactive(),
                                 in: RoundedRectangle(cornerRadius: expanded ? 26.0 : max(sourceFrame.height, 36.0) * 0.5,
                                                      style: .continuous))
                    .position(x: expanded ? targetFrame.midX : sourceFrame.midX,
                              y: expanded ? targetFrame.midY : sourceFrame.midY)
            }
        }
        .background(Color.clear)
        .onAppear {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                expanded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                withAnimation(.easeOut(duration: 0.16)) { contentVisible = true }
            }
        }
    }

    private var menuSurface: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                if !menuStack.isEmpty {
                    Button {
                        withAnimation(.snappy(duration: 0.20)) { _ = menuStack.popLast() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "chevron.left")
                                .frame(width: 20)
                            Text(currentMenu.title.isEmpty ? "Back" : currentMenu.title)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: metrics.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.horizontal, 12)
                }

                ForEach(Array(elements.enumerated()), id: \.offset) { index, element in
                    elementRow(element)
                    if index < elements.count - 1 {
                        Divider().padding(.leading, 46).padding(.trailing, 12)
                    }
                }
            }
            .padding(.vertical, metrics.verticalPadding)
        }
        .opacity(contentVisible ? 1.0 : 0.0)
        .clipped()
    }

    @ViewBuilder
    private func elementRow(_ element: UIMenuElement) -> some View {
        if let command = element as? UICommand {
            commandRow(command)
        } else if let submenu = element as? UIMenu {
            Button {
                withAnimation(.snappy(duration: 0.20)) { menuStack.append(submenu) }
            } label: {
                HStack(spacing: 10) {
                    leadingImage(submenu.image, selected: false)
                    Text(submenu.title)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: metrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func commandRow(_ command: UICommand) -> some View {
        let disabled = command.attributes.contains(.disabled)
        let destructive = command.attributes.contains(.destructive)
        return Button {
            guard !disabled else { return }
            dispatch(command)
            dismissAnimated()
        } label: {
            HStack(spacing: 10) {
                leadingImage(command.image, selected: command.state == .on)
                Text(command.title)
                    .lineLimit(1)
                    .foregroundStyle(destructive ? Color.red : Color.primary)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .frame(height: metrics.rowHeight)
            .contentShape(Rectangle())
            .opacity(disabled ? 0.38 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    @ViewBuilder
    private func leadingImage(_ image: UIImage?, selected: Bool) -> some View {
        if selected {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 20)
        } else if let image {
            Image(uiImage: image)
                .renderingMode(.template)
                .frame(width: 20)
        } else {
            Color.clear.frame(width: 20, height: 1)
        }
    }

    private func flattenedElements(_ menu: UIMenu) -> [UIMenuElement] {
        var out: [UIMenuElement] = []
        for child in menu.children {
            if let submenu = child as? UIMenu, submenu.options.contains(.displayInline) {
                out.append(contentsOf: flattenedElements(submenu))
            } else {
                out.append(child)
            }
        }
        return out
    }

    private func dispatch(_ command: UICommand) {
        var responder: UIResponder? = source
        while let current = responder {
            if current.responds(to: command.action) {
                UIApplication.shared.sendAction(command.action, to: current, from: command, for: nil)
                return
            }
            responder = current.next
        }
        UIApplication.shared.sendAction(command.action, to: nil, from: command, for: nil)
    }

    private func dismissAnimated() {
        withAnimation(.easeInOut(duration: 0.16)) {
            contentVisible = false
            expanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
            onDismiss()
        }
    }
}
