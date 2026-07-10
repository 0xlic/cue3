import Foundation

struct CueOutputFormatter {
    static let cuePlaceholder = "{{Cue}}"
    static let defaultPrompt = """
    下面的内容是我标记的重点内容，以及我自己的批注：

    {{Cue}}
    """

    struct Item: Equatable {
        let quoteText: String
        let annotationText: String?
    }

    func format(items: [Item]) -> String {
        items
            .map { item in
                var lines = [item.quoteText]
                if let annotation = item.annotationText, !annotation.isEmpty {
                    lines.append("批注：\(annotation)")
                }
                return lines.joined(separator: "\n")
            }
            .joined(separator: "\n\n")
    }

    func applyTemplate(
        _ template: String,
        placeholder: String,
        to output: String
    ) -> String {
        if template.contains(placeholder) {
            return template.replacingOccurrences(of: placeholder, with: output)
        }

        return """
        \(template)

        \(output)
        """
    }
}
