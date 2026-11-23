import Foundation

/// Deterministic post-transcription cleanup. This is the cheap half of what
/// FluidVoice's private model does — fillers, immediate repeats/stutters,
/// leftover unconverted spoken punctuation, and recognizer mid-clause casing
/// noise — without loading a model. Pure, synchronous, runs in microseconds on
/// the dictation finishing path before LocalPunctuationService.
///
/// Ordering contract: runs AFTER SpokenDictationFormatter.applyingSpokenCommands
/// and word substitutions, BEFORE LocalPunctuationService, so the learner's
/// source/accepted pair still records raw ASR input vs final output.
enum DictationCleanup {

    /// Filler interjections the recognizer writes as real words. Whole-token
    /// matching means "um" inside real words can never match.
    private static let fillerWords: Set<String> = [
        "um", "uh", "umm", "uhh", "umh", "uhm", "erm", "err", "er", "ah", "ahh",
        "hmm", "mm", "mmm", "mhm", "huh",
    ]

    /// Multi-word fillers. These only appear as conversational filler; the
    /// component words are never removed individually.
    private static let fillerPhrases: [String] = [
        "you know", "i mean", "uh huh",
    ]

    /// Unambiguous spoken punctuation the command formatter left behind. Words
    /// like "period", "comma", "dot", and "new line" stay literal — the ASR uses
    /// them for real nouns ("tests dot dns") and ambiguous contexts, so only the
    /// forms that can never be ordinary words are converted.
    private static let spokenPunctuation: [(phrase: String, replacement: String)] = [
        ("question mark", "?"),
        ("exclamation mark", "!"),
        ("exclamation point", "!"),
        ("full stop", "."),
    ]

    /// Words before "you know" / "i mean" that make the phrase genuine, not
    /// filler ("do you know…", "did you mean…"). When one of these precedes the
    /// phrase, it is left alone.
    private static let phraseLicensingPredecessors: Set<String> = [
        "do", "did", "does", "can", "could", "will", "would", "shall", "should",
        "may", "might", "must", "let", "lets", "make", "makes", "made", "help",
        "helps", "tell", "tells", "told", "ask", "asks", "asked", "show",
        "shows", "remind", "reminds", "say", "says", "said", "hear", "hears",
        "heard", "see", "sees", "saw", "watch", "watches", "remember",
        "remembers", "forget", "forgets", "want", "wants", "need", "needs",
        "expect", "expects", "hope", "hopes", "bet", "promise", "promises",
        "understand", "understands", "don", "dont", "didn", "didnt",
        "doesn", "doesnt", "cant", "cannot",
    ]

    /// Words after "you know" / "i mean" that make the phrase genuine
    /// ("you know that…", "i mean it", "i mean business").
    private static let phraseLicensingFollowers: Set<String> = [
        "that", "this", "what", "how", "why", "when", "where", "who", "which",
        "if", "whether", "it", "its", "him", "her", "them", "us", "me",
        "business", "literally", "exactly", "precisely", "word", "words",
    ]

    /// Words that legitimately repeat in ordinary speech and must never collapse
    /// ("that that", "very very", "no no").
    private static let repeatAllowlist: Set<String> = [
        "very", "really", "that", "had", "is", "no", "yes", "yeah", "now",
        "so", "bye", "hear", "well", "good", "long", "big",
    ]

