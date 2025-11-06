import Foundation

final class RealTokenizer {
    struct Config: Decodable { let model_max_length: Int? }
    private let vocab: [String:Int]
    private let id2tok: [Int:String]
    private let bpeRanks: [String:Int]
    private let byteEnc: [UInt8:Character]
    private let byteDec: [Character:UInt8]
    private let pat = try! NSRegularExpression(pattern: #"\'s|\'t|\'re|\'ve|\'m|\'ll|\'d| ?[A-Za-z]+|\d+| ?[^ \r\n\tA-Za-z0-9]+"#, options: [])
    private(set) var pad: Int
    private(set) var eos: Int

    init?(basePath: String) {
        let tokJSON = (basePath as NSString).appendingPathComponent("tokenizer.json")
        let vocabJSON1 = (basePath as NSString).appendingPathComponent("vocab.json")
        let vocabJSON2 = (basePath as NSString).appendingPathComponent("tinygpt2_vocab.json")
        let mergesTXT1 = (basePath as NSString).appendingPathComponent("merges.txt")
        let mergesTXT2 = (basePath as NSString).appendingPathComponent("merges")
        let spMap = (basePath as NSString).appendingPathComponent("special_tokens_map.json")
        let decJSON = (basePath as NSString).appendingPathComponent("token_decoder.json")

        var p = 0, e = 50256
        if let d = try? Data(contentsOf: URL(fileURLWithPath: spMap)),
           let m = try? JSONSerialization.jsonObject(with: d) as? [String:Any] {
            if let id = (m["pad_token"] as? [String:Any])?["id"] as? Int { p = id }
            if let id = (m["eos_token"] as? [String:Any])?["id"] as? Int { e = id }
        }

        var v:[String:Int] = [:]
        var inv:[Int:String] = [:]
        var ranks:[String:Int] = [:]

        if FileManager.default.fileExists(atPath: tokJSON),
           let d = try? Data(contentsOf: URL(fileURLWithPath: tokJSON)),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String:Any],
           let model = o["model"] as? [String:Any],
           let vv = model["vocab"] as? [String:Int],
           let merges = model["merges"] as? [String] {
            v = vv
            for (t,i) in vv { inv[i] = t }
            for (i,m) in merges.enumerated() { ranks[m] = i }
        } else {
            let vocabPath = FileManager.default.fileExists(atPath: vocabJSON1) ? vocabJSON1 : vocabJSON2
            guard FileManager.default.fileExists(atPath: vocabPath),
                  let d = try? Data(contentsOf: URL(fileURLWithPath: vocabPath)),
                  let vv = try? JSONSerialization.jsonObject(with: d) as? [String:Int] else { return nil }
            v = vv
            for (t,i) in vv { inv[i] = t }

            if FileManager.default.fileExists(atPath: mergesTXT1) || FileManager.default.fileExists(atPath: mergesTXT2) {
                let mpath = FileManager.default.fileExists(atPath: mergesTXT1) ? mergesTXT1 : mergesTXT2
                if let s = try? String(contentsOfFile: mpath, encoding: .utf8) {
                    let lines = s.split(separator: "\n").filter { !$0.hasPrefix("#") }
                    for (i,line) in lines.enumerated() { ranks[String(line)] = i }
                }
            } else if FileManager.default.fileExists(atPath: decJSON),
                      let d2 = try? Data(contentsOf: URL(fileURLWithPath: decJSON)),
                      let map = try? JSONSerialization.jsonObject(with: d2) as? [String:String] {
                var invAlt:[Int:String]=[:]
                for (k, tok) in map { if let id = Int(k) { invAlt[id] = tok } }
                if !invAlt.isEmpty { inv = invAlt }
            }
        }

        vocab = v
        id2tok = inv
        bpeRanks = ranks
        pad = p
        eos = e

        var be:[UInt8:Character]=[:], bd:[Character:UInt8]=[:]
        var bs:[UInt8]=[]
        bs += Array(33...126)
        bs += Array(161...172)
        bs += Array(174...255)
        for b in 0...255 {
            if bs.contains(UInt8(b)) {
                let c = Character(UnicodeScalar(b)!)
                be[UInt8(b)] = c
                bd[c] = UInt8(b)
            } else {
                let c = Character(UnicodeScalar(256 + b)!)
                be[UInt8(b)] = c
                bd[c] = UInt8(b)
            }
        }
        byteEnc = be
        byteDec = bd
    }

    private func pairs(_ w:[String]) -> Set<String> {
        var s = Set<String>()
        if w.count < 2 { return s }
        for i in 0..<(w.count-1) { s.insert(w[i] + " " + w[i+1]) }
        return s
    }

    private func bpe(_ token:String) -> [String] {
        if bpeRanks.isEmpty { return [token] }
        var w = Array(token).map { String($0) }
        var ps = pairs(w)
        if ps.isEmpty { return [token] }
        while true {
            var best:String?
            var rank = Int.max
            for p in ps { if let r = bpeRanks[p], r < rank { rank = r; best = p }
            }
            guard let bp = best else { break }
            let a = String(bp.split(separator: " ")[0])
            let b = String(bp.split(separator: " ")[1])
            var i = 0
            var nw:[String]=[]
            while i < w.count {
                if i < w.count-1 && w[i] == a && w[i+1] == b { nw.append(a+b); i += 2 }
                else { nw.append(w[i]); i += 1 }
            }
            w = nw
            if w.count == 1 { break }
            ps = pairs(w)
        }
        return w
    }

    private func encUTF8(_ s:String) -> String {
        var out = ""
        for b in s.utf8 { if let c = byteEnc[b] { out.append(c) } }
        return out
    }

    private func decUTF8(_ s:String) -> String {
        var bytes:[UInt8]=[]
        for c in s { if let b = byteDec[c] { bytes.append(b) } }
        return String(decoding: bytes, as: UTF8.self)
    }

    func encode(_ text:String) -> [Int] {
        var ids:[Int]=[]
        let ns = text as NSString
        let ms = pat.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        for m in ms {
            let t = ns.substring(with: m.range)
            let bt = encUTF8(t)
            let toks = bpe(bt).map { String($0) }
            for tk in toks {
                if let id = vocab[tk] { ids.append(id) }
                else if let id = vocab["Ġ\(tk)"] { ids.append(id) }
            }
        }
        return ids
    }

    func decode(_ tokens:[Int]) -> String {
        var s = ""
        for id in tokens { if let t = id2tok[id] { s.append(t) } }
        s = s.replacingOccurrences(of: "Ġ", with: " ")
        return decUTF8(s)
    }
}
