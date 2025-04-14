import Foundation
import CoreML

class BPETokenizer {
    private let vocab: [String: Int]
    private let merges: [(String, String)]
    private var bpeRanks: [String: Int] = [:]
    private let reverseVocab: [Int: String]

    init?(vocabPath: String, mergesPath: String) {
        guard
            let vocabData = FileManager.default.contents(atPath: vocabPath),
            let vocabDict = try? JSONDecoder().decode([String: Int].self, from: vocabData),
            let mergesContent = try? String(contentsOfFile: mergesPath, encoding: .utf8)
        else {
            print("❌ Failed to load vocab or merges")
            return nil
        }

        self.vocab = vocabDict
        self.reverseVocab = Dictionary(uniqueKeysWithValues: vocabDict.map { ($1, $0) })

        let lines = mergesContent.split(separator: "\n").dropFirst()
        self.merges = lines.map { line in
            let parts = line.split(separator: " ")
            return (String(parts[0]), String(parts[1]))
        }

        for (i, merge) in merges.enumerated() {
            bpeRanks["\(merge.0) \(merge.1)"] = i
        }
    }

    func tokenize(_ text: String) -> [Int] {
        let words = text.components(separatedBy: .whitespaces)
        var tokens: [Int] = []

        for word in words {
            let token = bpe(word)
            for sub in token {
                if let id = vocab[sub] {
                    tokens.append(id)
                } else {
                    tokens.append(vocab["<unk>"] ?? 0)
                }
            }
        }

        return tokens
    }

    func decode(_ tokens: [Int]) -> String {
        let words = tokens.map { reverseVocab[$0] ?? "<unk>" }
        return words.joined().replacingOccurrences(of: "Ġ", with: " ")
    }

    private func bpe(_ token: String) -> [String] {
        var word = Array(token).map { String($0) }
        if word.isEmpty { return [] }

        var pairs = getPairs(word)

        while true {
            let bigram = pairs.min { (a, b) in
                (bpeRanks[a] ?? Int.max) > (bpeRanks[b] ?? Int.max)
            }

            guard let pair = bigram, bpeRanks[pair] != nil else {
                break
            }

            let components = pair.components(separatedBy: " ")
            guard components.count == 2 else { break }
            let first = components[0]
            let second = components[1]

            var newWord: [String] = []
            var i = 0

            while i < word.count {
                if i < word.count - 1, word[i] == first, word[i + 1] == second {
                    newWord.append(first + second)
                    i += 2
                } else {
                    newWord.append(word[i])
                    i += 1
                }
            }

            word = newWord
            pairs = getPairs(word)
        }

        return word
    }

    private func getPairs(_ word: [String]) -> Set<String> {
        var pairs = Set<String>()
        for i in 0..<word.count - 1 {
            pairs.insert("\(word[i]) \(word[i + 1])")
        }
        return pairs
    }
}