    /// Proper nouns and domain words that must keep capitals mid-sentence.
    /// Matches the vocabulary in this dictation history plus universal names.
    private static let casingProtectedWords: Set<String> = [
        "god", "jesus", "christ", "bible",
        "api", "url", "dns", "pdf", "github", "gitlab", "stm", "mac", "macos",
        "ios", "ipados", "watchos", "tvos", "openai", "chatgpt", "claude",
        "anthropic", "google", "gemini", "grok", "openrouter", "ollama",
        "json", "xml", "html", "css", "php", "sql", "mysql", "postgres",
        "postgresql", "mongodb", "sqlite", "http", "https", "ssh", "ftp",
        "vpn", "tcp", "udp", "ip", "ui", "ux", "gpu", "cpu", "ram", "cuda",
        "javascript", "typescript", "python", "swift", "rust", "golang",
        "wordpress", "woocommerce", "shopify", "laravel", "react", "vue",
        "angular", "svelte", "astro", "tailwind", "bootstrap", "jquery",
        "apache", "nginx", "docker", "kubernetes", "aws", "azure", "gcp",
        "cloudflare", "vercel", "netlify", "firebase", "supabase", "stripe",
        "paypal", "github", "gitlab", "bitbucket", "jira", "linear", "notion",
        "slack", "discord", "zoom", "teams", "skype", "whatsapp", "telegram",
        "signal", "spotify", "youtube", "tiktok", "instagram", "facebook",
        "twitter", "reddit", "linkedin", "pinterest", "snapchat",
        "chrome", "safari", "firefox", "edge", "brave", "arc", "opera",
        "windows", "linux", "ubuntu", "debian", "fedora", "android",
        "iphone", "ipad", "airpods", "homepod", "siri", "alexa", "cortana",
        "xcode", "vscode", "terminal", "iterm", "warp", "cursor", "windsurf",
        "raycast", "alfred", "photoshop", "illustrator", "figma", "sketch",
        "excel", "word", "powerpoint", "outlook", "gmail", "docs", "sheets",
        "keynote", "pages", "numbers", "safari", "finder", "imessage",
        "facetime", "airdrop", "icloud", "keychain", "touchid", "faceid",
        "wacom", "logitech", "nvidia", "amd", "intel", "apple", "microsoft",
        "samsung", "sony", "lg", "dell", "hp", "lenovo", "asus", "acer",
        "qwen", "mlx", "llama", "whisper", "parakeet", "nemotron",
        "fluidvoice", "devin", "codex", "copilot", "jitsi", "prosody",
        "termux", "huggingface", "pytorch", "tensorflow", "keras", "numpy",
        "pandas", "scipy", "matplotlib", "jupyter", "anaconda", "homebrew",
        "brew", "npm", "yarn", "pnpm", "pip", "conda", "cargo", "composer",
        "webpack", "vite", "eslint", "prettier", "babel", "jest", "pytest",
        "junit", "selenium", "playwright", "cypress", "puppeteer",
        "grafana", "prometheus", "datadog", "sentry", "bugsnag", "rollbar",
        "twilio", "sendgrid", "mailgun", "postmark", "ses", "sns", "sqs",
        "kafka", "redis", "memcached", "elasticsearch", "solr", "algolia",
        "meilisearch", "typesense", "graphql", "grpc", "rest", "soap",
        "oauth", "jwt", "saml", "ldap", "kerberos", "oauth2", "openid",
        "webp", "jpeg", "png", "gif", "svg", "avif", "heic", "wav", "mp3",
        "mp4", "mov", "avi", "mkv", "webm", "flac", "aac", "ogg",
        "dmg", "zip", "tar", "gz", "rar", "7z", "iso", "exe", "msi", "apk",
        "ipa", "deb", "rpm", "flatpak", "snap", "appimage",
        "covid", "covid-19", "ai", "ml", "llm", "asr", "tts", "stt", "ocr",
        "hud", "dox", "prd", "seo", "gmb", "roi", "kpi", "crm", "erp",
        "saas", "paas", "iaas", "api", "sdk", "ide", "cli", "gui", "tui",
        "os", "sdk", "abi", "isa", "arm", "x86", "risc", "mips",
        "dns", "dhcp", "nat", "vlan", "lan", "wan", "wifi", "ethernet",
        "bluetooth", "nfc", "gps", "led", "lcd", "oled", "amoled",
        "usb", "hdmi", "thunderbolt", "pcie", "nvme", "ssd", "hdd",
        "bios", "uefi", "efi", "acpi", "irq", "dma", "mmu", "tlb",
        "json", "yaml", "toml", "ini", "csv", "tsv", "md", "txt", "rtf",
        "docx", "xlsx", "pptx", "pdf", "epub", "mobi",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
        "sunday", "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december",
        "loreto", "demetre", "neils", "neil", "dents", "mulchtech",
        "whistle", "orca", "herdr", "autobuild", "semantic", "webgpt",
        "speedywatch", "frankenkey", "voicedog", "minijev", "comfy",
        "goblin", "honeybadger", "tailscale", "rustdesk", "proxmox",
        "hosthatch", "digitalocean", "linode", "vultr", "hetzner",
        "massiveorganic", "seotimemachines", "aussie", "australia",
        "american", "british", "english", "french", "german", "spanish",
        "italian", "chinese", "japanese", "korean", "russian", "indian",
    ]

