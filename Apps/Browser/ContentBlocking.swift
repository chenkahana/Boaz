import WebKit

/// Ad and tracker blocking, on by default. Two bundled `WKContentRuleList`s, attached to every page
/// (incognito included) when `Preferences.blockTrackers` is on; nothing is downloaded at runtime:
/// - EasyList (`easylist_min_content_blocker.json`, the WebKit build from easylist-downloads.adblockplus.org):
///   ad servers plus element hiding. Compiled once per bundled version, then loaded from WebKit's store.
/// - `domains` below: Boaz's own list of tracking and analytics hosts, which the min EasyList doesn't cover.
enum ContentBlocking {
    /// Change when the bundled EasyList file is replaced, so its compiled copy is rebuilt.
    static let easyListVersion = "2025-05-27.3"
    private static let ownIdentifier = "BoazAdBlock"
    private static let easyListPrefix = "BoazEasyList-"

    @MainActor private static var cached: [WKContentRuleList]?
    @MainActor private static var compiling: Task<[WKContentRuleList], Never>?

    @MainActor
    static func compiledLists() async -> [WKContentRuleList] {
        if let cached { return cached }
        if let compiling { return await compiling.value }
        let task = Task<[WKContentRuleList], Never> {
            async let own = ownList()
            async let easy = easyList()
            return [await own, await easy].compactMap { $0 }
        }
        compiling = task
        let lists = await task.value
        cached = lists
        compiling = nil
        return lists
    }

