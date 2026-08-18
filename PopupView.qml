import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ReleaseLogic.js" as Logic

Item {
  id: root

  // Injected from BarWidget host
  property var host: null
  property bool showAnime: host ? host.showAnime : true
  property bool showManga: host ? host.showManga : true
  property var upcomingList: host ? host.upcomingList : []
  property var recentDrops: host ? host.recentDrops : []
  property var watchingList: host ? host.watchingList : []
  property var readingManga: host ? host.readingManga : []
  property var searchResults: host ? host.searchResults : []
  property bool isFetching: host ? host.isFetching : false
  property bool isSearching: host ? host.isSearching : false
  property string lastSyncText: host ? host.lastSyncText : ""
  property string aniListUser: host ? host.aniListUser : ""
  property string malUser: host ? host.malUser : ""
  property string userAvatar: host ? host.userAvatar : ""
  property string aniAvatar: host ? host.aniAvatar : ""
  property string malAvatar: host ? host.malAvatar : ""
  property string userBanner: host ? host.userBanner : ""
  property string customBanner: host ? host.customBanner : ""
  property string aniListError: host ? host.aniListError : ""
  property string malError: host ? host.malError : ""
  property bool notifyOnRelease: host ? host.notifyOnRelease : true
  property bool notifyManga: host ? host.notifyManga : true
  property int checkIntervalMins: host ? host.checkIntervalMins : 30
  property int unseenCount: host ? host.unseenCount : 0

  // Tick every 15s to refresh countdown strings
  property int tickCounter: 0
  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.tickCounter++
  }

  // Computed properties
  readonly property bool isDualAccount: (root.aniListUser.trim().length > 0 && root.malUser.trim().length > 0)
  readonly property bool canSync: (root.aniListUser.trim().length > 0 || root.malUser.trim().length > 0)
  readonly property string displayUserName: {
    if (root.isDualAccount) {
      if (root.aniListUser.trim().toLowerCase() === root.malUser.trim().toLowerCase()) {
        return root.aniListUser.trim()
      }
      return root.aniListUser.trim() + " · " + root.malUser.trim()
    }
    if (root.aniListUser.trim().length > 0) return root.aniListUser.trim()
    if (root.malUser.trim().length > 0) return root.malUser.trim()
    return "AniSync"
  }

  readonly property string activeBanner: {
    if (root.customBanner && root.customBanner.trim().length > 0) return root.customBanner.trim()
    if (root.userBanner && root.userBanner.trim().length > 0) return root.userBanner.trim()
    if (root.watchingList && root.watchingList.length > 0 && root.watchingList[0].cover) {
      return root.watchingList[0].cover
    }
    return ""
  }

  // Main 3 panels: Anime, Manga, Explore
  readonly property var mainTabsModel: {
    var list = []
    if (root.showAnime) list.push({ id: "anime", label: "Anime", icon: "󰿎" })
    if (root.showManga) list.push({ id: "manga", label: "Manga", icon: "󰂿" })
    list.push({ id: "explore", label: "Explore", icon: "󰍉" })
    return list
  }

  property string activeTabId: "anime"
  property string previousTabId: "anime"
  property bool isSettingsOpen: false

  onShowAnimeChanged: {
    if (!root.showAnime && root.activeTabId === "anime") {
      root.activeTabId = root.showManga ? "manga" : "explore"
    }
  }

  onShowMangaChanged: {
    if (!root.showManga && root.activeTabId === "manga") {
      root.activeTabId = root.showAnime ? "anime" : "explore"
    }
  }

  readonly property color colForeground: Color.foreground
  readonly property color colAccent: Color.accent
  readonly property color colDim: Qt.darker(Color.foreground, 1.4)
  readonly property color colMuted: Qt.darker(Color.foreground, 1.7)
  readonly property color colCardBg: Style.normalFillFor(Color.foreground, Color.accent)
  readonly property color colBorder: Style.normalBorderFor(Color.foreground, Color.accent)
  readonly property string fontFamily: host && host.bar ? host.bar.fontFamily : Style.font.family

  implicitWidth: Style.space(430)
  implicitHeight: Style.space(490)

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(8)

    // ------------------------------------------------------------- Header with Dynamic Banner Backdrop
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(48)
      radius: Style.cornerRadius
      clip: true
      color: "transparent"
      border.color: Util.alpha(colBorder, 0.25)
      border.width: 1

      // 1) Dynamic Themed Gradient (always active, harmonizes with current theme colors)
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Util.alpha(colAccent, 0.22) }
          GradientStop { position: 0.45; color: Util.alpha(colAccent, 0.08) }
          GradientStop { position: 1.0; color: Util.alpha(colForeground, 0.03) }
        }
      }

      // 2) Banner Background Image (Custom -> AniList User Banner -> Top Watching Anime Fallback)
      Image {
        anchors.fill: parent
        source: root.activeBanner
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: 0.32
        visible: root.activeBanner.length > 0
      }

      // 3) Soft Darkening Scrim Overlay for 100% text legibility
      Rectangle {
        anchors.fill: parent
        visible: root.activeBanner.length > 0
        color: Qt.rgba(0.04, 0.05, 0.07, 0.45)
      }

      // Header Row: [Avatar] [User Name/Status] (----space----) [Settings] [✕]
      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(8)

        // 1) DUAL OVERLAPPING AVATARS (if both accounts connected)
        Item {
          visible: root.isDualAccount
          width: Style.space(46)
          height: Style.space(32)

          // AniList Bubble (Left)
          Rectangle {
            width: Style.space(28)
            height: Style.space(28)
            radius: width / 2
            anchors.left: parent.left
            anchors.top: parent.top
            z: 2
            clip: true
            color: Util.alpha(colAccent, 0.2)
            border.color: Util.alpha(colAccent, 0.7)
            border.width: 1.5

            Image {
              anchors.fill: parent
              source: root.aniAvatar || root.userAvatar
              fillMode: Image.PreserveAspectCrop
              visible: (root.aniAvatar.length > 0 || root.userAvatar.length > 0)
              asynchronous: true
            }

            Image {
              anchors.centerIn: parent
              visible: !root.aniAvatar && !root.userAvatar
              source: Qt.resolvedUrl("assets/anilist.svg")
              width: Style.space(16)
              height: Style.space(16)
              sourceSize: Qt.size(16, 16)
            }
          }

          // MAL Bubble (Overlapping Right)
          Rectangle {
            width: Style.space(28)
            height: Style.space(28)
            radius: width / 2
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.bottom: parent.bottom
            z: 1
            clip: true
            color: Util.alpha("#2e51a2", 0.3)
            border.color: Util.alpha(colForeground, 0.35)
            border.width: 1.5

            Image {
              anchors.fill: parent
              source: root.malAvatar
              fillMode: Image.PreserveAspectCrop
              visible: root.malAvatar.length > 0
              asynchronous: true
            }

            Image {
              anchors.centerIn: parent
              visible: !root.malAvatar || root.malAvatar.length === 0
              source: Qt.resolvedUrl("assets/myanimelist.svg")
              width: Style.space(16)
              height: Style.space(16)
              sourceSize: Qt.size(16, 16)
            }
          }
        }

        // 2) SINGLE AVATAR (if single account or no account)
        Rectangle {
          visible: !root.isDualAccount
          width: Style.space(32)
          height: Style.space(32)
          radius: width / 2
          clip: true
          color: Util.alpha(colAccent, 0.2)
          border.color: Util.alpha(colAccent, 0.6)
          border.width: 1

          Image {
            anchors.fill: parent
            source: root.userAvatar
            fillMode: Image.PreserveAspectCrop
            visible: root.userAvatar.length > 0
            asynchronous: true
          }

          Image {
            anchors.centerIn: parent
            visible: !root.userAvatar || root.userAvatar.length === 0
            source: root.malUser.length > 0 ? Qt.resolvedUrl("assets/myanimelist.svg") : (root.aniListUser.length > 0 ? Qt.resolvedUrl("assets/anilist.svg") : Qt.resolvedUrl("assets/anisync.svg"))
            width: Style.space(18)
            height: Style.space(18)
            sourceSize: Qt.size(18, 18)
          }
        }

        // User Name + Status
        ColumnLayout {
          spacing: 0

          RowLayout {
            spacing: Style.space(4)

            Text {
              text: root.displayUserName
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              color: colForeground
              elide: Text.ElideRight
              Layout.maximumWidth: root.isDualAccount ? Style.space(160) : Style.space(220)
            }

            // Dual Account Tag
            Rectangle {
              visible: root.isDualAccount
              height: Style.space(16)
              width: dualTagText.implicitWidth + Style.space(8)
              radius: 4
              color: Util.alpha(colAccent, 0.15)
              border.color: Util.alpha(colAccent, 0.4)
              border.width: 1

              Text {
                id: dualTagText
                anchors.centerIn: parent
                text: "AL + MAL"
                font.family: root.fontFamily
                font.pixelSize: 9
                font.bold: true
                color: colAccent
              }
            }
          }

          Text {
            text: isFetching 
              ? "Syncing..." 
              : (lastSyncText.length > 0 
                  ? (root.isDualAccount ? ("Synced: AniList + MAL · " + lastSyncText) : ("Updated " + lastSyncText))
                  : "Ready")
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: isFetching ? colAccent : colDim
          }
        }

        // Space
        Item {
          Layout.fillWidth: true
        }

        // Settings Button (Top-right)
        Rectangle {
          width: Style.space(28)
          height: Style.space(28)
          radius: Style.cornerRadius
          color: root.isSettingsOpen 
            ? Util.alpha(colAccent, 0.35) 
            : (settingsHover.containsMouse ? Util.alpha(Color.background, 0.8) : Util.alpha(Color.background, 0.45))
          border.color: root.isSettingsOpen ? colAccent : (settingsHover.containsMouse ? colBorder : "transparent")
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: "󰒓"
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: root.isSettingsOpen ? colAccent : (settingsHover.containsMouse ? colForeground : colDim)
          }

          MouseArea {
            id: settingsHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.isSettingsOpen) {
                root.isSettingsOpen = false
                root.activeTabId = root.previousTabId || "anime"
              } else {
                root.previousTabId = root.activeTabId
                root.isSettingsOpen = true
              }
            }
          }
        }

        // Close Button
        Rectangle {
          width: Style.space(28)
          height: Style.space(28)
          radius: Style.cornerRadius
          color: closeHover.containsMouse ? Util.alpha(Color.background, 0.8) : Util.alpha(Color.background, 0.45)
          border.color: closeHover.containsMouse ? colBorder : "transparent"
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: "✕"
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            color: closeHover.containsMouse ? colForeground : colDim
          }

          MouseArea {
            id: closeHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (host && host.close) host.close()
            }
          }
        }
      }
    }

    // ------------------------------------------------------------- Segmented Tabs Bar: Anime, Manga, Explore
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(32)
      radius: Style.cornerRadius
      color: Util.alpha(colForeground, 0.06)
      visible: !root.isSettingsOpen

      RowLayout {
        anchors.fill: parent
        anchors.margins: Style.space(3)
        spacing: Style.space(3)

        Repeater {
          model: root.mainTabsModel

          delegate: Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Style.cornerRadius - 1
            color: (!root.isSettingsOpen && root.activeTabId === modelData.id)
              ? colAccent
              : (tabMouse.containsMouse ? Util.alpha(colForeground, 0.08) : "transparent")

            RowLayout {
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                text: modelData.icon
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: (!root.isSettingsOpen && root.activeTabId === modelData.id) ? "#12131a" : (tabMouse.containsMouse ? colForeground : colDim)
              }

              Text {
                text: modelData.label
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: (!root.isSettingsOpen && root.activeTabId === modelData.id)
                color: (!root.isSettingsOpen && root.activeTabId === modelData.id) ? "#12131a" : (tabMouse.containsMouse ? colForeground : colDim)
              }
            }

            MouseArea {
              id: tabMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.isSettingsOpen = false
                root.activeTabId = modelData.id
              }
            }
          }
        }
      }
    }

    // Settings Header Banner (when in settings)
    RowLayout {
      Layout.fillWidth: true
      visible: root.isSettingsOpen
      spacing: Style.space(6)

      Text {
        text: "⚙ Settings"
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        color: colForeground
      }

      Item { Layout.fillWidth: true }

      Rectangle {
        Layout.preferredHeight: Style.space(24)
        Layout.preferredWidth: backText.implicitWidth + 16
        radius: Style.cornerRadius
        color: backHover.containsMouse ? Util.alpha(colForeground, 0.1) : "transparent"

        Text {
          id: backText
          anchors.centerIn: parent
          text: "← Back"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          color: backHover.containsMouse ? colAccent : colDim
        }

        MouseArea {
          id: backHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.isSettingsOpen = false
            root.activeTabId = root.previousTabId || "anime"
          }
        }
      }
    }

    // Divider
    Rectangle {
      Layout.fillWidth: true
      height: 1
      color: Util.alpha(colBorder, 0.4)
    }

    // ------------------------------------------------------------- Panels Content

    // ============================================================= ANIME PANEL
    Item {
      visible: !root.isSettingsOpen && root.activeTabId === "anime"
      Layout.fillWidth: true
      Layout.fillHeight: true

      ListView {
        id: animeListView
        anchors.fill: parent
        clip: true
        spacing: Style.space(6)
        model: root.watchingList

        delegate: Rectangle {
          id: animeCard
          width: animeListView.width
          height: modelData.nextEpisode ? Style.space(68) : Style.space(56)
          radius: Style.cornerRadius
          color: animeCardMouse.containsMouse ? Util.alpha(colAccent, 0.12) : "transparent"
          border.color: animeCardMouse.containsMouse ? Util.alpha(colAccent, 0.3) : "transparent"
          border.width: 1

          property bool copied: false
          Timer {
            id: animeCopyTimer
            interval: 1500
            onTriggered: animeCard.copied = false
          }

          RowLayout {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(8)

            // Cover Image
            Rectangle {
              width: Style.space(36)
              height: modelData.nextEpisode ? Style.space(54) : Style.space(44)
              radius: 4
              clip: true
              color: Util.alpha(colForeground, 0.08)

              Image {
                anchors.fill: parent
                source: modelData.cover || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }

              Text {
                visible: !modelData.cover
                anchors.centerIn: parent
                text: "󰿎"
                font.family: root.fontFamily
                color: colDim
              }
            }

            // Info
            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)

              // Title
              Text {
                Layout.fillWidth: true
                text: modelData.title
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                color: colForeground
                elide: Text.ElideRight
              }

              // Progress + Score
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(6)

                Text {
                  text: "Watched " + modelData.progress + (modelData.totalEpisodes ? (" / " + modelData.totalEpisodes) : " eps")
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: colAccent
                  font.bold: true
                }

                Text {
                  text: modelData.score > 0 ? ("★ " + modelData.score) : ""
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: "#f5c518"
                  visible: modelData.score > 0
                }

                Text {
                  visible: modelData.source === "AniList + MAL"
                  text: "AniList+MAL"
                  font.family: root.fontFamily
                  font.pixelSize: 9
                  color: colDim
                }
              }

              // Next Airing Countdown Chip & Schedule
              RowLayout {
                visible: modelData.nextEpisode !== null && modelData.nextEpisode !== undefined && modelData.airingAt > 0
                spacing: Style.space(6)

                Rectangle {
                  radius: 3
                  color: Util.alpha(colAccent, 0.22)
                  implicitWidth: epBadge.implicitWidth + 8
                  implicitHeight: epBadge.implicitHeight + 3

                  Text {
                    id: epBadge
                    anchors.centerIn: parent
                    text: {
                      var dummy = root.tickCounter
                      return "Ep " + modelData.nextEpisode + " " + Logic.formatCountdown(modelData.airingAt)
                    }
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    color: colAccent
                  }
                }

                Text {
                  text: Logic.formatAiringTime(modelData.airingAt)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: colMuted
                  elide: Text.ElideRight
                }
              }

              // Status for finished shows without upcoming episodes
              Text {
                visible: (!modelData.nextEpisode || !modelData.airingAt)
                text: modelData.status === "FINISHED" ? ("Completed · " + (modelData.totalEpisodes || modelData.progress) + " eps") : (modelData.status || "")
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: colMuted
              }
            }

            // Copy Link Button
            Rectangle {
              width: Style.space(28)
              height: Style.space(28)
              radius: Style.cornerRadius
              color: animeCopyHover.containsMouse ? Util.alpha(colAccent, 0.2) : "transparent"
              border.color: animeCopyHover.containsMouse ? Util.alpha(colAccent, 0.4) : "transparent"
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: animeCard.copied ? "✓" : "󰌹"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: animeCard.copied ? colAccent : (animeCopyHover.containsMouse ? colForeground : colDim)
              }

              MouseArea {
                id: animeCopyHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                  mouse.accepted = true
                  if (modelData.siteUrl && host && host.copyUrl) {
                    host.copyUrl(modelData.siteUrl)
                    animeCard.copied = true
                    animeCopyTimer.restart()
                  }
                }
              }
            }
          }

          // Card Click (Opens in Browser)
          MouseArea {
            id: animeCardMouse
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (modelData.siteUrl && host && host.openUrl) {
                host.openUrl(modelData.siteUrl)
              }
            }
          }
        }

        // Empty state
        Item {
          anchors.fill: parent
          visible: animeListView.count === 0 && !root.isFetching

          ColumnLayout {
            anchors.centerIn: parent
            spacing: Style.space(6)

            Text {
              Layout.alignment: Qt.AlignHCenter
              text: "󰿎"
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              color: colBorder
            }

            Text {
              Layout.alignment: Qt.AlignHCenter
              text: root.aniListUser || root.malUser ? "No currently watching anime found" : "Set your username in Settings"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              color: colDim
            }

            Button {
              Layout.alignment: Qt.AlignHCenter
              text: root.aniListUser || root.malUser ? "Refresh" : "Open Settings"
              onClicked: {
                if (root.aniListUser || root.malUser) {
                  if (host && host.sync) host.sync()
                } else {
                  root.isSettingsOpen = true
                }
              }
            }
          }
        }
      }
    }

    // ============================================================= MANGA PANEL
    Item {
      visible: !root.isSettingsOpen && root.activeTabId === "manga"
      Layout.fillWidth: true
      Layout.fillHeight: true

      ListView {
        id: mangaListView
        anchors.fill: parent
        clip: true
        spacing: Style.space(6)
        model: root.readingManga

        delegate: Rectangle {
          id: mangaCard
          width: mangaListView.width
          height: Style.space(56)
          radius: Style.cornerRadius
          color: mangaCardMouse.containsMouse ? Util.alpha(colAccent, 0.12) : "transparent"
          border.color: mangaCardMouse.containsMouse ? Util.alpha(colAccent, 0.3) : "transparent"
          border.width: 1

          property bool copied: false
          Timer {
            id: mangaCopyTimer
            interval: 1500
            onTriggered: mangaCard.copied = false
          }

          RowLayout {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(8)

            Rectangle {
              width: Style.space(36)
              height: Style.space(44)
              radius: 4
              clip: true
              color: Util.alpha(colForeground, 0.08)

              Image {
                anchors.fill: parent
                source: modelData.cover || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }

              Text {
                visible: !modelData.cover
                anchors.centerIn: parent
                text: "󰂿"
                font.family: root.fontFamily
                color: colDim
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)

              Text {
                Layout.fillWidth: true
                text: modelData.title
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                color: colForeground
                elide: Text.ElideRight
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(6)

                Text {
                  text: "Progress: Ch. " + modelData.progress + (modelData.totalChapters ? (" / " + modelData.totalChapters) : "")
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: colAccent
                  font.bold: true
                }

                Text {
                  text: modelData.score > 0 ? ("★ " + modelData.score) : ""
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: "#f5c518"
                  visible: modelData.score > 0
                }

                Rectangle {
                  visible: modelData.status === "RELEASING"
                  radius: 3
                  color: Util.alpha(colAccent, 0.15)
                  implicitWidth: mangaPubText.implicitWidth + 6
                  implicitHeight: mangaPubText.implicitHeight + 2

                  Text {
                    id: mangaPubText
                    anchors.centerIn: parent
                    text: "Publishing"
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    font.bold: true
                    color: colAccent
                  }
                }
              }
            }

            // Copy Link Button
            Rectangle {
              width: Style.space(28)
              height: Style.space(28)
              radius: Style.cornerRadius
              color: mangaCopyHover.containsMouse ? Util.alpha(colAccent, 0.2) : "transparent"
              border.color: mangaCopyHover.containsMouse ? Util.alpha(colAccent, 0.4) : "transparent"
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: mangaCard.copied ? "✓" : "󰌹"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: mangaCard.copied ? colAccent : (mangaCopyHover.containsMouse ? colForeground : colDim)
              }

              MouseArea {
                id: mangaCopyHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                  mouse.accepted = true
                  if (modelData.siteUrl && host && host.copyUrl) {
                    host.copyUrl(modelData.siteUrl)
                    mangaCard.copied = true
                    mangaCopyTimer.restart()
                  }
                }
              }
            }
          }

          // Card Click (Opens in Browser)
          MouseArea {
            id: mangaCardMouse
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (modelData.siteUrl && host && host.openUrl) {
                host.openUrl(modelData.siteUrl)
              }
            }
          }
        }

        // Empty state
        Item {
          anchors.fill: parent
          visible: mangaListView.count === 0 && !root.isFetching

          ColumnLayout {
            anchors.centerIn: parent
            spacing: Style.space(6)

            Text {
              Layout.alignment: Qt.AlignHCenter
              text: "󰂿"
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              color: colBorder
            }

            Text {
              Layout.alignment: Qt.AlignHCenter
              text: root.aniListUser || root.malUser ? "No currently reading manga found" : "Set your username in Settings"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              color: colDim
            }
          }
        }
      }
    }

    // ============================================================= EXPLORE PANEL
    Item {
      visible: !root.isSettingsOpen && root.activeTabId === "explore"
      Layout.fillWidth: true
      Layout.fillHeight: true

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(6)

        TextField {
          id: searchField
          Layout.fillWidth: true
          placeholderText: "Search anime or manga (e.g. Frieren, Solo Leveling)..."
          activeFocusOnPress: true

          onTextEdited: {
            searchDebounce.restart()
          }

          onAccepted: {
            if (host && host.search) host.search(text.trim())
          }

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              if (text.length > 0) {
                text = ""
                if (host && host.clearSearch) host.clearSearch()
              } else if (host && host.close) {
                host.close()
              }
              event.accepted = true
            }
          }
        }

        Timer {
          id: searchDebounce
          interval: 400
          repeat: false
          onTriggered: {
            if (searchField.text.trim().length >= 2 && host && host.search) {
              host.search(searchField.text.trim())
            }
          }
        }

        ListView {
          id: searchListView
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: Style.space(4)
          model: root.searchResults

          delegate: Rectangle {
            id: resultCard
            width: searchListView.width
            height: Style.space(56)
            radius: Style.cornerRadius
            color: resCardMouse.containsMouse ? Util.alpha(colAccent, 0.12) : "transparent"
            border.color: resCardMouse.containsMouse ? Util.alpha(colAccent, 0.3) : "transparent"
            border.width: 1

            property bool copied: false
            Timer {
              id: resCopyTimer
              interval: 1500
              onTriggered: resultCard.copied = false
            }

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              spacing: Style.space(8)

              Rectangle {
                width: Style.space(36)
                height: Style.space(44)
                radius: 4
                clip: true
                color: Util.alpha(colForeground, 0.08)

                Image {
                  anchors.fill: parent
                  source: modelData.cover || ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(1)

                Text {
                  Layout.fillWidth: true
                  text: modelData.title
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: colForeground
                  elide: Text.ElideRight
                }

                RowLayout {
                  spacing: Style.space(6)

                  Rectangle {
                    radius: 3
                    color: Util.alpha(colAccent, 0.15)
                    implicitWidth: typeText.implicitWidth + 6
                    implicitHeight: typeText.implicitHeight + 2

                    Text {
                      id: typeText
                      anchors.centerIn: parent
                      text: (modelData.type || "ANIME") + (modelData.format ? (" · " + modelData.format) : "")
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      color: colAccent
                      font.bold: true
                    }
                  }

                  Text {
                    text: modelData.nextEpisode ? ("Ep " + modelData.nextEpisode + " " + Logic.formatCountdown(modelData.airingAt)) : (modelData.status || "")
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    color: colDim
                  }
                }
              }

              // Copy Link Button
              Rectangle {
                width: Style.space(28)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: resCopyHover.containsMouse ? Util.alpha(colAccent, 0.2) : "transparent"
                border.color: resCopyHover.containsMouse ? Util.alpha(colAccent, 0.4) : "transparent"
                border.width: 1

                Text {
                  anchors.centerIn: parent
                  text: resultCard.copied ? "✓" : "󰌹"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  color: resultCard.copied ? colAccent : (resCopyHover.containsMouse ? colForeground : colDim)
                }

                MouseArea {
                  id: resCopyHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    mouse.accepted = true
                    if (modelData.siteUrl && host && host.copyUrl) {
                      host.copyUrl(modelData.siteUrl)
                      resultCard.copied = true
                      resCopyTimer.restart()
                    }
                  }
                }
              }
            }

            // Card Click (Opens in Browser)
            MouseArea {
              id: resCardMouse
              anchors.fill: parent
              z: -1
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (modelData.siteUrl && host && host.openUrl) {
                  host.openUrl(modelData.siteUrl)
                }
              }
            }
          }

          Item {
            anchors.fill: parent
            visible: searchListView.count === 0

            ColumnLayout {
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: "󰍉"
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                color: colBorder
              }

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: searchField.text.length > 0 ? (root.isSearching ? "Searching..." : "No results found") : "Type to search on AniList"
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: colDim
              }
            }
          }
        }
      }
    }

    // ============================================================= SETTINGS PANEL
    Item {
      id: settingsPanelItem
      visible: root.isSettingsOpen
      Layout.fillWidth: true
      Layout.fillHeight: true

      property string activeAccountTab: "anilist"

      Flickable {
        anchors.fill: parent
        contentHeight: settingsCol.implicitHeight + Style.space(12)
        clip: true

        ColumnLayout {
          id: settingsCol
          width: parent.width
          spacing: Style.space(10)

          // --------------------------------------------- SECTION 1: Accounts & Profile (Sub-Tabs)
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            RowLayout {
              spacing: Style.space(6)
              Text {
                text: "󰀉"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: colAccent
              }
              Text {
                text: "Accounts & Profile"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                color: colForeground
              }
            }

            // Sub-tabs: [ 󰚩 AniList • ] [ 󰒓 MAL ] [ 🖼 Banner ]
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(32)
              radius: Style.cornerRadius
              color: Util.alpha(colForeground, 0.06)

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.space(3)
                spacing: Style.space(4)

                // AniList SubTab
                Rectangle {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  radius: Style.cornerRadius - 1
                  color: (settingsPanelItem.activeAccountTab === "anilist") 
                    ? colAccent 
                    : (aniTabHover.containsMouse ? Util.alpha(colForeground, 0.08) : "transparent")

                  RowLayout {
                    anchors.centerIn: parent
                    spacing: Style.space(5)

                    Image {
                      source: Qt.resolvedUrl("assets/anilist.svg")
                      width: Style.space(13)
                      height: Style.space(13)
                      sourceSize: Qt.size(13, 13)
                      fillMode: Image.PreserveAspectFit
                    }

                    Text {
                      text: "AniList"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: (settingsPanelItem.activeAccountTab === "anilist")
                      color: (settingsPanelItem.activeAccountTab === "anilist") ? "#12131a" : (aniTabHover.containsMouse ? colForeground : colDim)
                    }

                    Rectangle {
                      width: 5
                      height: 5
                      radius: 2.5
                      color: (settingsPanelItem.activeAccountTab === "anilist") ? "#12131a" : "#4ade80"
                      visible: root.aniListUser.trim().length > 0
                    }
                  }

                  MouseArea {
                    id: aniTabHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: settingsPanelItem.activeAccountTab = "anilist"
                  }
                }

                // MAL SubTab
                Rectangle {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  radius: Style.cornerRadius - 1
                  color: (settingsPanelItem.activeAccountTab === "mal") 
                    ? colAccent 
                    : (malTabHover.containsMouse ? Util.alpha(colForeground, 0.08) : "transparent")

                  RowLayout {
                    anchors.centerIn: parent
                    spacing: Style.space(5)

                    Image {
                      source: Qt.resolvedUrl("assets/myanimelist.svg")
                      width: Style.space(13)
                      height: Style.space(13)
                      sourceSize: Qt.size(13, 13)
                      fillMode: Image.PreserveAspectFit
                    }

                    Text {
                      text: "MAL"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: (settingsPanelItem.activeAccountTab === "mal")
                      color: (settingsPanelItem.activeAccountTab === "mal") ? "#12131a" : (malTabHover.containsMouse ? colForeground : colDim)
                    }

                    Rectangle {
                      width: 5
                      height: 5
                      radius: 2.5
                      color: (settingsPanelItem.activeAccountTab === "mal") ? "#12131a" : "#4ade80"
                      visible: root.malUser.trim().length > 0
                    }
                  }

                  MouseArea {
                    id: malTabHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: settingsPanelItem.activeAccountTab = "mal"
                  }
                }

                // Banner SubTab
                Rectangle {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  radius: Style.cornerRadius - 1
                  color: (settingsPanelItem.activeAccountTab === "banner") 
                    ? colAccent 
                    : (bannerTabHover.containsMouse ? Util.alpha(colForeground, 0.08) : "transparent")

                  RowLayout {
                    anchors.centerIn: parent
                    spacing: Style.space(5)

                    Text {
                      text: "󰸭"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      color: (settingsPanelItem.activeAccountTab === "banner") ? "#12131a" : (bannerTabHover.containsMouse ? colForeground : colDim)
                    }

                    Text {
                      text: "Banner"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: (settingsPanelItem.activeAccountTab === "banner")
                      color: (settingsPanelItem.activeAccountTab === "banner") ? "#12131a" : (bannerTabHover.containsMouse ? colForeground : colDim)
                    }

                    Rectangle {
                      width: 5
                      height: 5
                      radius: 2.5
                      color: (settingsPanelItem.activeAccountTab === "banner") ? "#12131a" : "#4ade80"
                      visible: root.customBanner.trim().length > 0
                    }
                  }

                  MouseArea {
                    id: bannerTabHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: settingsPanelItem.activeAccountTab = "banner"
                  }
                }
              }
            }

            // Active Sub-Tab Form Field
            // 1) AniList
            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(3)
              visible: settingsPanelItem.activeAccountTab === "anilist"

              TextField {
                id: aniInput
                Layout.fillWidth: true
                text: root.aniListUser
                placeholderText: "Enter AniList username (e.g. frizzy135)"
                activeFocusOnPress: true

                onTextEdited: {
                  if (host && host.updateSetting) host.updateSetting("aniListUser", text.trim())
                }
              }

              Text {
                Layout.fillWidth: true
                text: {
                  if (root.aniListError && root.aniListError.length > 0) return "⚠ " + root.aniListError
                  if (root.aniListUser.trim().length > 0) return "✓ Connected · Syncs countdown schedules, covers & banner"
                  return "Syncs your watching/reading lists and exact countdowns"
                }
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: (root.aniListError && root.aniListError.length > 0) ? "#f87171" : (root.aniListUser.trim().length > 0 ? colAccent : Qt.lighter(colDim, 1.25))
              }
            }

            // 2) MAL
            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(3)
              visible: settingsPanelItem.activeAccountTab === "mal"

              TextField {
                id: malInput
                Layout.fillWidth: true
                text: root.malUser
                placeholderText: "Enter MyAnimeList username (e.g. Xinil)"
                activeFocusOnPress: true

                onTextEdited: {
                  if (host && host.updateSetting) host.updateSetting("malUser", text.trim())
                }
              }

              Text {
                Layout.fillWidth: true
                text: {
                  if (root.malError && root.malError.length > 0) return "⚠ " + root.malError
                  if (root.malUser.trim().length > 0) return "✓ Connected · Merged with AniList into unified watchlist"
                  return "Optional · Can be combined with AniList simultaneously"
                }
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: (root.malError && root.malError.length > 0) ? "#f87171" : (root.malUser.trim().length > 0 ? colAccent : Qt.lighter(colDim, 1.25))
              }
            }

            // 3) Banner
            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(3)
              visible: settingsPanelItem.activeAccountTab === "banner"

              TextField {
                id: bannerInput
                Layout.fillWidth: true
                text: root.customBanner
                placeholderText: "Custom banner image URL or local file path"
                activeFocusOnPress: true

                onTextEdited: {
                  if (host && host.updateSetting) host.updateSetting("customBanner", text.trim())
                }
              }

              Text {
                Layout.fillWidth: true
                text: root.customBanner.trim().length > 0 
                  ? "✓ Custom banner image configured" 
                  : "Leave empty to auto-sync your account profile banner"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: root.customBanner.trim().length > 0 ? colAccent : Qt.lighter(colDim, 1.25)
              }
            }
          }

          // Section Divider
          Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Util.alpha(colBorder, 0.2)
          }

          // --------------------------------------------- SECTION 2 & 3: 2-COLUMN GRID (Sections & Alerts)
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(10)

            // Col 1: Display Sections (50% equal width)
            ColumnLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              spacing: Style.space(5)

              RowLayout {
                spacing: Style.space(4)
                Text { text: "󰿎"; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; color: colAccent }
                Text { text: "Sections"; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; color: colForeground }
              }

              // Anime Toggle Tile
              Rectangle {
                Layout.fillWidth: true
                height: Style.space(36)
                radius: Style.cornerRadius
                color: Util.alpha(colForeground, 0.04)
                border.color: root.showAnime ? Util.alpha(colAccent, 0.4) : Util.alpha(colBorder, 0.2)
                border.width: 1

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.space(7)
                  spacing: Style.space(6)

                  Text { text: "󰿎"; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; color: root.showAnime ? colAccent : colDim }
                  Text { Layout.fillWidth: true; text: "Anime"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; color: colForeground }

                  Rectangle {
                    width: Style.space(30)
                    height: Style.space(16)
                    radius: 8
                    color: root.showAnime ? colAccent : Util.alpha(colForeground, 0.15)

                    Rectangle {
                      width: Style.space(12)
                      height: Style.space(12)
                      radius: 6
                      color: root.showAnime ? "#12131a" : colDim
                      anchors.verticalCenter: parent.verticalCenter
                      x: root.showAnime ? (parent.width - width - 2) : 2
                      Behavior on x { NumberAnimation { duration: 120 } }
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (host && host.updateSetting) host.updateSetting("showAnime", !root.showAnime)
                  }
                }
              }

              // Manga Toggle Tile
              Rectangle {
                Layout.fillWidth: true
                height: Style.space(36)
                radius: Style.cornerRadius
                color: Util.alpha(colForeground, 0.04)
                border.color: root.showManga ? Util.alpha(colAccent, 0.4) : Util.alpha(colBorder, 0.2)
                border.width: 1

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.space(7)
                  spacing: Style.space(6)

                  Text { text: "󰂿"; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; color: root.showManga ? colAccent : colDim }
                  Text { Layout.fillWidth: true; text: "Manga"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; color: colForeground }

                  Rectangle {
                    width: Style.space(30)
                    height: Style.space(16)
                    radius: 8
                    color: root.showManga ? colAccent : Util.alpha(colForeground, 0.15)

                    Rectangle {
                      width: Style.space(12)
                      height: Style.space(12)
                      radius: 6
                      color: root.showManga ? "#12131a" : colDim
                      anchors.verticalCenter: parent.verticalCenter
                      x: root.showManga ? (parent.width - width - 2) : 2
                      Behavior on x { NumberAnimation { duration: 120 } }
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (host && host.updateSetting) host.updateSetting("showManga", !root.showManga)
                  }
                }
              }
            }

            // Col 2: Release Alerts (50% equal width)
            ColumnLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              spacing: Style.space(5)

              RowLayout {
                spacing: Style.space(4)
                Text { text: "󰂚"; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; color: colAccent }
                Text { text: "Alerts"; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; color: colForeground }
              }

              // Anime Alerts Toggle Tile
              Rectangle {
                Layout.fillWidth: true
                height: Style.space(36)
                radius: Style.cornerRadius
                color: Util.alpha(colForeground, 0.04)
                border.color: root.notifyOnRelease ? Util.alpha(colAccent, 0.4) : Util.alpha(colBorder, 0.2)
                border.width: 1

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.space(7)
                  spacing: Style.space(6)

                  Text { text: "󰿎"; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; color: root.notifyOnRelease ? colAccent : colDim }
                  Text { Layout.fillWidth: true; text: "Episodes"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; color: colForeground }

                  Rectangle {
                    width: Style.space(30)
                    height: Style.space(16)
                    radius: 8
                    color: root.notifyOnRelease ? colAccent : Util.alpha(colForeground, 0.15)

                    Rectangle {
                      width: Style.space(12)
                      height: Style.space(12)
                      radius: 6
                      color: root.notifyOnRelease ? "#12131a" : colDim
                      anchors.verticalCenter: parent.verticalCenter
                      x: root.notifyOnRelease ? (parent.width - width - 2) : 2
                      Behavior on x { NumberAnimation { duration: 120 } }
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (host && host.updateSetting) host.updateSetting("notifyOnRelease", !root.notifyOnRelease)
                  }
                }
              }

              // Manga Alerts Toggle Tile
              Rectangle {
                Layout.fillWidth: true
                height: Style.space(36)
                radius: Style.cornerRadius
                color: Util.alpha(colForeground, 0.04)
                border.color: root.notifyManga ? Util.alpha(colAccent, 0.4) : Util.alpha(colBorder, 0.2)
                border.width: 1

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.space(7)
                  spacing: Style.space(6)

                  Text { text: "󰂿"; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; color: root.notifyManga ? colAccent : colDim }
                  Text { Layout.fillWidth: true; text: "Chapters"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; color: colForeground }

                  Rectangle {
                    width: Style.space(30)
                    height: Style.space(16)
                    radius: 8
                    color: root.notifyManga ? colAccent : Util.alpha(colForeground, 0.15)

                    Rectangle {
                      width: Style.space(12)
                      height: Style.space(12)
                      radius: 6
                      color: root.notifyManga ? "#12131a" : colDim
                      anchors.verticalCenter: parent.verticalCenter
                      x: root.notifyManga ? (parent.width - width - 2) : 2
                      Behavior on x { NumberAnimation { duration: 120 } }
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (host && host.updateSetting) host.updateSetting("notifyManga", !root.notifyManga)
                  }
                }
              }
            }
          }

          // Section Divider
          Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Util.alpha(colBorder, 0.2)
          }

          // Background Sync Interval (Full Width Segmented Bar)
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            RowLayout {
              spacing: Style.space(4)
              Text {
                text: "󰑐"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: colAccent
              }
              Text {
                text: "Sync Frequency"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                color: colForeground
              }
            }

            Rectangle {
              Layout.fillWidth: true
              height: Style.space(32)
              radius: Style.cornerRadius
              color: Util.alpha(colForeground, 0.06)

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.space(3)
                spacing: Style.space(4)

                Repeater {
                  model: [
                    { label: "15m", val: 15 },
                    { label: "30m", val: 30 },
                    { label: "1h", val: 60 },
                    { label: "2h", val: 120 },
                    { label: "Manual", val: 0 }
                  ]

                  delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Style.cornerRadius - 1
                    color: (root.checkIntervalMins === modelData.val) 
                      ? colAccent 
                      : (intHover.containsMouse ? Util.alpha(colForeground, 0.08) : "transparent")

                    Text {
                      anchors.centerIn: parent
                      text: modelData.label
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: (root.checkIntervalMins === modelData.val)
                      color: (root.checkIntervalMins === modelData.val) ? "#12131a" : (intHover.containsMouse ? colForeground : colDim)
                    }

                    MouseArea {
                      id: intHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (host && host.updateSetting) host.updateSetting("checkIntervalMins", modelData.val)
                      }
                    }
                  }
                }
              }
            }
          }

          // --------------------------------------------- SECTION 4: Actions (Test | Save & Sync)
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(10)

            // Test Button
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(36)
              radius: Style.cornerRadius
              color: testNotifHover.containsMouse ? Util.alpha(colAccent, 0.25) : Util.alpha(colForeground, 0.08)
              border.color: testNotifHover.containsMouse ? colAccent : colBorder
              border.width: 1

              RowLayout {
                anchors.centerIn: parent
                spacing: Style.space(6)

                Text {
                  text: "󰂚"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  color: colAccent
                }

                Text {
                  text: "Test Notification"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: colForeground
                }
              }

              MouseArea {
                id: testNotifHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (host && host.testNotification) host.testNotification()
                }
              }
            }

            // Sync Button (Enabled ONLY if account present)
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(36)
              radius: Style.cornerRadius
              color: root.canSync ? (syncBtnHover.containsMouse ? Qt.lighter(colAccent, 1.1) : colAccent) : Util.alpha(colForeground, 0.08)
              border.color: root.canSync ? colAccent : colBorder
              border.width: 1
              opacity: root.canSync ? 1.0 : 0.4

              RowLayout {
                anchors.centerIn: parent
                spacing: Style.space(6)

                Text {
                  text: "󰑐"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  color: root.canSync ? "#12131a" : colDim
                }

                Text {
                  text: "Save & Sync"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: root.canSync ? "#12131a" : colDim
                }
              }

              MouseArea {
                id: syncBtnHover
                anchors.fill: parent
                hoverEnabled: root.canSync
                cursorShape: root.canSync ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.canSync && host) {
                    if (host.updateSetting) {
                      host.updateSetting("aniListUser", aniInput.text.trim())
                      host.updateSetting("malUser", malInput.text.trim())
                      host.updateSetting("customBanner", bannerInput.text.trim())
                    }
                    if (host.sync) host.sync()
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