    /// Every English word the ASR has been observed capitalizing mid-clause.
    /// Only words on this list are ever lowercased, and only when they are not
    /// the first word after a sentence terminator — so "And if there…" starting
    /// a real sentence keeps its cap, but "connect To the site" loses it.
    private static let midClauseLowerable: Set<String> = [
        // function words
        "the", "a", "an", "and", "but", "or", "nor", "so", "yet", "for",
        "if", "as", "at", "by", "in", "of", "on", "to", "up", "we", "it",
        "is", "are", "am", "was", "were", "be", "been", "being", "do", "does",
        "did", "done", "doing", "have", "has", "had", "having",
        "can", "could", "will", "would", "shall", "should", "may", "might",
        "must", "ought",
        "you", "your", "yours", "he", "him", "his", "she", "her", "hers",
        "its", "they", "them", "their", "theirs", "we", "us", "our", "ours",
        "me", "my", "mine", "who", "whom", "whose", "which", "that", "these",
        "those", "this", "what", "when", "where", "why", "how", "all", "any",
        "both", "each", "few", "more", "most", "other", "some", "such",
        "only", "own", "same", "than", "too", "very", "just", "now", "then",
        "here", "there", "once", "twice", "also", "still", "even", "ever",
        "never", "always", "often", "sometimes", "usually", "really",
        "quite", "rather", "pretty", "almost", "nearly", "barely", "hardly",
        "not", "no", "yes", "yeah", "okay", "ok", "well", "right", "sure",
        "maybe", "perhaps", "probably", "possibly", "actually", "basically",
        "literally", "honestly", "frankly", "obviously", "clearly",
        "hopefully", "luckily", "unfortunately", "sadly", "happily",
        "meanwhile", "otherwise", "instead", "anyway", "anyways", "besides",
        "moreover", "furthermore", "therefore", "thus", "hence", "however",
        "nevertheless", "nonetheless", "regardless", "consequently",
        "accordingly", "subsequently", "previously", "recently", "currently",
        "presently", "immediately", "eventually", "finally", "lastly",
        "first", "second", "third", "fourth", "fifth", "next", "last",
        "again", "back", "away", "out", "off", "down", "over", "under",
        "around", "through", "across", "along", "above", "below", "between",
        "among", "within", "without", "inside", "outside", "behind", "beyond",
        "beside", "near", "toward", "towards", "upon", "onto", "into",
        "unto", "per", "via", "versus", "vs", "etc", "ie", "eg",
        "let", "lets", "make", "makes", "made", "making", "take", "takes",
        "took", "taken", "taking", "get", "gets", "got", "gotten", "getting",
        "give", "gives", "gave", "given", "giving", "go", "goes", "went",
        "gone", "going", "come", "comes", "came", "coming", "see", "sees",
        "saw", "seen", "seeing", "know", "knows", "knew", "known", "knowing",
        "think", "thinks", "thought", "thinking", "say", "says", "said",
        "saying", "tell", "tells", "told", "telling", "ask", "asks", "asked",
        "asking", "want", "wants", "wanted", "wanting", "need", "needs",
        "needed", "needing", "use", "uses", "used", "using", "find", "finds",
        "found", "finding", "put", "puts", "putting", "mean", "means",
        "meant", "meaning", "keep", "keeps", "kept", "keeping", "start",
        "starts", "started", "starting", "stop", "stops", "stopped",
        "stopping", "try", "tries", "tried", "trying", "call", "calls",
        "called", "calling", "look", "looks", "looked", "looking", "work",
        "works", "worked", "working", "run", "runs", "ran", "running",
        "move", "moves", "moved", "moving", "live", "lives", "lived",
        "living", "believe", "believes", "believed", "hold", "holds", "held",
        "holding", "bring", "brings", "brought", "bringing", "happen",
        "happens", "happened", "happening", "write", "writes", "wrote",
        "written", "writing", "sit", "sits", "sat", "sitting", "stand",
        "stands", "stood", "standing", "lose", "loses", "lost", "losing",
        "pay", "pays", "paid", "paying", "meet", "meets", "met", "meeting",
        "include", "includes", "included", "including", "continue",
        "continues", "continued", "continuing", "set", "sets", "setting",
        "learn", "learns", "learned", "learning", "change", "changes",
        "changed", "changing", "lead", "leads", "led", "leading",
        "understand", "understands", "understood", "understanding", "watch",
        "watches", "watched", "watching", "follow", "follows", "followed",
        "following", "create", "creates", "created", "creating", "speak",
        "speaks", "spoke", "spoken", "speaking", "read", "reads", "reading",
        "allow", "allows", "allowed", "allowing", "add", "adds", "added",
        "adding", "spend", "spends", "spent", "spending", "grow", "grows",
        "grew", "grown", "growing", "open", "opens", "opened", "opening",
        "walk", "walks", "walked", "walking", "win", "wins", "won",
        "winning", "offer", "offers", "offered", "offering", "remember",
        "remembers", "remembered", "remembering", "love", "loves", "loved",
        "loving", "consider", "considers", "considered", "considering",
        "appear", "appears", "appeared", "appearing", "buy", "buys",
        "bought", "buying", "wait", "waits", "waited", "waiting", "serve",
        "serves", "served", "serving", "die", "dies", "died", "dying",
        "send", "sends", "sent", "sending", "expect", "expects", "expected",
        "expecting", "build", "builds", "built", "building", "stay", "stays",
        "stayed", "staying", "fall", "falls", "fell", "fallen", "falling",
        "cut", "cuts", "cutting", "reach", "reaches", "reached", "reaching",
        "kill", "kills", "killed", "killing", "remain", "remains",
        "remained", "remaining", "suggest", "suggests", "suggested",
        "suggesting", "raise", "raises", "raised", "raising", "pass",
        "passes", "passed", "passing", "sell", "sells", "sold", "selling",
        "require", "requires", "required", "requiring", "report", "reports",
        "reported", "reporting", "decide", "decides", "decided", "deciding",
        "pull", "pulls", "pulled", "pulling", "explain", "explains",
        "explained", "explaining", "hope", "hopes", "hoped", "hoping",
        "develop", "develops", "developed", "developing", "carry", "carries",
        "carried", "carrying", "break", "breaks", "broke", "broken",
        "breaking", "receive", "receives", "received", "receiving", "agree",
        "agrees", "agreed", "agreeing", "support", "supports", "supported",
        "supporting", "hit", "hits", "hitting", "produce", "produces",
        "produced", "producing", "eat", "eats", "ate", "eaten", "eating",
        "cover", "covers", "covered", "covering", "catch", "catches",
        "caught", "catching", "draw", "draws", "drew", "drawn", "drawing",
        "choose", "chooses", "chose", "chosen", "choosing",
        // common dictation-domain words observed capitalized mid-clause
        "already", "possible", "getting", "ends", "with", "finally",
        "because", "about", "before", "after", "while", "until", "unless",
        "though", "although", "whether", "since", "once", "during",
        "another", "anything", "everything", "something", "nothing",
        "anyone", "everyone", "someone", "anywhere", "everywhere",
        "somewhere", "nowhere", "anytime", "everytime", "sometime",
        "thing", "things", "stuff", "lot", "lots", "bit", "kind", "sort",
        "part", "parts", "way", "ways", "time", "times", "day", "days",
        "week", "weeks", "month", "months", "year", "years", "minute",
        "minutes", "hour", "hours", "second", "seconds", "moment", "moments",
        "place", "places", "case", "cases", "point", "points", "fact",
        "facts", "idea", "ideas", "question", "questions", "answer",
        "answers", "problem", "problems", "issue", "issues", "example",
        "examples", "reason", "reasons", "result", "results", "change",
        "changes", "check", "checks", "test", "tests", "file", "files",
        "folder", "folders", "page", "pages", "site", "sites", "link",
        "links", "list", "lists", "item", "items", "text", "texts", "word",
        "words", "sentence", "sentences", "line", "lines", "note", "notes",
        "copy", "copies", "paste", "pasted", "message", "messages",
    ]

