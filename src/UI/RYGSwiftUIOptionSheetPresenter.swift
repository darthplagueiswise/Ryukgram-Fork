import SwiftUI
import UIKit

/// SwiftUI presentation owner for RyukGram option sheets on iOS 26+.
/// Standard NavigationStack/List/toolbar components inherit the system Liquid
/// Glass design automatically; no duplicate blur/material is layered on top.
@objcMembers
public final class RYGSwiftUIOptionSheetPresenter: NSObject {
    @objc(presentFrom:title:defaultsKey:options:onChange:)
    public static func present(
        from presenter: UIViewController,
        title: NSString,
        defaultsKey: NSString?,
        options: NSArray,
        onChange: ((NSString) -> Void)?
    ) {
        guard #available(iOS 26.0, *) else { return }

        let normalized: [[String: String]] = options.compactMap { element in
            guard let raw = element as? NSDictionary else { return nil }
            var value: [String: String] = [:]
            for (key, object) in raw {
                guard let key = key as? String else { continue }
                if let string = object as? String { value[key] = string }
            }
            return value
        }

        let root = RYGSwiftUIOptionSheetView(
            sheetTitle: title as String,
            defaultsKey: defaultsKey as String?,
            options: normalized,
            onChange: { value in onChange?(value as NSString) }
        )
        let host = UIHostingController(rootView: root)
        host.modalPresentationStyle = .pageSheet
        presenter.present(host, animated: true)
    }
}

@available(iOS 26.0, *)
private struct RYGSwiftUIOptionSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let sheetTitle: String
    let defaultsKey: String?
    let options: [[String: String]]
    let onChange: (String) -> Void

    @State private var selectedValue: String

    init(
        sheetTitle: String,
        defaultsKey: String?,
        options: [[String: String]],
        onChange: @escaping (String) -> Void
    ) {
        self.sheetTitle = sheetTitle
        self.defaultsKey = defaultsKey
        self.options = options
        self.onChange = onChange
        let saved = defaultsKey.flatMap { UserDefaults.standard.string(forKey: $0) } ?? ""
        _selectedValue = State(initialValue: saved)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    optionRow(option)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func optionRow(_ option: [String: String]) -> some View {
        let value = option["value"] ?? ""
        let title = option["title"] ?? value
        let detail = option["description"] ?? ""

        Button {
            selectedValue = value
            if let defaultsKey, !defaultsKey.isEmpty {
                UserDefaults.standard.set(value, forKey: defaultsKey)
            }
            onChange(value)
            dismiss()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                if value == selectedValue {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
