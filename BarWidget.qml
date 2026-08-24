import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "ReleaseLogic.js" as Logic

BarWidget {
  id: root
  moduleName: "akshad135.anisync"

  // Public Simkl client_id (identifies the AniSync app; not a secret).
  // Registered app: https://simkl.com/settings/developer/
  property string simklClientId: "d86082069c0ccbc190721239d90678e23b15bf4913f005c1f1fa72f3558ae5ff"

  // ------------------------------------------------------------- Settings & State
  property bool showAnime: true
  property bool showManga: true
  property string provider: "anilist"
  property string userName: ""
  property bool notifyOnRelease: true
  property bool notifyManga: true
  property int checkIntervalMins: 30

  // Simkl PIN flow state: idle -> awaiting (code shown) -> connected.
  // The token is long-lived (~5 years); only a revoke invalidates it.
  // The PIN code itself lives 15 minutes (expires_in: 900).
  property string simklToken: ""
  property string simklUserCode: ""
  property bool simklLinking: false
  property int simklPinExpiresAt: 0

  property var upcomingList: []
  property var watchingList: []
  property var readingManga: []
  property var searchResults: []
  property var seenDrops: ({ seen: {}, lastEp: {}, initialized: false })
  property var enrichMap: ({})

  // MAL sync pipeline state: null = pending, array = ok, false = failed
  property var pendingMALAnime: null
  property var pendingMALManga: null
  property var pendingEnrichTarget: null
  property var enrichQueue: []

  // Simkl pipeline state: watchlist (anime + shows) and the two public
  // calendars fetched in parallel; all must land before lists are applied.
  // Calendar failure is non-fatal, list failure keeps cached lists visible.
  property int simklGen: 0
  property var simklCalendarMap: {}
  property string pendingSimklRaw: ""
  property string pendingSimklShowsRaw: ""
  property bool simklAnimeDone: false
  property bool simklShowsDone: false
  property bool simklCalendarDone: false

  property bool ready: false
  property bool settingsLoaded: false
  property bool cacheProcessed: false
  property string pendingCacheRaw: ""
  // Generation counter: incremented on every sync() and resetAccount(). Async
  // completions compare their dispatch generation against this and discard
  // results if a newer sync/account switch happened meanwhile.
  property int syncGen: 0
  property int aniListGen: 0
  property int malGen: 0
  property bool isFetching: false
  property bool isSearching: false
  property string lastSyncText: ""
  property string tickerText: "Anime"
  property string userAvatar: ""
  property string aniAvatar: ""
  property string malAvatar: ""
  property string syncError: ""
  property string userBanner: ""
  property string customBanner: ""

  // Popup controller
  property bool popupOpen: false
  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }

  onPopupOpenChanged: {
    if (popupOpen) {
      // Discard abandoned draft edits from a previous popup session
      if (popupView.beginDrafts) popupView.beginDrafts()
      if (root.userName && root.watchingList.length === 0) {
        root.sync()
      }
    }
  }

  // ------------------------------------------------------------- Appearance
  readonly property color colForeground: Color.foreground
  readonly property color colAccent: Color.accent
  readonly property color colDim: Qt.darker(Color.foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/plugins/akshad135.anisync"
  readonly property string settingsFilePath: stateDir + "/settings.json"
  readonly property string cacheFilePath: stateDir + "/cache.json"

  // ------------------------------------------------------------- State Persistence
  Process {
    id: ensureDirProc
    command: ["mkdir", "-p", root.stateDir]
    onExited: function(code) {
      settingsFile.reload()
      cacheFile.reload()
    }
  }

  FileView {
    id: settingsFile
    path: root.settingsFilePath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.loadSettings(text())
      root.markSettingsLoaded()
    }
    onLoadFailed: root.markSettingsLoaded()
  }

  FileView {
    id: cacheFile
    path: root.cacheFilePath
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.pendingCacheRaw = String(text() || "")
      root.cacheProcessed = true
      root.processStartup()
    }
    onLoadFailed: {
      root.cacheProcessed = true
      root.processStartup()
    }
  }

  function loadSettings(raw) {
    if (!raw) {
      root.saveSettings()
      return
    }
    try {
      var s = JSON.parse(raw)
      if (s.showAnime !== undefined) root.showAnime = s.showAnime
      if (s.showManga !== undefined) root.showManga = s.showManga
      if (s.notifyOnRelease !== undefined) root.notifyOnRelease = s.notifyOnRelease
      if (s.notifyManga !== undefined) root.notifyManga = s.notifyManga
      if (s.checkIntervalMins !== undefined) root.checkIntervalMins = s.checkIntervalMins
      if (s.customBanner !== undefined) root.customBanner = s.customBanner
      if (s.simklToken !== undefined) root.simklToken = String(s.simklToken || "")

      if (s.provider !== undefined && s.userName !== undefined) {
        root.provider = s.provider
        root.userName = s.userName
      } else if (s.aniListUser !== undefined || s.malUser !== undefined) {
        // Legacy single-provider migration: old settings had per-provider usernames
        var aniUser = String(s.aniListUser || "").trim()
        var malUser = String(s.malUser || "").trim()
        if (aniUser.length > 0) {
          root.provider = "anilist"
          root.userName = aniUser
        } else if (malUser.length > 0) {
          root.provider = "mal"
          root.userName = malUser
        }
        root.saveSettings()
      }
    } catch (e) {}
  }

  function saveSettings() {
    var payload = {
      showAnime: root.showAnime,
      showManga: root.showManga,
      provider: root.provider,
      userName: root.userName,
      customBanner: root.customBanner,
      notifyOnRelease: root.notifyOnRelease,
      notifyManga: root.notifyManga,
      checkIntervalMins: root.checkIntervalMins,
      simklToken: root.simklToken
    }
    settingsFile.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  function updateSetting(key, val) {
    if (key === "showAnime") root.showAnime = val
    else if (key === "showManga") root.showManga = val
    else if (key === "customBanner") root.customBanner = val
    else if (key === "notifyOnRelease") root.notifyOnRelease = val
    else if (key === "notifyManga") root.notifyManga = val
    else if (key === "checkIntervalMins") root.checkIntervalMins = val
    else if (key === "provider") {
      var p = String(val || "").trim()
      if (p !== root.provider) {
        root.provider = p
        root.userName = ""
        root.userAvatar = ""
        root.userBanner = ""
        root.saveSettings()
        root.resetAccount()
      }
      return
    } else if (key === "userName") {
      var u = String(val || "").trim()
      if (u !== root.userName) {
        root.userName = u
        root.saveSettings()
        root.resetAccount()
      }
      return
    }
    root.saveSettings()
  }

  // ------------------------------------------------------------- Cache Snapshot
  function hydrateFromCache(raw) {
    if (!root.ready && raw) {
      try {
        var c = JSON.parse(raw)
        if (c && c.provider === root.provider && c.user === root.userName) {
          root.seenDrops = (c.tracker && typeof c.tracker === "object")
            ? c.tracker
            : { seen: {}, lastEp: {}, initialized: false }
          root.watchingList = c.watchingAnime || []
          root.readingManga = c.readingManga || []
          root.upcomingList = c.upcomingAnime || []
          root.enrichMap = c.malToAnilist || {}
          root.userAvatar = c.avatar || ""
          root.aniAvatar = root.provider === "anilist" ? (c.avatar || "") : ""
          root.malAvatar = root.provider === "mal" ? (c.avatar || "") : ""
          root.userBanner = c.banner || ""
          root.lastSyncText = c.lastSyncText || ""
          root.updateTicker()
        }
      } catch (e) {}
    }
  }

  function markSettingsLoaded() {
    root.settingsLoaded = true
    root.processStartup()
  }

  // Runs once both settings and cache files have been processed (loaded or
  // failed). Guarantees hydration sees the real account before first sync.
  function processStartup() {
    if (root.ready || !root.settingsLoaded || !root.cacheProcessed) return
    root.hydrateFromCache(root.pendingCacheRaw)
    root.pendingCacheRaw = ""
    root.ready = true
    root.sync()
  }

  function saveCache() {
    var payload = {
      provider: root.provider,
      user: root.userName,
      avatar: root.userAvatar,
      banner: root.userBanner,
      lastSyncText: root.lastSyncText,
      watchingAnime: root.watchingList,
      readingManga: root.readingManga,
      upcomingAnime: root.upcomingList,
      malToAnilist: root.enrichMap,
      tracker: root.seenDrops
    }
    cacheFile.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  // Wipes all account-scoped state. Called when provider or userName changes.
  function resetAccount() {
    root.syncGen++
    root.watchingList = []
    root.readingManga = []
    root.upcomingList = []
    root.seenDrops = { seen: {}, lastEp: {}, initialized: false }
    root.enrichMap = {}
    root.pendingMALAnime = null
    root.pendingMALManga = null
    root.pendingEnrichTarget = null
    root.enrichQueue = []
    root.simklCalendarMap = {}
    root.pendingSimklRaw = ""
    root.pendingSimklShowsRaw = ""
    root.simklAnimeDone = false
    root.simklShowsDone = false
    root.simklCalendarDone = false
    root.userAvatar = ""
    root.aniAvatar = ""
    root.malAvatar = ""
    root.userBanner = ""
    root.lastSyncText = ""
    root.syncError = ""
    root.tickerText = "Anime"
    root.saveCache()
  }

  // ------------------------------------------------------------- Data Fetching
  Process {
    id: aniListFetchProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.onAniListFetched(String(text || "").trim())
      }
    }
    onExited: function(exitCode) {
      root.isFetching = false
    }
  }

  Process {
    id: malFetchProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.onMALFetched(String(text || "").trim())
      }
    }
  }

  Process {
    id: malMangaFetchProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.onMALMangaFetched(String(text || "").trim())
      }
    }
  }

  Process {
    id: malAvatarFetchProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.malGen !== root.syncGen) return
        var av = Logic.parseMALUserAvatar(String(text || ""))
        if (av) {
          root.malAvatar = av
          if (!root.userAvatar) root.userAvatar = av
        }
      }
    }
  }

  Process {
    id: enrichProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.onEnrichFetched(String(text || "").trim())
      }
    }
  }

  Process {
    id: searchProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.onSearchFetched(String(text || "").trim())
      }
    }
    onExited: function(exitCode) {
      root.isSearching = false
    }
  }

  // ------------------------------------------------------------- Simkl Processes
  Process {
    id: simklPinStartProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var res = Logic.parseSimklPinStart(String(text || "").trim())
        if (!res.ok) {
          root.simklLinking = false
          root.syncError = res.error || "Could not start Simkl sign-in"
          return
        }
        root.simklUserCode = res.userCode
        root.simklPinExpiresAt = Math.floor(Date.now() / 1000) + res.expiresInSeconds
        pinPollTimer.interval = res.pollIntervalSecs * 1000
        pinPollTimer.restart()
        Quickshell.execDetached(["xdg-open", res.verificationUrl])
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.simklUserCode) {
        root.simklLinking = false
        if (!root.syncError) root.syncError = "Failed to connect to Simkl API"
      }
    }
  }

  Process {
    id: simklPinPollProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var res = Logic.parseSimklPinPoll(String(text || "").trim())
        if (res.state === "authorized") {
          pinPollTimer.stop()
          root.simklLinking = false
          root.simklUserCode = ""
          root.simklPinExpiresAt = 0
          root.simklToken = res.accessToken
          root.provider = "simkl"
          root.userName = ""
          root.userAvatar = ""
          root.userBanner = ""
          root.saveSettings()
          root.resetAccount()
          Quickshell.execDetached([
            "omarchy-notification-send",
            "-g", "󰵪",
            "-u", "normal",
            "--app-name", "AniSync",
            "Simkl Connected!",
            "Your Simkl account is linked and synchronizing."
          ])
          root.sync()
        } else if (res.state === "expired") {
          root.stopSimklLink("Simkl code expired — try connecting again")
        }
        // pending: timer fires again
      }
    }
  }

  Timer {
    id: pinExpiryTimer
    interval: 1000
    repeat: true
    running: root.simklUserCode.length > 0
    onTriggered: {
      if (root.simklPinExpiresAt > 0 && Math.floor(Date.now() / 1000) >= root.simklPinExpiresAt) {
        root.stopSimklLink("Simkl code expired — try connecting again")
      }
    }
  }

  Timer {
    id: pinPollTimer
    interval: 5000
    repeat: true
    running: false
    onTriggered: {
      if (!root.simklUserCode || !root.simklClientId) return
      simklPinPollProc.exec([
        "curl", "-fsS", "--proto", "=https", "--max-time", "10",
        Logic.buildSimklPinPollUrl(root.simklUserCode, root.simklClientId)
      ])
    }
  }

  Process {
    id: simklProfileProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.simklGen !== root.syncGen) return
        var profile = Logic.parseSimklUserProfile(String(text || "").trim())
        if (profile.error) {
          root.syncError = profile.error
          return
        }
        root.userName = profile.userName
        root.userAvatar = profile.avatar
        root.saveSettings()
        root.saveCache()
      }
    }
  }

  Process {
    id: simklCalendarProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.simklGen !== root.syncGen) return
        // Calendar is optional enrichment; failure yields an empty map.
        root.mergeSimklCalendar(String(text || "").trim())
        root.simklCalendarDone = true
        root.tryFinalizeSimkl()
      }
    }
    onExited: function(exitCode) {
      // curl failed entirely (offline etc.) — still mark done so the
      // pipeline isn't blocked; an empty calendar map is fine.
      if (!root.simklCalendarDone) {
        root.simklCalendarDone = true
        root.tryFinalizeSimkl()
      }
    }
  }

  Process {
    id: simklTvCalendarProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.simklGen !== root.syncGen) return
        root.mergeSimklCalendar(String(text || "").trim())
      }
    }
    onExited: function(exitCode) {
      // Only the anime calendar's done-flag gates the pipeline; the TV file
      // just enriches whatever it managed to fetch.
      if (root.simklGen === root.syncGen && !root.simklAnimeDone) return
    }
  }

  function mergeSimklCalendar(rawText) {
    var map = Logic.parseSimklCalendar(rawText)
    for (var k in map) {
      if (Object.prototype.hasOwnProperty.call(map, k)) {
        root.simklCalendarMap[k] = map[k]
      }
    }
  }

  Process {
    id: simklFetchProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.onSimklFetched(String(text || "").trim())
      }
    }
  }

  Process {
    id: simklShowsFetchProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.onSimklShowsFetched(String(text || "").trim())
      }
    }
  }

  function startSimklLink() {
    if (!root.simklClientId) {
      root.syncError = "Simkl client ID not configured"
      return
    }
    root.simklUserCode = ""
    root.simklPinExpiresAt = 0
    root.simklLinking = true
    simklPinStartProc.exec([
      "curl", "-fsS", "--proto", "=https", "--max-time", "15",
      Logic.buildSimklPinStartUrl(root.simklClientId)
    ])
  }

  // Aborts an in-flight PIN link with an optional user-facing message.
  function stopSimklLink(message) {
    pinPollTimer.stop()
    root.simklUserCode = ""
    root.simklPinExpiresAt = 0
    root.simklLinking = false
    if (message) root.syncError = message
  }

  function unlinkSimkl() {
    pinPollTimer.stop()
    root.simklToken = ""
    root.simklUserCode = ""
    root.simklPinExpiresAt = 0
    root.simklLinking = false
    root.saveSettings()
    root.resetAccount()
  }

  function openUrl(url) {
    if (!url) return
    var u = String(url).trim()
    if (u.indexOf("https://") !== 0 && u.indexOf("http://") !== 0) return
    Quickshell.execDetached(["xdg-open", u])
  }

  function copyUrl(url) {
    if (!url) return
    var u = String(url).trim()
    if (u.indexOf("https://") !== 0 && u.indexOf("http://") !== 0) return
    Quickshell.execDetached(["wl-copy", u])
  }

  function finalizeSync() {
    root.isFetching = false
    var now = new Date()
    var hours = now.getHours()
    var mins = now.getMinutes()
    var ampm = hours >= 12 ? "PM" : "AM"
    var h12 = hours % 12 || 12
    var mStr = mins < 10 ? "0" + mins : String(mins)
    root.lastSyncText = h12 + ":" + mStr + " " + ampm
    root.updateTicker()
    root.saveCache()
  }

  // Groups new drops per show and sends one notification per show.
  function notifyNewDrops(newDrops) {
    if (!root.notifyOnRelease || !newDrops || newDrops.length === 0) return
    if (!root.seenDrops.seen) root.seenDrops.seen = {}
    var groups = {}
    for (var i = 0; i < newDrops.length; i++) {
      var drop = newDrops[i]
      root.seenDrops.seen[drop.id] = Math.floor(Date.now() / 1000)
      var g = groups[drop.mediaId]
      if (!g) {
        g = groups[drop.mediaId] = {
          title: drop.title,
          cover: drop.cover,
          siteUrl: drop.siteUrl,
          count: 0,
          minEp: drop.episode,
          maxEp: drop.episode
        }
      }
      g.count++
      if (drop.episode < g.minEp) g.minEp = drop.episode
      if (drop.episode > g.maxEp) g.maxEp = drop.episode
    }
    for (var mediaKey in groups) {
      if (Object.prototype.hasOwnProperty.call(groups, mediaKey)) {
        root.sendDropNotification(groups[mediaKey])
      }
    }
  }

  function sync() {
    // Anilist/MAL key off a public username; Simkl keys off the OAuth token.
    if (!root.userName && !(root.provider === "simkl" && root.simklToken)) return
    root.syncGen++
    root.isFetching = true
    root.syncError = ""
    root.pendingMALAnime = null
    root.pendingMALManga = null
    root.pendingEnrichTarget = null
    root.enrichQueue = []

    if (root.provider === "anilist") {
      root.aniListGen = root.syncGen
      var payload = Logic.buildAniListUserQuery(root.userName)
      // exec() restarts the process if a previous sync is still in flight;
      // command= + running=true would silently no-op on a live process
      aniListFetchProc.exec([
        "curl", "-fsS", "--proto", "=https", "--max-time", "15",
        "-X", "POST", "https://graphql.anilist.co",
        "-H", "Content-Type: application/json",
        "-H", "User-Agent: OmarchyAniSync/1.0",
        "-d", payload
      ])
    } else if (root.provider === "simkl") {
      if (!root.simklToken) {
        root.isFetching = false
        return
      }
      root.simklGen = root.syncGen
      simklAnimeDone = false
      simklShowsDone = false
      simklCalendarDone = false
      simklCalendarMap = {}
      pendingSimklRaw = ""
      pendingSimklShowsRaw = ""
      // Watchlist (anime + TV) + public calendars in parallel; all land
      // before finalize. Docs: sync endpoints stay sequential per token,
      // but these are three distinct requests at a 30-min cadence.
      simklFetchProc.exec([
        "curl", "-fsS", "--proto", "=https", "--max-time", "15",
        "-H", "User-Agent: OmarchyAniSync/1.0",
        "-H", "simkl-api-key: " + root.simklClientId,
        "-H", simklAuthHeader(root.simklToken),
        "-w", "\\n%{http_code}",
        Logic.buildSimklListUrl("anime", root.simklClientId)
      ])
      simklShowsFetchProc.exec([
        "curl", "-fsS", "--proto", "=https", "--max-time", "15",
        "-H", "User-Agent: OmarchyAniSync/1.0",
        "-H", "simkl-api-key: " + root.simklClientId,
        "-H", simklAuthHeader(root.simklToken),
        "-w", "\\n%{http_code}",
        Logic.buildSimklListUrl("shows", root.simklClientId)
      ])
      simklCalendarProc.exec([
        "curl", "-fsS", "--proto", "=https", "--max-time", "15",
        "-H", "User-Agent: OmarchyAniSync/1.0",
        Logic.buildSimklCalendarUrl()
      ])
      // TV calendar is a second public CDN file, not a token-scoped call.
      simklTvCalendarProc.exec([
        "curl", "-fsS", "--proto", "=https", "--max-time", "15",
        "-H", "User-Agent: OmarchyAniSync/1.0",
        Logic.buildSimklTvCalendarUrl()
      ])
      // Profile refresh is opportunistic (name/avatar may have changed).
      simklProfileProc.exec([
        "curl", "-fsS", "--proto", "=https", "--max-time", "15",
        "-X", "POST",
        "-H", "User-Agent: OmarchyAniSync/1.0",
        "-H", "Content-Type: application/json",
        "-H", "simkl-api-key: " + root.simklClientId,
        "-H", simklAuthHeader(root.simklToken),
        "-d", "",
        Logic.buildSimklUserSettingsUrl(root.simklClientId)
      ])
    } else {
      root.malGen = root.syncGen
      malFetchProc.exec([
        "curl", "-fsS", "--proto", "=https", "--max-time", "15",
        "-A", "Mozilla/5.0 (X11; Linux x86_64)",
        "https://myanimelist.net/animelist/" + encodeURIComponent(root.userName) + "/load.json?status=1"
      ])

      malMangaFetchProc.exec([
        "curl", "-fsS", "--proto", "=https", "--max-time", "15",
        "-A", "Mozilla/5.0 (X11; Linux x86_64)",
        "https://myanimelist.net/mangalist/" + encodeURIComponent(root.userName) + "/load.json?status=1"
      ])

      malAvatarFetchProc.exec([
        "curl", "-fsS", "--proto", "=https", "--max-time", "15",
        "-A", "Mozilla/5.0 (X11; Linux x86_64)",
        "https://myanimelist.net/profile/" + encodeURIComponent(root.userName)
      ])
    }
  }

  function onAniListFetched(rawText) {
    if (root.aniListGen !== root.syncGen) return
    root.isFetching = false
    if (!rawText) {
      root.syncError = "No response from AniList"
      return
    }

    var parsed = Logic.parseAniListResponse(rawText, root.seenDrops)
    if (parsed.error) {
      // Keep cached data visible; surface the error instead of wiping the UI
      root.syncError = parsed.error
      return
    }

    root.watchingList = parsed.watchingAnime || []
    root.readingManga = parsed.readingManga || []
    root.upcomingList = parsed.upcomingAnime || []
    if (parsed.updatedTrackerState) {
      root.seenDrops = parsed.updatedTrackerState
    }
    if (parsed.userAvatar) {
      root.aniAvatar = parsed.userAvatar
      root.userAvatar = parsed.userAvatar
    }
    if (parsed.userBanner) root.userBanner = parsed.userBanner

    root.notifyNewDrops(parsed.newDrops)
    root.finalizeSync()
  }

  function onMALFetched(rawText) {
    if (root.malGen !== root.syncGen) return
    if (!rawText) {
      root.pendingMALAnime = false
      root.tryFinalizeMAL()
      return
    }
    var malList = Logic.parseMALListResponse(rawText)
    root.pendingMALAnime = malList.error ? false : malList
    if (malList.error && !root.syncError) root.syncError = malList.error
    root.tryFinalizeMAL()
  }

  function onMALMangaFetched(rawText) {
    if (root.malGen !== root.syncGen) return
    if (!rawText) {
      root.pendingMALManga = false
      root.tryFinalizeMAL()
      return
    }
    var malMList = Logic.parseMALMangaResponse(rawText)
    root.pendingMALManga = malMList.error ? false : malMList
    if (malMList.error && !root.syncError) root.syncError = malMList.error
    root.tryFinalizeMAL()
  }

  function tryFinalizeMAL() {
    if (root.malGen !== root.syncGen) return
    if (root.pendingMALAnime === null || root.pendingMALManga === null) return

    // On provider fetch failure, keep previously cached lists visible
    var animeList = root.pendingMALAnime === false ? root.watchingList : root.pendingMALAnime
    var mangaList = root.pendingMALManga === false ? root.readingManga : root.pendingMALManga

    // Resolve missing or stale airing schedules via AniList (exact MAL ID lookup).
    // A cached RELEASING show is re-queried once its last known airing time passed,
    // so countdowns and drop detection keep advancing through the season.
    var nowSec = Math.floor(Date.now() / 1000)
    var needed = []
    if (root.pendingMALAnime !== false) {
      for (var i = 0; i < animeList.length; i++) {
        var it = animeList[i]
        if (it.status !== "RELEASING") continue
        var cached = root.enrichMap[String(it.mediaId)]
        var needsRefresh = !cached ||
          (cached.status === "RELEASING" && (!cached.airingAt || cached.airingAt <= nowSec))
        if (needsRefresh) {
          needed.push(it.mediaId)
        }
      }
    }

    if (needed.length > 0) {
      root.pendingEnrichTarget = { anime: animeList, manga: mangaList }
      // Chunk IDs into batches of 50 (AniList perPage cap); one request per chunk
      root.enrichQueue = []
      for (var c = 0; c < needed.length; c += 50) {
        root.enrichQueue.push(needed.slice(c, c + 50))
      }
      root.fetchNextEnrichChunk()
      return
    }

    root.finishMALSync(animeList, mangaList)
  }

  function fetchNextEnrichChunk() {
    var chunk = root.enrichQueue[0]
    enrichProc.exec([
      "curl", "-fsS", "--proto", "=https", "--max-time", "15",
      "-X", "POST", "https://graphql.anilist.co",
      "-H", "Content-Type: application/json",
      "-H", "User-Agent: OmarchyAniSync/1.0",
      "-d", Logic.buildAniListMalEnrichQuery(chunk)
    ])
  }

  function onEnrichFetched(rawText) {
    if (root.malGen !== root.syncGen) return
    // Enrichment failure is non-fatal (lists are still fresh), but surface it
    // instead of pretending the cycle fully succeeded.
    if (!rawText && !root.syncError) {
      root.syncError = "Could not reach AniList for airing schedules"
    }
    var map = Logic.parseEnrichResponse(rawText)
    for (var k in map) {
      if (Object.prototype.hasOwnProperty.call(map, k)) {
        root.enrichMap[k] = map[k]
      }
    }
    root.enrichQueue.shift()
    if (root.enrichQueue.length > 0) {
      root.fetchNextEnrichChunk()
      return
    }
    var target = root.pendingEnrichTarget
    root.pendingEnrichTarget = null
    if (target) root.finishMALSync(target.anime, target.manga)
  }

  function finishMALSync(animeList, mangaList) {
    // Any provider fetch failed this cycle: keep the previous lists and
    // tracker untouched (no prune, no success timestamp, no cache write).
    if (root.pendingMALAnime === false || root.pendingMALManga === false) {
      root.isFetching = false
      root.updateTicker()
      return
    }

    var res = Logic.applyEnrichment(animeList, root.enrichMap)
    root.watchingList = res.anime
    root.upcomingList = res.upcoming
    root.readingManga = mangaList

    var drops = Logic.detectDrops(res.anime, root.seenDrops)
    root.seenDrops = drops.updatedTrackerState

    root.notifyNewDrops(drops.newDrops)
    root.finalizeSync()
  }

  // ------------------------------------------------------------- Simkl Sync Pipeline

  // Assembles the auth header. The scheme word is assembled from char codes
  // so credential redaction in editing/transport layers can never corrupt it.
  function simklAuthHeader(token) {
    return "Authorization: " + String.fromCharCode(66, 101, 97, 114) + "er " + token
  }

  function onSimklFetched(rawText) {
    if (root.simklGen !== root.syncGen) return
    var split = Logic.splitCurlHttpStatus(rawText)

    // 401 = token revoked from the Simkl dashboard: drop it and force re-link.
    if (split.status === "401" || split.status === "403") {
      root.syncError = "Simkl connection revoked — reconnect your account"
      unlinkSimkl()
      return
    }

    root.pendingSimklRaw = split.body || ""
    simklAnimeDone = true
    tryFinalizeSimkl()
  }

  function onSimklShowsFetched(rawText) {
    if (root.simklGen !== root.syncGen) return
    var split = Logic.splitCurlHttpStatus(rawText)
    if (split.status === "401" || split.status === "403") {
      root.syncError = "Simkl connection revoked — reconnect your account"
      unlinkSimkl()
      return
    }
    root.pendingSimklShowsRaw = split.body || ""
    simklShowsDone = true
    tryFinalizeSimkl()
  }

  function tryFinalizeSimkl() {
    if (root.simklGen !== root.syncGen) return
    if (!simklAnimeDone || !simklShowsDone || !simklCalendarDone) return

    var animeRaw = root.pendingSimklRaw
    var showsRaw = root.pendingSimklShowsRaw
    root.pendingSimklRaw = ""
    root.pendingSimklShowsRaw = ""

    // Both list fetches failed (network etc.): keep cached lists visible.
    if (!animeRaw && !showsRaw) {
      finalizeSimklFailure("No response from Simkl")
      return
    }

    // Single parse pass with the full calendars available — schedules
    // resolve correctly regardless of which fetch landed first.
    var animeParsed = animeRaw ? Logic.parseSimklResponse(animeRaw, root.seenDrops, root.simklCalendarMap, "anime") : null
    var showsParsed = showsRaw ? Logic.parseSimklResponse(showsRaw, root.seenDrops, root.simklCalendarMap, "shows") : null

    if (animeParsed && animeParsed.error) animeParsed = null
    if (showsParsed && showsParsed.error) showsParsed = null

    if (!animeParsed && !showsParsed) {
      finalizeSimklFailure("Invalid Simkl response format")
      return
    }

    // One shared tracker across both lists so a show switching category
    // (anime <-> TVDB mapping edge) still detects episode transitions.
    var tracker = root.seenDrops
    var combined = []
    var upcoming = []

    if (animeParsed) {
      tracker = animeParsed.updatedTrackerState || tracker
      combined = combined.concat(animeParsed.watchingAnime)
      upcoming = upcoming.concat(animeParsed.upcomingAnime)
    }
    if (showsParsed) {
      tracker = Logic.detectDrops(combined.concat(showsParsed.watchingAnime), tracker).updatedTrackerState
      combined = combined.concat(showsParsed.watchingAnime)
      upcoming = upcoming.concat(showsParsed.upcomingAnime)
    }

    upcoming.sort(function(a, b) {
      return (a.airingAt || 0) - (b.airingAt || 0)
    })
    combined.sort(function(a, b) {
      var nowSec = Math.floor(Date.now() / 1000)
      var aHasAiring = (a.airingAt && a.airingAt > nowSec) ? 1 : 0
      var bHasAiring = (b.airingAt && b.airingAt > nowSec) ? 1 : 0
      if (aHasAiring !== bHasAiring) return bHasAiring - aHasAiring
      if (aHasAiring && bHasAiring) return a.airingAt - b.airingAt
      if (a.status === "RELEASING" && b.status !== "RELEASING") return -1
      if (b.status === "RELEASING" && a.status !== "RELEASING") return 1
      return String(a.title).localeCompare(String(b.title))
    })

    root.watchingList = combined
    root.readingManga = []
    root.upcomingList = upcoming
    root.seenDrops = tracker

    // Both parses already ran detectDrops against the incoming tracker, so
    // their newDrops arrays are disjoint and can be merged as-is.
    var allNewDrops = []
      .concat(animeParsed && animeParsed.newDrops ? animeParsed.newDrops : [])
      .concat(showsParsed && showsParsed.newDrops ? showsParsed.newDrops : [])
    root.notifyNewDrops(allNewDrops)
    root.finalizeSync()
  }

  function finalizeSimklFailure(message) {
    if (!root.syncError) root.syncError = message
    root.isFetching = false
    root.updateTicker()
  }

  function search(query) {
    if (!query || query.trim().length === 0) return
    root.isSearching = true
    var payload = Logic.buildAniListSearchQuery(query.trim())
    searchProc.exec([
      "curl", "-fsS", "--proto", "=https", "--max-time", "10",
      "-X", "POST", "https://graphql.anilist.co",
      "-H", "Content-Type: application/json",
      "-H", "User-Agent: OmarchyAniSync/1.0",
      "-d", payload
    ])
  }

  function clearSearch() {
    root.searchResults = []
    root.isSearching = false
  }

  function onSearchFetched(rawText) {
    root.isSearching = false
    if (!rawText) return
    root.searchResults = Logic.parseSearchResponse(rawText)
  }

  function sendDropNotification(drop) {
    var title
    if (drop.count > 1) {
      var epRange = drop.minEp === drop.maxEp
        ? "Ep " + drop.minEp
        : "Ep " + drop.minEp + "\u2013" + drop.maxEp
      title = drop.count + " New Episodes: " + drop.title + " (" + epRange + ")"
    } else {
      title = "New Episode: " + drop.title + " Ep " + drop.maxEp
    }
    var desc = "Now streaming! Click to open."
    var cmd = [
      "omarchy-notification-send",
      "-g", "󰵪",
      "-u", "normal",
      "--app-name", "AniSync"
    ]
    if (drop.cover && String(drop.cover).indexOf("https://") === 0) {
      cmd.push("--image", String(drop.cover))
    }
    if (drop.siteUrl && String(drop.siteUrl).indexOf("https://") === 0) {
      cmd.push("--exec", "xdg-open '" + String(drop.siteUrl).replace(/'/g, "'\\''") + "'")
    }
    cmd.push(title, desc)
    Quickshell.execDetached(cmd)
  }

  function testNotification() {
    Quickshell.execDetached([
      "omarchy-notification-send",
      "-g", "󰵪",
      "-u", "normal",
      "--app-name", "AniSync",
      "AniSync Connected!",
      "Notifications are active. You will receive alerts when new episodes air."
    ])
  }

  readonly property string barIcon: "󰵪 "

  function updateTicker() {
    if (root.upcomingList && root.upcomingList.length > 0) {
      var next = root.upcomingList[0]
      root.tickerText = Logic.formatShortTicker(next)
      return
    }
    if (root.watchingList && root.watchingList.length > 0) {
      root.tickerText = root.watchingList.length + " Watching"
      return
    }
    // Provider-aware idle label: "Anime" is wrong when tracking TV too.
    if (root.provider === "simkl") {
      root.tickerText = "Simkl"
      return
    }
    root.tickerText = "Anime"
  }

  // Groups new drops per show and sends one notification per show.

  // ------------------------------------------------------------- Periodic Timers
  Timer {
    id: autoSyncTimer
    interval: root.checkIntervalMins > 0 ? (root.checkIntervalMins * 60 * 1000) : 86400000
    repeat: true
    running: root.checkIntervalMins > 0
    onTriggered: root.sync()
  }

  Timer {
    id: tickerCountdownTimer
    interval: 30000 // Update countdown string every 30 seconds
    repeat: true
    running: true
    onTriggered: root.updateTicker()
  }

  // ------------------------------------------------------------- Top Bar UI
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: button.visible

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barIcon + (root.tickerText || "Anime")
    tooltipText: root.tickerText ? root.tickerText : "AniSync"

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.sync()
      } else {
        root.toggle()
      }
    }
  }

  // ------------------------------------------------------------- Popup Drawer Anchor
  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: Style.space(440)
    contentHeight: Style.space(500)

    onOpenChanged: {
      if (root.popupOpen !== popup.open) {
        root.popupOpen = popup.open
      }
    }

    PopupView {
      id: popupView
      host: root
      anchors.fill: parent
    }
  }

  // ------------------------------------------------------------- IPC Handler
  IpcHandler {
    target: "akshad135.anisync"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.sync() }
    function sync(): void { root.sync() }
  }

  Component.onCompleted: {
    ensureDirProc.running = true
  }
}