    /// Filler phrase → nothing. Filler words handled per-token.
    static func cleaningContent(
        _ text: String,
        fillersEnabled: Bool = true,
        repeatsEnabled: Bool = true,
        punctuationEnabled: Bool = true,
        casingEnabled: Bool = true
    ) -> String {
        var result = text

        if punctuationEnabled {
            result = convertingSpokenPunctuation(result)
        }
        if fillersEnabled {
            result = removingFillers(result)
        }
        if repeatsEnabled {
            result = collapsingRepeats(result)
        }
        if casingEnabled {
            result = normalizingMidClauseCase(result)
        }
        result = tidyingSpaces(result)
        return result
    }

    // MARK: - Spoken punctuation leftovers

    private static func convertingSpokenPunctuation(_ text: String) -> String {
        var result = text
        for (phrase, replacement) in spokenPunctuation {
            let pattern = "(?i)(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: phrase))(?![\\p{L}\\p{N}])"
            result = replacingMatches(in: result, pattern: pattern) { _ in replacement }
        }
        return result
    }

    // MARK: - Fillers

    private static func removingFillers(_ text: String) -> String {
        let words = wordTokens(text)
        let ns = text as NSString
        var removals: [NSRange] = []

        // Multi-word phrases first: only when no licensing neighbour proves the
        // phrase is a real clause ("do you know…", "i mean it").
        for phrase in fillerPhrases {
            let parts = phrase.components(separatedBy: " ")
            guard !parts.isEmpty else { continue }
            let first = parts[0]

            for index in words.indices {
                guard words[index].text.lowercased() == first else { continue }
                // Require the following tokens to match the phrase tail.
                var matched = true
                for offset in 1..<parts.count {
                    guard index + offset < words.count else { matched = false; break }
                    if words[index + offset].text.lowercased() != parts[offset] {
                        matched = false
                        break
                    }
                    let gapRange = NSRange(
                        location: NSMaxRange(words[index + offset - 1].range),
                        length: words[index + offset].range.location -
                                NSMaxRange(words[index + offset - 1].range)
                    )
                    let gap = ns.substring(with: gapRange)
                    // Hyphenated "uh-huh" tokenizes as two words; a bare hyphen
                    // or apostrophe between them still means one phrase.
                    if !(onlyWhitespace(gap) || gap == "-" || gap == "‑" || gap == "‐" || gap == "'") {
                        matched = false
                        break
                    }
                }
                guard matched else { continue }
                let endIndex = index + parts.count - 1
                if index > 0,
                   phraseLicensingPredecessors.contains(words[index - 1].text.lowercased()) {
                    continue
                }
                if endIndex + 1 < words.count,
                   phraseLicensingFollowers.contains(words[endIndex + 1].text.lowercased()) {
                    continue
                }
                removals.append(
                    NSRange(location: words[index].range.location,
                            length: NSMaxRange(words[endIndex].range) - words[index].range.location)
                )
            }
        }

        // Single-word fillers with an attached comma.
        for index in stride(from: words.count - 1, through: 0, by: -1) {
            let word = words[index]
            guard fillerWords.contains(word.text.lowercased()) else { continue }
            var span = word.range
            if span.location + span.length < ns.length {
                let next = ns.substring(with: NSRange(location: span.location + span.length, length: 1))
                if next == "," { span.length += 1 }
            }
            if span.location > 0 {
                let prev = ns.substring(with: NSRange(location: span.location - 1, length: 1))
                if prev == "," { span.location -= 1; span.length += 1 }
            }
            // Skip if a phrase removal already covers this span.
            if removals.contains(where: { NSIntersectionRange($0, span).length > 0 }) { continue }
            removals.append(span)
        }

        // Apply deepest-last so earlier deletions never shift later offsets;
        // skip ranges nested inside an already-applied one.
        let ordered = removals.sorted { $0.location > $1.location }
        var applied: [NSRange] = []
        let rebuilt = NSMutableString(string: text)
        for range in ordered {
            guard !applied.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { continue }
            rebuilt.replaceCharacters(in: range, with: "")
            applied.append(range)
        }
        // Restore a leading capital when the deleted filler carried it
        // ("Um, hey there" -> "Hey there").
        let result = rebuilt as String
        if let first = text.first, first.isUppercase,
           let start = result.firstIndex(where: { $0.isLetter }) {
            let tail = String(result[start...])
            return String(tail.prefix(1)).uppercased() + tail.dropFirst()
        }
        return result
    }

