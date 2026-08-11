import AppKit

struct HoverStatusModel {
    let keepsWorking: Bool?
    let hours: Int?
    let source: ClosedLidForecastSource?
}

final class HoverStatusViewController: NSViewController {
    private let model: HoverStatusModel

    init(model: HoverStatusModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 330, height: 176)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)

        content.addArrangedSubview(makeHeader())
        content.addArrangedSubview(makeForecastCard())
        content.addArrangedSubview(makeHint())

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        ])
        view = root
    }

    private func makeHeader() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 9

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = statusColor.cgColor
        dot.layer?.cornerRadius = 6
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 12),
            dot.heightAnchor.constraint(equalToConstant: 12)
        ])

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.addArrangedSubview(label(statusTitle, size: 14, weight: .semibold))
        labels.addArrangedSubview(label(statusSubtitle, size: 12, color: .secondaryLabelColor))

        row.addArrangedSubview(dot)
        row.addArrangedSubview(labels)
        return row
    }

    private func makeForecastCard() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
        card.layer?.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 76).isActive = true

        let forecast = model.hours.map { "≈ \($0) ч" } ?? "Изучаю…"
        let value = label(forecast, size: model.hours == nil ? 17 : 23, weight: .bold)
        value.translatesAutoresizingMaskIntoConstraints = false

        let explanation = label(
            model.hours == nil ? "Прогноз времени работы" : "работы от батареи\nс закрытой крышкой",
            size: 11,
            color: .secondaryLabelColor
        )
        explanation.maximumNumberOfLines = 2
        explanation.translatesAutoresizingMaskIntoConstraints = false

        let basis = label(forecastBasis, size: 10.5, color: .tertiaryLabelColor)
        basis.maximumNumberOfLines = 2
        basis.lineBreakMode = .byWordWrapping
        basis.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(value)
        card.addSubview(explanation)
        card.addSubview(basis)
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 302),
            value.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            value.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            explanation.leadingAnchor.constraint(equalTo: value.trailingAnchor, constant: 10),
            explanation.centerYAnchor.constraint(equalTo: value.centerYAnchor),
            explanation.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -10),
            basis.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            basis.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            basis.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8)
        ])
        return card
    }

    private func makeHint() -> NSTextField {
        label("Клик — переключить  ·  Правый клик — открыть меню", size: 10.5, color: .tertiaryLabelColor)
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    private var statusColor: NSColor {
        switch model.keepsWorking {
        case true: return .systemGreen
        case false: return .systemYellow
        case nil: return .systemGray
        }
    }

    private var statusTitle: String {
        switch model.keepsWorking {
        case true: return "Работа с закрытой крышкой включена"
        case false: return "Сон при закрытии крышки включён"
        case nil: return "Состояние режима неизвестно"
        }
    }

    private var statusSubtitle: String {
        switch model.keepsWorking {
        case true: return "Mac продолжит работать после закрытия крышки"
        case false: return "Mac уснёт после закрытия крышки"
        case nil: return "Обновите состояние через контекстное меню"
        }
    }

    private var forecastBasis: String {
        switch model.source {
        case .measuredClosed: return "Основа: измерение с закрытой крышкой"
        case .modeledDisplayOff: return "Основа: текущий расход без встроенного экрана"
        case .learnedOnAC: return "Основа: последний расход, изученный на батарее"
        case .baselineOnAC(let watts): return "Основа: базовые \(watts) Вт · уточнится после работы от батареи"
        case nil: return "Основа: ожидаю первый замер энергопотребления"
        }
    }
}
