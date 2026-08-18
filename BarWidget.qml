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
  moduleName: "akshad135.anime-watcher"

  // ------------------------------------------------------------- Settings & State
  property bool showAnime: true
  property bool showManga: true
  property string aniListUser: "akshad"
  property string malUser: ""
  property bool notifyOnRelease: true
  property bool notifyManga: true
  property int checkIntervalMins: 30

  property var upcomingList: []
  property var recentDrops: []
  property var watchingList: []
  property var readingManga: []
  property var searchResults: []
  property var seenDrops: ({})

  property bool isFetching: false
  property bool isSearching: false
  property string lastSyncText: ""
  property string tickerText: "Anime"
  property int unseenCount: 0
  property string userAvatar: ""
  property string userBanner: ""
  property string customBanner: ""

  // Popup controller
  property bool popupOpen: false
  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }

  // ------------------------------------------------------------- Appearance
  readonly property color colForeground: Color.foreground
  readonly property color colAccent: Color.accent
  readonly property color colDim: Qt.darker(Color.foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/plugins/akshad135.anime-watcher"
  readonly property string settingsFilePath: stateDir + "/settings.json"
  readonly property string seenFilePath: stateDir + "/seen.json"

  // ------------------------------------------------------------- State Persistence
  Process {
    id: ensureDirProc
    command: ["mkdir", "-p", root.stateDir]
    onExited: function(code) {
      settingsFile.reload()
      seenFile.reload()
      root.sync()
    }
  }

  FileView {
    id: settingsFile
    path: root.settingsFilePath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadSettings(text())
  }

  FileView {
    id: seenFile
    path: root.seenFilePath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadSeen(text())
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
      if (s.aniListUser !== undefined) root.aniListUser = s.aniListUser
      if (s.malUser !== undefined) root.malUser = s.malUser
      if (s.customBanner !== undefined) root.customBanner = s.customBanner
      if (s.notifyOnRelease !== undefined) root.notifyOnRelease = s.notifyOnRelease
      if (s.notifyManga !== undefined) root.notifyManga = s.notifyManga
      if (s.checkIntervalMins !== undefined) root.checkIntervalMins = s.checkIntervalMins
    } catch (e) {}
  }

  function saveSettings() {
    var payload = {
      showAnime: root.showAnime,
      showManga: root.showManga,
      aniListUser: root.aniListUser,
      malUser: root.malUser,
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
    else if (key === "aniListUser") root.aniListUser = val
    else if (key === "malUser") root.malUser = val
    else if (key === "customBanner") root.customBanner = val
    else if (key === "notifyOnRelease") root.notifyOnRelease = val
    else if (key === "notifyManga") root.notifyManga = val
    else if (key === "checkIntervalMins") root.checkIntervalMins = val
    root.saveSettings()
  }

  function loadSeen(raw) {
    if (!raw) return
    try {
      var s = JSON.parse(raw)
      if (s && typeof s === "object") root.seenDrops = s
    } catch (e) {}
  }

  function saveSeen() {
    seenFile.setText(JSON.stringify(root.seenDrops, null, 2) + "\n")
  }

  function markSeen(dropId) {
    root.seenDrops[dropId] = Math.floor(Date.now() / 1000)
    root.saveSeen()
    root.recalculateUnseen()
  }

  function markAllSeen() {
    var nowSec = Math.floor(Date.now() / 1000)
    for (var i = 0; i < root.recentDrops.length; i++) {
      root.seenDrops[root.recentDrops[i].id] = nowSec
    }
    root.saveSeen()
    root.recalculateUnseen()
  }

  function recalculateUnseen() {
    var count = 0
    var drops = root.recentDrops
    for (var i = 0; i < drops.length; i++) {
      var drop = drops[i]
      drop.isNew = !root.seenDrops[drop.id]
      if (drop.isNew) count++
    }
    root.recentDrops = drops
    root.unseenCount = count
    root.updateTicker()
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

  Process {
    id: notifyProc
    running: false
    command: []
  }

  function openUrl(url) {
    if (!url) return
    Quickshell.execDetached(["xdg-open", String(url)])
  }

  function copyUrl(url) {
    if (!url) return
    Quickshell.execDetached(["wl-copy", String(url)])
  }

  // Internal provider buffers for union merging
  property var rawAniListAnime: []
  property var rawAniListManga: []
  property var rawMALAnime: []
  property var rawMALManga: []

  function unifyLists() {
    root.watchingList = Logic.mergeAnimeLists(root.rawAniListAnime, root.rawMALAnime)
    root.readingManga = Logic.mergeMangaLists(root.rawAniListManga, root.rawMALManga)
    root.recalculateUnseen()
    var now = new Date()
    var hours = now.getHours()
    var mins = now.getMinutes()
    var ampm = hours >= 12 ? "PM" : "AM"
    var h12 = hours % 12 || 12
    var mStr = mins < 10 ? "0" + mins : String(mins)
    root.lastSyncText = h12 + ":" + mStr + " " + ampm
    root.updateTicker()
  }

  function sync() {
    if (!root.aniListUser && !root.malUser) return
    root.isFetching = true

    if (root.aniListUser) {
      var payload = Logic.buildAniListUserQuery(root.aniListUser)
      aniListFetchProc.command = [
        "curl", "-fsS", "--max-time", "15",
        "-X", "POST", "https://graphql.anilist.co",
        "-H", "Content-Type: application/json",
        "-H", "User-Agent: OmarchyAnimeWatcher/1.0",
        "-d", payload
      ]
      aniListFetchProc.running = true
    } else {
      root.rawAniListAnime = []
      root.rawAniListManga = []
      root.upcomingList = []
      root.recentDrops = []
    }

    if (root.malUser) {
      malFetchProc.command = [
        "curl", "-fsS", "--max-time", "15",
        "-A", "Mozilla/5.0",
        "https://myanimelist.net/animelist/" + encodeURIComponent(root.malUser) + "/load.json?status=1"
      ]
      malFetchProc.running = true

      malMangaFetchProc.command = [
        "curl", "-fsS", "--max-time", "15",
        "-A", "Mozilla/5.0",
        "https://myanimelist.net/mangalist/" + encodeURIComponent(root.malUser) + "/load.json?status=1"
      ]
      malMangaFetchProc.running = true
    } else {
      root.rawMALAnime = []
      root.rawMALManga = []
    }
  }

  function onAniListFetched(rawText) {
    root.isFetching = false
    if (!rawText) return

    var parsed = Logic.parseAniListResponse(rawText, root.seenDrops)
    if (parsed.error) return

    root.rawAniListAnime = parsed.watchingAnime || []
    root.rawAniListManga = parsed.readingManga || []
    root.upcomingList = parsed.upcomingAnime || []
    root.recentDrops = parsed.recentDrops || []
    if (parsed.userAvatar) root.userAvatar = parsed.userAvatar
    if (parsed.userBanner) root.userBanner = parsed.userBanner

    // Check for newly dropped items that need desktop notifications
    if (root.notifyOnRelease && parsed.newDrops && parsed.newDrops.length > 0) {
      for (var i = 0; i < parsed.newDrops.length; i++) {
        var drop = parsed.newDrops[i]
        root.sendDropNotification(drop)
        root.seenDrops[drop.id] = Math.floor(Date.now() / 1000)
      }
      root.saveSeen()
    }

    root.unifyLists()
  }

  function onMALFetched(rawText) {
    root.isFetching = false
    if (!rawText) return
    root.rawMALAnime = Logic.parseMALListResponse(rawText)
    root.unifyLists()
  }

  function onMALMangaFetched(rawText) {
    root.isFetching = false
    if (!rawText) return
    root.rawMALManga = Logic.parseMALMangaResponse(rawText)
    root.unifyLists()
  }

  function search(query) {
    if (!query || query.trim().length === 0) return
    root.isSearching = true
    var payload = Logic.buildAniListSearchQuery(query.trim())
    searchProc.command = [
      "curl", "-fsS", "--max-time", "10",
      "-X", "POST", "https://graphql.anilist.co",
      "-H", "Content-Type: application/json",
      "-H", "User-Agent: OmarchyAnimeWatcher/1.0",
      "-d", payload
    ]
    searchProc.running = true
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
    var title = "🎌 New Episode: " + drop.title + " Ep " + drop.episode
    var desc = "Now streaming! Click to open."
    var cmd = [
      "omarchy-notification-send",
      "-g", "󰚩",
      "-u", "normal",
      "--app-name", "Anime Watcher"
    ]
    if (drop.cover) {
      cmd.push("--image", drop.cover)
    }
    if (drop.siteUrl) {
      cmd.push("--exec", "xdg-open '" + drop.siteUrl + "'")
    }
    cmd.push(title, desc)
    notifyProc.command = cmd
    notifyProc.running = true
  }

  function testNotification() {
    notifyProc.command = [
      "omarchy-notification-send",
      "-g", "󰚩",
      "-u", "normal",
      "--app-name", "Anime Watcher",
      "🎌 Anime Watcher Connected!",
      "Notifications are active. You will receive alerts when new episodes air."
    ]
    notifyProc.running = true
  }

  function updateTicker() {
    if (root.unseenCount > 0) {
      root.tickerText = root.unseenCount + " New"
      return
    }
    if (root.upcomingList && root.upcomingList.length > 0) {
      var next = root.upcomingList[0]
      root.tickerText = Logic.formatShortTicker(next)
      return
    }
    root.tickerText = "Anime"
  }

  // ------------------------------------------------------------- Periodic Timers
  Timer {
    id: autoSyncTimer
    interval: Math.max(5, root.checkIntervalMins) * 60 * 1000
    repeat: true
    running: true
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
    text: (root.unseenCount > 0 ? "󱅫 " : "󰚩 ") + (root.tickerText || "Anime")
    active: root.unseenCount > 0
    useActiveColor: true
    activeColor: colAccent
    tooltipText: root.unseenCount > 0 ? (root.unseenCount + " new episode(s) available") : (root.tickerText ? root.tickerText : "Anime Watcher")

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
    target: "akshad135.anime-watcher"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.sync() }
    function sync(): void { root.sync() }
  }

  Component.onCompleted: {
    ensureDirProc.running = true
    Qt.callLater(root.sync)
  }
}