    // MARK: - Immediate repeats (stutters)

    private static func collapsingRepeats(_ text: String) -> String {
        let words = wordTokens(text)
        guard words.count > 1 else { return text }
        let ns = text as NSString
        var removals: [NSRange] = []
        var i = words.count - 1
        while i >= 1 {
            // Multi-word stutter: try widest window (4,3,2) first.
            var collapsed = false
            for window in stride(from: 4, through: 2, by: -1) {
                guard i >= window * 2 - 1 else { continue }
                var matches = true
                for k in 0..<window {
                    let a = words[i - 2 * window + 1 + k].text
                    let b = words[i - window + 1 + k].text
                    if a.lowercased() != b.lowercased() { matches = false; break }
                }
                if matches {
                    let start = words[i - window + 1].range.location
                    let end = NSMaxRange(words[i].range)
                    removals.append(NSRange(location: start, length: end - start))
                    i -= window * 2 - 1
                    collapsed = true
                    break
                }
            }
            guard !collapsed else { continue }
            let current = words[i], previous = words[i - 1]
            if current.text.lowercased() == previous.text.lowercased(),
               !repeatAllowlist.contains(current.text.lowercased()) {
                removals.append(current.range)
            }
            i -= 1
        }
        let rebuilt = NSMutableString(string: text)
        for range in removals.sorted(by: { $0.location > $1.location }) {
            rebuilt.replaceCharacters(in: range, with: "")
        }
        return rebuilt as String
    }

