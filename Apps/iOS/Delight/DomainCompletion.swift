import Foundation

/// Inline address completion: hosts from the user's history first, then a bundled list of popular domains.
enum DomainCompletion {
    /// Returns the full host the typed text completes to ("git" → "github.com"), or nil.
    static func complete(_ typed: String, historyHosts: [String]) -> String? {
        let query = Self.query(typed)
        guard !query.isEmpty, !query.contains(" "), !query.contains("/") else { return nil }
        let typedWWW = query.hasPrefix("www.")
        for candidate in historyHosts.map(normalized) + topDomains {
            let host = typedWWW ? "www." + candidate : candidate
            if host.count > query.count, host.hasPrefix(query) { return host }
        }
        return nil
    }

    /// What the user typed, lowercased, without a scheme.
    static func query(_ typed: String) -> String {
        var query = typed.trimmingCharacters(in: .whitespaces).lowercased()
        for prefix in ["https://", "http://"] where query.hasPrefix(prefix) { query.removeFirst(prefix.count) }
        return query
    }

    private static func normalized(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }

    /// Roughly by global popularity, so the most likely completion wins.
    static let topDomains = [
        "google.com", "youtube.com", "facebook.com", "instagram.com", "wikipedia.org", "x.com", "twitter.com",
        "reddit.com", "amazon.com", "whatsapp.com", "chatgpt.com", "claude.ai", "tiktok.com", "linkedin.com",
        "yahoo.com", "netflix.com", "bing.com", "live.com", "microsoft.com", "office.com", "github.com",
        "apple.com", "icloud.com", "openai.com", "pinterest.com", "twitch.tv", "discord.com", "duckduckgo.com",
        "ebay.com", "spotify.com", "zoom.us", "weather.com", "cnn.com", "nytimes.com", "bbc.com", "bbc.co.uk",
        "theguardian.com", "espn.com", "imdb.com", "paypal.com", "dropbox.com", "notion.so", "figma.com",
        "slack.com", "stackoverflow.com", "medium.com", "quora.com", "tumblr.com", "wordpress.com", "craigslist.org",
        "etsy.com", "walmart.com", "target.com", "bestbuy.com", "ikea.com", "booking.com", "airbnb.com",
        "tripadvisor.com", "expedia.com", "maps.google.com", "mail.google.com", "drive.google.com", "docs.google.com",
        "news.ycombinator.com", "arc.net", "theverge.com", "wired.com", "techcrunch.com", "arstechnica.com",
        "bloomberg.com", "reuters.com", "wsj.com", "washingtonpost.com", "forbes.com", "cnbc.com", "npr.org",
        "developer.apple.com", "swift.org", "gitlab.com", "vercel.com", "cloudflare.com", "aws.amazon.com",
        "hulu.com", "disneyplus.com", "max.com", "primevideo.com", "soundcloud.com", "bandcamp.com", "vimeo.com",
        "goodreads.com", "substack.com", "producthunt.com", "dribbble.com", "behance.net", "canva.com",
        "duolingo.com", "khanacademy.org", "coursera.org", "udemy.com", "archive.org", "zillow.com", "yelp.com",
        "uber.com", "doordash.com", "instacart.com", "shopify.com", "aliexpress.com", "temu.com", "nike.com",
    ]
}
