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
  property bool notifyOnRelease: host ? host.notifyOnRelease : true
  property bool notifyManga: host ? host.notifyManga : true
  property int unseenCount: host ? host.unseenCount : 0

  // Computed properties
  readonly property bool canSync: (root.aniListUser.trim().length > 0 || root.malUser.trim().length > 0)
  readonly property string displayUserName: root.aniListUser.trim().length > 0 
    ? root.aniListUser.trim() 
    : (root.malUser.trim().length > 0 ? root.malUser.trim() : "Anime Watcher")

  // Main 3 panels: Anime, Manga, Explore
  readonly property var mainTabsModel: {
    var list = []
    if (root.showAnime) list.push({ id: "anime", label: "Anime", icon: "󰝚" })
    if (root.showManga) list.push({ id: "manga", label: "Manga", icon: "󰂬" })
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
  readonly property color colDim: Qt.darker(Color.foreground, 1.45)
  readonly property color colMuted: Qt.darker(Color.foreground, 1.85)
  readonly property color colCardBg: Style.normalFillFor(Color.foreground, Color.accent)
  readonly property color colBorder: Style.normalBorderFor(Color.foreground, Color.accent)
  readonly property string fontFamily: host && host.bar ? host.bar.fontFamily : Style.font.family

  implicitWidth: Style.space(420)
  implicitHeight: Style.space(480)

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(8)

    // ------------------------------------------------------------- Header: [User Icon] [User Name] (----space----) [Settings] [✕]
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      // User Icon
      Rectangle {
        width: Style.space(28)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: Util.alpha(colAccent, 0.2)

        Text {
          anchors.centerIn: parent
          text: "󰚩"
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          color: colAccent
        }
      }

      // User Name + Status
      ColumnLayout {
        spacing: 0

        Text {
          text: root.displayUserName
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          color: colForeground
          elide: Text.ElideRight
          Layout.maximumWidth: Style.space(220)
        }

        Text {
          text: isFetching ? "Syncing..." : (lastSyncText.length > 0 ? ("Updated " + lastSyncText) : "Ready")
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: isFetching ? colAccent : colDim
        }
      }

      // Space
      Item {
        Layout.fillWidth: true
      }

      // Settings Button (Next to user area, top-right)
      Rectangle {
        width: Style.space(28)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: root.isSettingsOpen 
          ? Util.alpha(colAccent, 0.25) 
          : (settingsHover.containsMouse ? colCardBg : "transparent")
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
        color: closeHover.containsMouse ? colCardBg : "transparent"
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

    // ------------------------------------------------------------- Main 3 Tabs: Anime, Manga, Explore
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(4)
      visible: !root.isSettingsOpen

      Repeater {
        model: root.mainTabsModel

        delegate: Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(28)
          radius: Style.cornerRadius
          color: (!root.isSettingsOpen && root.activeTabId === modelData.id)
            ? Util.alpha(colAccent, 0.22) 
            : (tabMouse.containsMouse ? Util.alpha(colCardBg, 0.6) : "transparent")
          border.color: (!root.isSettingsOpen && root.activeTabId === modelData.id) ? colAccent : "transparent"
          border.width: 1

          RowLayout {
            anchors.centerIn: parent
            spacing: Style.space(4)

            Text {
              text: modelData.icon
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: (!root.isSettingsOpen && root.activeTabId === modelData.id) ? colAccent : (tabMouse.containsMouse ? colForeground : colDim)
            }

            Text {
              text: modelData.label
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: (!root.isSettingsOpen && root.activeTabId === modelData.id)
              color: (!root.isSettingsOpen && root.activeTabId === modelData.id) ? colForeground : (tabMouse.containsMouse ? colForeground : colDim)
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

      Text {
        text: "← Back"
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        color: backHover.containsMouse ? colAccent : colDim

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
      color: Util.alpha(colBorder, 0.5)
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
          height: modelData.nextEpisode ? Style.space(64) : Style.space(56)
          radius: Style.cornerRadius
          color: animeMouse.containsMouse ? colCardBg : Util.alpha(colCardBg, 0.4)
          border.color: animeMouse.containsMouse ? colAccent : colBorder
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(8)

            // Cover Image
            Rectangle {
              width: Style.space(34)
              height: modelData.nextEpisode ? Style.space(50) : Style.space(44)
              radius: 4
              clip: true
              color: Qt.darker(colCardBg, 1.3)

              Image {
                anchors.fill: parent
                source: modelData.cover || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }

              Text {
                visible: !modelData.cover
                anchors.centerIn: parent
                text: "󰝚"
                font.family: root.fontFamily
                color: colDim
              }
            }

            // Details
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
                  text: "Watched " + modelData.progress + (modelData.totalEpisodes ? (" / " + modelData.totalEpisodes) : " eps")
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: colAccent
                }

                Text {
                  text: modelData.score > 0 ? ("★ " + modelData.score) : ""
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: "#f5c518"
                  visible: modelData.score > 0
                }
              }

              // Next Airing Info
              RowLayout {
                visible: modelData.nextEpisode !== null && modelData.nextEpisode !== undefined
                spacing: Style.space(6)

                Text {
                  text: "Next: Ep " + modelData.nextEpisode + " " + Logic.formatCountdown(modelData.airingAt)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: colMuted
                }
              }
            }

            Text {
              text: "󰌹"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              color: animeMouse.containsMouse ? colAccent : colDim
            }
          }

          MouseArea {
            id: animeMouse
            anchors.fill: parent
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
              text: "󰝚"
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
          color: mangaMouse.containsMouse ? colCardBg : Util.alpha(colCardBg, 0.4)
          border.color: mangaMouse.containsMouse ? colAccent : colBorder
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(8)

            Rectangle {
              width: Style.space(34)
              height: Style.space(44)
              radius: 4
              clip: true
              color: Qt.darker(colCardBg, 1.3)

              Image {
                anchors.fill: parent
                source: modelData.cover || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }

              Text {
                visible: !modelData.cover
                anchors.centerIn: parent
                text: "󰂬"
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
                }

                Text {
                  text: modelData.score > 0 ? ("★ " + modelData.score) : ""
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: "#f5c518"
                  visible: modelData.score > 0
                }
              }
            }

            Text {
              text: "󰌹"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              color: mangaMouse.containsMouse ? colAccent : colDim
            }
          }

          MouseArea {
            id: mangaMouse
            anchors.fill: parent
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
              text: "󰂬"
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              color: colBorder
            }

            Text {
              Layout.alignment: Qt.AlignHCenter
              text: root.aniListUser ? "No currently reading manga found" : "Set your AniList username in Settings"
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
          spacing: Style.space(6)
          model: root.searchResults

          delegate: Rectangle {
            id: resultCard
            width: searchListView.width
            height: Style.space(60)
            radius: Style.cornerRadius
            color: resMouse.containsMouse ? colCardBg : Util.alpha(colCardBg, 0.4)
            border.color: resMouse.containsMouse ? colAccent : colBorder
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              spacing: Style.space(8)

              Rectangle {
                width: Style.space(34)
                height: Style.space(48)
                radius: 4
                clip: true
                color: Qt.darker(colCardBg, 1.3)

                Image {
                  anchors.fill: parent
                  source: modelData.cover || ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
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

              Text {
                text: "󰌹"
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: resMouse.containsMouse ? colAccent : colDim
              }
            }

            MouseArea {
              id: resMouse
              anchors.fill: parent
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
      visible: root.isSettingsOpen
      Layout.fillWidth: true
      Layout.fillHeight: true

      Flickable {
        anchors.fill: parent
        contentHeight: settingsCol.implicitHeight
        clip: true

        ColumnLayout {
          id: settingsCol
          width: parent.width
          spacing: Style.space(10)

          // Display Sections
          Text {
            text: "Display Sections"
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            color: colForeground
          }

          RowLayout {
            Layout.fillWidth: true

            Text {
              Layout.fillWidth: true
              text: "Show Anime Section"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: colForeground
            }

            Rectangle {
              width: Style.space(38)
              height: Style.space(20)
              radius: 10
              color: root.showAnime ? colAccent : colCardBg
              border.color: colBorder
              border.width: 1

              Rectangle {
                width: Style.space(16)
                height: Style.space(16)
                radius: 8
                color: root.showAnime ? "#12131a" : colDim
                anchors.verticalCenter: parent.verticalCenter
                x: root.showAnime ? (parent.width - width - 2) : 2

                Behavior on x { NumberAnimation { duration: 120 } }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (host && host.updateSetting) host.updateSetting("showAnime", !root.showAnime)
                }
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true

            Text {
              Layout.fillWidth: true
              text: "Show Manga Section"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: colForeground
            }

            Rectangle {
              width: Style.space(38)
              height: Style.space(20)
              radius: 10
              color: root.showManga ? colAccent : colCardBg
              border.color: colBorder
              border.width: 1

              Rectangle {
                width: Style.space(16)
                height: Style.space(16)
                radius: 8
                color: root.showManga ? "#12131a" : colDim
                anchors.verticalCenter: parent.verticalCenter
                x: root.showManga ? (parent.width - width - 2) : 2

                Behavior on x { NumberAnimation { duration: 120 } }
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

          Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Util.alpha(colBorder, 0.5)
          }

          // Accounts Section
          Text {
            text: "Accounts"
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            color: colForeground
          }

          // AniList Username
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(3)

            Text {
              text: "AniList Username (Optional)"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: colDim
            }

            TextField {
              id: aniInput
              Layout.fillWidth: true
              text: root.aniListUser
              placeholderText: "e.g. akshad"
              activeFocusOnPress: true

              onTextEdited: {
                if (host && host.updateSetting) host.updateSetting("aniListUser", text.trim())
              }
            }
          }

          // MyAnimeList Username
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(3)

            Text {
              text: "MyAnimeList (MAL) Username (Optional)"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: colDim
            }

            TextField {
              id: malInput
              Layout.fillWidth: true
              text: root.malUser
              placeholderText: "e.g. akshad"
              activeFocusOnPress: true

              onTextEdited: {
                if (host && host.updateSetting) host.updateSetting("malUser", text.trim())
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Util.alpha(colBorder, 0.5)
          }

          // Notifications Section
          Text {
            text: "Notifications"
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            color: colForeground
          }

          RowLayout {
            Layout.fillWidth: true

            Text {
              Layout.fillWidth: true
              text: "Notify on Anime releases"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: colForeground
            }

            Rectangle {
              width: Style.space(38)
              height: Style.space(20)
              radius: 10
              color: root.notifyOnRelease ? colAccent : colCardBg
              border.color: colBorder
              border.width: 1

              Rectangle {
                width: Style.space(16)
                height: Style.space(16)
                radius: 8
                color: root.notifyOnRelease ? "#12131a" : colDim
                anchors.verticalCenter: parent.verticalCenter
                x: root.notifyOnRelease ? (parent.width - width - 2) : 2

                Behavior on x { NumberAnimation { duration: 120 } }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (host && host.updateSetting) host.updateSetting("notifyOnRelease", !root.notifyOnRelease)
                }
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true

            Text {
              Layout.fillWidth: true
              text: "Notify on Manga releases"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: colForeground
            }

            Rectangle {
              width: Style.space(38)
              height: Style.space(20)
              radius: 10
              color: root.notifyManga ? colAccent : colCardBg
              border.color: colBorder
              border.width: 1

              Rectangle {
                width: Style.space(16)
                height: Style.space(16)
                radius: 8
                color: root.notifyManga ? "#12131a" : colDim
                anchors.verticalCenter: parent.verticalCenter
                x: root.notifyManga ? (parent.width - width - 2) : 2

                Behavior on x { NumberAnimation { duration: 120 } }
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

          Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Util.alpha(colBorder, 0.5)
          }

          // Bottom Action Bar: Test | Sync
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            // Test Button
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(32)
              radius: Style.cornerRadius
              color: testNotifHover.containsMouse ? Util.alpha(colAccent, 0.3) : colCardBg
              border.color: testNotifHover.containsMouse ? colAccent : colBorder
              border.width: 1

              RowLayout {
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  text: "󰂚"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  color: colAccent
                }

                Text {
                  text: "Test"
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
              height: Style.space(32)
              radius: Style.cornerRadius
              color: root.canSync ? (syncBtnHover.containsMouse ? colAccent : Util.alpha(colAccent, 0.85)) : Util.alpha(colCardBg, 0.4)
              border.color: root.canSync ? colAccent : colBorder
              border.width: 1
              opacity: root.canSync ? 1.0 : 0.45

              RowLayout {
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  text: "󰑐"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  color: root.canSync ? "#12131a" : colDim
                }

                Text {
                  text: "Sync"
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