    // MARK: - Mid-clause casing

    private static func normalizingMidClauseCase(_ text: String) -> String {
        let words = wordTokens(text)
        guard words.count > 1 else { return text }
        let ns = text as NSString
        let rebuilt = NSMutableString(string: text)
        for index in stride(from: words.count - 1, through: 1, by: -1) {
            let word = words[index]
            let lowered = word.text.lowercased()
            guard word.text.first?.isUppercase == true,
                  word.text.count > 1,
                  lowered != "i",
                  !casingProtectedWords.contains(lowered),
                  midClauseLowerable.contains(lowered) else { continue }
            // Only lowercase when the previous visible character is not a
            // sentence terminator and not an opening quote/paren right after one.
            var location = word.range.location
            var sawContent = false
            while location > 0 {
                let scalar = ns.character(at: location - 1)
                guard let unicode = UnicodeScalar(scalar) else { break }
                if unicode == " " || unicode == "\t" || unicode == "\r" || unicode == "\n" {
                    location -= 1
                    continue
                }
                if unicode == "\"" || unicode == "'" || unicode == "(" || unicode == "[" ||
                   unicode == "“" || unicode == "‘" || unicode == "”" || unicode == "’" {
                    location -= 1
                    continue
                }
                if unicode == "." || unicode == "!" || unicode == "?" || unicode == "…" {
                    sawContent = false
                    break
                }
                sawContent = true
                break
            }
            guard sawContent else { continue }
            rebuilt.replaceCharacters(in: word.range, with: lowered)
        }
        return rebuilt as String
    }

    // MARK: - Shared helpers

    private static func wordTokens(_ text: String) -> [(text: String, range: NSRange)] {
        guard let expression = try? NSRegularExpression(pattern: "[\\p{L}\\p{N}']+") else { return [] }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: fullRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return (String(text[range]), match.range)
        }
    }

    private static func replacingMatches(
        in text: String,
        pattern: String,
        transform: (String) -> String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let result = NSMutableString(string: text)
        let matches = expression.matches(
            in: text,
            range: NSRange(location: 0, length: ns.length)
        ).reversed()
        for match in matches {
            let original = ns.substring(with: match.range)
            result.replaceCharacters(in: match.range, with: transform(original))
        }
        return result as String
    }

    /// Template-based replacement for patterns with capture groups. The
    /// closure variant would insert a literal "$1" instead of the group.
    private static func replacingTemplate(
        in text: String,
        pattern: String,
        template: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: template
        )
    }

    private static func tidyingSpaces(_ text: String) -> String {
        var result = replacingMatches(in: text, pattern: "[ \\t]{2,}") { _ in " " }
        result = replacingTemplate(in: result, pattern: "[ \\t]+([,.;:!?…’)\"])", template: "$1")
        result = replacingTemplate(in: result, pattern: "([“(])[ \\t]+", template: "$1")
        result = replacingMatches(in: result, pattern: "[ \\t]+\\n") { _ in "\n" }
        result = replacingMatches(in: result, pattern: "\\n[ \\t]+") { _ in "\n" }
        result = replacingMatches(in: result, pattern: "\\n{3,}") { _ in "\n\n" }
        // Leading comma/period left behind by a deleted leading filler.
        result = replacingMatches(in: result, pattern: "^[ \\t]*[,;]\\s*") { _ in "" }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func onlyWhitespace(_ text: String) -> Bool {
        text.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\r" || $0 == "\n" }
    }
}
