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

  // ------------------------------------------------------------- Settings & State
  property bool showAnime: true
  property bool showManga: true
  property string provider: "anilist"
  property string userName: ""
  property bool notifyOnRelease: true
  property bool notifyManga: true
  property int checkIntervalMins: 30

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
      checkIntervalMins: root.checkIntervalMins
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
    if (!root.userName) return
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
    root.tickerText = "Anime"
  }

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