    @MainActor
    private static func ownList() async -> WKContentRuleList? {
        try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: ownIdentifier,
                                                                         encodedContentRuleList: ruleListJSON)
    }

    /// ~27k rules take seconds to compile, so the compiled list is looked up first and only built when missing.
    @MainActor
    private static func easyList() async -> WKContentRuleList? {
        guard let store = WKContentRuleListStore.default() else { return nil }
        let identifier = easyListPrefix + easyListVersion
        if let list = try? await store.contentRuleList(forIdentifier: identifier) { return list }
        for old in await store.availableIdentifiers() ?? [] where old.hasPrefix(easyListPrefix) {
            try? await store.removeContentRuleList(forIdentifier: old)
        }
        guard let url = Bundle.main.url(forResource: "easylist_min_content_blocker", withExtension: "json"),
              let json = await Task.detached(operation: { webKitCompatible(url) }).value
        else { return nil }
        return try? await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json)
    }

    /// EasyList with the element-hiding rules WebKit can't parse removed: Adblock's extended selectors
    /// (`:has-text(…)`, `:-abp-…`) and style injections (`sel {…}`) aren't selectors, and WebKit joins hiding
    /// selectors into shared style rules,
    /// so one of them would switch off hiding for every selector it's grouped with.
    nonisolated private static func webKitCompatible(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let extended = [":has-text(", ":-abp-", ":contains(", ":xpath(", ":matches-css", ":upward(", ":remove(",
                        ":style(", ":matches-path(", ":min-text-length(", ":watch-attr(", "[-ext-", "{"]
        let kept = rules.compactMap { rule -> [String: Any]? in
            if let selector = (rule["action"] as? [String: Any])?["selector"] as? String,
               extended.contains(where: selector.contains) { return nil }
            return withoutEmptyDomains(rule)
        }
        return (try? JSONSerialization.data(withJSONObject: kept)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// The published list has a site pattern with no domain (`…([^/]+\.)?[^\.][/:]?`), which matches every URL.
    /// It sits in an exception that switches off all earlier rules on 88 sites, so it switched them off everywhere.
    /// Drops such patterns, and the rule itself if they were all it had.
    nonisolated private static func withoutEmptyDomains(_ rule: [String: Any]) -> [String: Any]? {
        guard var trigger = rule["trigger"] as? [String: Any] else { return rule }
        for key in ["if-top-url", "unless-top-url", "if-frame-url", "unless-frame-url"] {
            guard let patterns = trigger[key] as? [String] else { continue }
            let valid = patterns.filter { !$0.contains(#"\.)?[^\.]"#) }
            if valid.isEmpty { return nil }
            trigger[key] = valid
        }
        var rule = rule
        rule["trigger"] = trigger
        return rule
    }

    /// One rule per domain. WKContentRuleList's `url-filter` regex dialect has no disjunction
    /// (`(a|b)` fails to compile with "Disjunctions are not supported yet"), so domains can't be
    /// grouped into a single pattern — each gets its own simple anchored rule instead.
    private static var ruleListJSON: String {
        let rules = domains.map { domain -> [String: Any] in
            let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
            let pattern = "^https?://([a-z0-9-]+\\.)*" + escaped + "/?.*"
            return [
                "trigger": ["url-filter": pattern, "url-filter-is-case-sensitive": false, "load-type": ["third-party"]],
                "action": ["type": "block"],
            ]
        }
        let data = try? JSONSerialization.data(withJSONObject: rules)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    /// Common ad-serving, analytics and tracking hosts. Deliberately broad categories, not a
    /// reproduction of any third-party curated list. Leaves out hosts that sites need to work when loaded
    /// third-party (link shorteners, CDNs for their own assets, comment and chat widgets).
    private static let domains: [String] = [
        // Google ads / analytics
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com",
        "googletagmanager.com", "googletagservices.com", "adservice.google.com", "pagead2.googlesyndication.com",
        "google-analytics.de", "urchin.com", "googleoptimize.com", "googleoptimization.com",
        // Meta / social trackers
        "connect.facebook.net", "facebook.net", "pixel.facebook.com", "ads-api.twitter.com",
        "analytics.twitter.com", "ads-twitter.com", "static.ads-twitter.com", "sc-static.net",
        "snap.licdn.com", "px.ads.linkedin.com", "analytics.pinterest.com", "ct.pinterest.com",
        // Major ad exchanges / networks
        "adnxs.com", "adsrvr.org", "advertising.com", "adtechus.com", "criteo.com", "criteo.net",
        "outbrain.com", "taboola.com", "scorecardresearch.com", "quantserve.com", "quantcount.com",
        "moatads.com", "rubiconproject.com", "pubmatic.com", "openx.net", "openx.com", "casalemedia.com",
        "contextweb.com", "bidswitch.net", "smartadserver.com", "adform.net", "adroll.com", "bluekai.com",
        "exelator.com", "mathtag.com", "turn.com", "agkn.com", "media6degrees.com", "demdex.net",
        "krxd.net", "tapad.com", "yieldmo.com", "sharethrough.com", "triplelift.com", "indexexchange.com",
        "sovrn.com", "lijit.com", "gumgum.com", "teads.tv", "smartclip.net", "adcolony.com", "applovin.com",
        "vungle.com", "chartboost.com", "inmobi.com", "mopub.com", "flashtalking.com", "bidvertiser.com",
        "revcontent.com", "mgid.com", "content.ad", "adblade.com", "zedo.com", "adsymptotic.com",
        "simpli.fi", "rlcdn.com", "eyeota.net", "mezzobit.com", "towerdata.com", "crwdcntrl.net",
        "adtech.de", "adtechjp.com", "serving-sys.com", "adbrite.com", "undertone.com", "springserve.com",
        "spotxchange.com", "freewheel.tv", "improvedigital.com", "33across.com", "aniview.com",
        "adkernel.com", "adyoulike.com", "amazon-adsystem.com", "ad.atdmt.com", "atdmt.com",
        "bannerconnect.net", "bidtheatre.com", "conversantmedia.com", "districtm.io", "emxdgt.com",
        "gammaplatform.com", "ibillboard.com", "iponweb.net", "loopme.com", "nativo.com",
        "onetag-sys.com", "pixfuture.com", "pulsepoint.com", "rfihub.com", "richaudience.com",
        "sonobi.com", "stickyadstv.com", "synacor.com", "tremorhub.com", "unrulymedia.com",
        "videoplaza.com", "yldbt.com", "zemanta.com", "yieldlab.net", "adtriba.com", "adform.com",
        // Analytics / session replay / heatmaps
        "hotjar.com", "mixpanel.com", "segment.io", "segment.com", "amplitude.com", "fullstory.com",
        "mouseflow.com", "crazyegg.com", "optimizely.com", "clicktale.net", "heap.io", "heapanalytics.com",
        "clarity.ms", "sessioncam.com", "luckyorange.com", "inspectlet.com", "smartlook.com",
        "mathtag.net", "statcounter.com", "histats.com", "clustrmaps.com", "woopra.com", "kissmetrics.com",
        "chartbeat.com", "chartbeat.net", "parsely.com", "newrelic.com", "nr-data.net",
        // Mobile attribution / ad SDKs
        "branch.io", "adjust.com", "appsflyer.com", "kochava.com", "singular.net", "tune.com",
        "leanplum.com", "airbridge.io", "apptimize.com", "clevertap.com", "braze.com", "iterable.com",
        "onesignal.com", "urbanairship.com", "pushwoosh.com",
        // Data brokers / identity graphs
        "acxiom.com", "liveramp.com", "neustar.biz", "effectivemeasure.net", "comscore.com",
        "nielsen.com", "oracle-infinity.com", "bluecava.com", "exponential.com", "drawbridge.com",
        "adsafeprotected.com", "doubleverify.com", "integralads.com", "moatpixel.com",
        // Misc widget / tracker pixels
        "addthis.com", "sharethis.com", "hs-analytics.net",
        "hs-scripts.com", "hsadspixel.net", "trackjs.com", "bugsnag.com",
        "sentry-cdn.com", "sentry.io", "fastclick.net", "bluesoft.us", "yottaa.net", "yottaa.com",
        "cloudfront-trackers.com", "trafficjunky.net", "exoclick.com", "propellerads.com",
        "popads.net", "adcash.com", "clickadu.com", "trafficfactory.biz", "juicyads.com",
        "ero-advertising.com", "plugrush.com", "adxpansion.com", "trellian.com", "yesadvertising.com",
        "zergnet.com", "nativeads.com", "contentad.net", "adsterra.com", "hilltopads.net",
        "monetizemore.com", "mediavine.com", "ezoic.net", "ezodn.com", "sovrn.io", "pbstck.com",
        "pingdom.net", "fout.jp", "cedexis.com", "cedexis.net", "krux.com", "permutive.com",
        "permutive.app", "cxense.com", "chartboost.net", "vidible.tv", "connatix.com",
        "adsafeprotected.net", "mfadsrvr.com", "adspeed.com", "adspeed.net", "exdynsrv.com",
        "yllix.com", "a-ads.com", "coinzilla.com", "cointraffic.io", "media.net", "skimresources.com",
        "shareasale.com", "cj.com", "linksynergy.com", "rewardstyle.com", "avantlink.com",
        "pntra.com", "pntrac.com", "pntrs.com", "awin1.com", "webgains.com", "tradedoubler.com",
        "impact-ad.jp", "impactradius.com", "flashtalking.net", "ad-score.com", "adscore.com",
        "clickagy.com", "clickcease.com", "clicktripz.com", "bounceexchange.com", "bouncex.net",
        "qualtrics.com", "medallia.com", "foresee.com", "verint.com", "usersnap.com",
    ]
}
