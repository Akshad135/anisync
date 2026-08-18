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
  property int checkIntervalMins: host ? host.checkIntervalMins : 30
  property int unseenCount: host ? host.unseenCount : 0

  // UI state
  property int currentTab: 0 // 0: Upcoming, 1: Drops, 2: Watchlist, 3: Search, 4: Settings
  property string searchInputText: ""

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

    // ------------------------------------------------------------- Header
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

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

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Text {
          text: "Anime Watcher"
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          color: colForeground
        }

        Text {
          text: isFetching ? "Syncing with AniList..." : (lastSyncText.length > 0 ? ("Updated " + lastSyncText) : "Ready")
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: isFetching ? colAccent : colDim
        }
      }

      // Refresh Button
      Rectangle {
        width: Style.space(28)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: refreshHover.containsMouse ? colCardBg : "transparent"
        border.color: refreshHover.containsMouse ? colBorder : "transparent"
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "󰑐"
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          color: isFetching ? colAccent : (refreshHover.containsMouse ? colForeground : colDim)

          NumberAnimation on rotation {
            id: refreshRot
            running: root.isFetching
            from: 0
            to: 360
            loops: Animation.Infinite
            duration: 1000
          }
        }

        MouseArea {
          id: refreshHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (host && host.sync) host.sync()
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

    // ------------------------------------------------------------- Tabs
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(4)

      Repeater {
        model: [
          { index: 0, label: "Schedule", icon: "󰃭", badge: 0 },
          { index: 1, label: "Drops", icon: "󰓦", badge: root.unseenCount },
          { index: 2, label: "Watchlist", icon: "󰝚", badge: 0 },
          { index: 3, label: "Search", icon: "󰍉", badge: 0 },
          { index: 4, label: "Settings", icon: "󰒓", badge: 0 }
        ]

        delegate: Rectangle {
          id: tabBtn
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(28)
          radius: Style.cornerRadius
          color: root.currentTab === modelData.index 
            ? Util.alpha(colAccent, 0.22) 
            : (tabMouse.containsMouse ? Util.alpha(colCardBg, 0.6) : "transparent")
          border.color: root.currentTab === modelData.index ? colAccent : "transparent"
          border.width: 1

          RowLayout {
            anchors.centerIn: parent
            spacing: Style.space(4)

            Text {
              text: modelData.icon
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.currentTab === modelData.index ? colAccent : (tabMouse.containsMouse ? colForeground : colDim)
            }

            Text {
              text: modelData.label
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: root.currentTab === modelData.index
              color: root.currentTab === modelData.index ? colForeground : (tabMouse.containsMouse ? colForeground : colDim)
            }

            // Unseen badge
            Rectangle {
              visible: modelData.badge > 0
              width: Style.space(14)
              height: Style.space(14)
              radius: 7
              color: colAccent

              Text {
                anchors.centerIn: parent
                text: String(modelData.badge)
                font.family: root.fontFamily
                font.pixelSize: 9
                font.bold: true
                color: "#12131a"
              }
            }
          }

          MouseArea {
            id: tabMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.currentTab = modelData.index
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

    // ------------------------------------------------------------- Content Stack
    StackLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      currentIndex: root.currentTab

      // ===================================== TAB 0: Upcoming Schedule
      Item {
        id: tabSchedule

        ListView {
          id: upcomingListview
          anchors.fill: parent
          clip: true
          spacing: Style.space(6)
          model: root.upcomingList

          delegate: Rectangle {
            id: scheduleCard
            width: upcomingListview.width
            height: Style.space(64)
            radius: Style.cornerRadius
            color: schedMouse.containsMouse ? colCardBg : Util.alpha(colCardBg, 0.4)
            border.color: schedMouse.containsMouse ? colAccent : colBorder
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              spacing: Style.space(8)

              // Cover Art Image
              Rectangle {
                width: Style.space(38)
                height: Style.space(52)
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

              // Info
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
                  maximumLineCount: 1
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(6)

                  // Episode Badge
                  Rectangle {
                    radius: 3
                    color: Util.alpha(colAccent, 0.15)
                    implicitWidth: epText.implicitWidth + 8
                    implicitHeight: epText.implicitHeight + 4

                    Text {
                      id: epText
                      anchors.centerIn: parent
                      text: "Episode " + (modelData.nextEpisode || "?")
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      color: colAccent
                    }
                  }

                  Text {
                    text: modelData.progress > 0 ? ("Watched " + modelData.progress + (modelData.totalEpisodes ? ("/" + modelData.totalEpisodes) : "")) : ""
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    color: colDim
                    visible: modelData.progress > 0
                  }
                }

                Text {
                  text: Logic.formatAiringTime(modelData.airingAt)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: colMuted
                }
              }

              // Countdown Pill
              ColumnLayout {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                spacing: Style.space(2)

                Rectangle {
                  radius: Style.cornerRadius
                  color: Util.alpha(colAccent, 0.25)
                  implicitWidth: cdText.implicitWidth + 10
                  implicitHeight: cdText.implicitHeight + 6

                  Text {
                    id: cdText
                    anchors.centerIn: parent
                    text: Logic.formatCountdown(modelData.airingAt)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    color: colForeground
                  }
                }
              }
            }

            MouseArea {
              id: schedMouse
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
            visible: upcomingListview.count === 0 && !root.isFetching

            ColumnLayout {
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: "󰃭"
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                color: colBorder
              }

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.aniListUser ? "No upcoming episodes in your list" : "Set your AniList username in Settings"
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: colDim
              }

              Button {
                Layout.alignment: Qt.AlignHCenter
                text: root.aniListUser ? "Refresh" : "Open Settings"
                visible: true
                onClicked: {
                  if (root.aniListUser) {
                    if (host && host.sync) host.sync()
                  } else {
                    root.currentTab = 4
                  }
                }
              }
            }
          }
        }
      }

      // ===================================== TAB 1: Recent Drops
      Item {
        id: tabDrops

        ColumnLayout {
          anchors.fill: parent
          spacing: Style.space(6)

          RowLayout {
            Layout.fillWidth: true
            visible: root.recentDrops.length > 0

            Text {
              Layout.fillWidth: true
              text: "Recently released (last 48 hours)"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              color: colDim
            }

            Text {
              text: "Mark all seen"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              color: markAllHover.containsMouse ? colAccent : colDim
              visible: root.unseenCount > 0

              MouseArea {
                id: markAllHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (host && host.markAllSeen) host.markAllSeen()
                }
              }
            }
          }

          ListView {
            id: dropsListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Style.space(6)
            model: root.recentDrops

            delegate: Rectangle {
              id: dropCard
              width: dropsListView.width
              height: Style.space(64)
              radius: Style.cornerRadius
              color: modelData.isNew ? Util.alpha(colAccent, 0.12) : (dropMouse.containsMouse ? colCardBg : Util.alpha(colCardBg, 0.4))
              border.color: modelData.isNew ? colAccent : (dropMouse.containsMouse ? colAccent : colBorder)
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.space(6)
                spacing: Style.space(8)

                // Cover Art
                Rectangle {
                  width: Style.space(38)
                  height: Style.space(52)
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

                // Info
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(2)

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(4)

                    Text {
                      Layout.fillWidth: true
                      text: modelData.title
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                      color: colForeground
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }

                    Rectangle {
                      visible: modelData.isNew
                      radius: 3
                      color: colAccent
                      implicitWidth: newBadgeText.implicitWidth + 6
                      implicitHeight: newBadgeText.implicitHeight + 2

                      Text {
                        id: newBadgeText
                        anchors.centerIn: parent
                        text: "NEW"
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        font.bold: true
                        color: "#12131a"
                      }
                    }
                  }

                  Text {
                    text: "Episode " + modelData.episode + " · " + Logic.formatRelativeTime(modelData.airedAt)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    color: colAccent
                  }
                }

                // Action Buttons
                RowLayout {
                  spacing: Style.space(4)

                  Rectangle {
                    width: Style.space(26)
                    height: Style.space(26)
                    radius: Style.cornerRadius
                    color: openDropHover.containsMouse ? Util.alpha(colAccent, 0.3) : Util.alpha(colCardBg, 0.8)

                    Text {
                      anchors.centerIn: parent
                      text: "󰌹"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      color: openDropHover.containsMouse ? colForeground : colDim
                    }

                    MouseArea {
                      id: openDropHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (modelData.siteUrl && host && host.openUrl) {
                          host.openUrl(modelData.siteUrl)
                          if (host.markSeen) host.markSeen(modelData.id)
                        }
                      }
                    }
                  }

                  Rectangle {
                    visible: modelData.isNew
                    width: Style.space(26)
                    height: Style.space(26)
                    radius: Style.cornerRadius
                    color: markDropHover.containsMouse ? Util.alpha(colAccent, 0.3) : Util.alpha(colCardBg, 0.8)

                    Text {
                      anchors.centerIn: parent
                      text: "✓"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      color: markDropHover.containsMouse ? colAccent : colDim
                    }

                    MouseArea {
                      id: markDropHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (host && host.markSeen) host.markSeen(modelData.id)
                      }
                    }
                  }
                }
              }

              MouseArea {
                id: dropMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (modelData.siteUrl && host && host.openUrl) {
                    host.openUrl(modelData.siteUrl)
                    if (host.markSeen) host.markSeen(modelData.id)
                  }
                }
              }
            }

            // Empty state
            Item {
              anchors.fill: parent
              visible: dropsListView.count === 0

              ColumnLayout {
                anchors.centerIn: parent
                spacing: Style.space(6)

                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: "󰓦"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge
                  color: colBorder
                }

                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: "No recent drops in the last 48 hours"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  color: colDim
                }
              }
            }
          }
        }
      }

      // ===================================== TAB 2: Watchlist & Manga
      Item {
        id: tabWatchlist

        ListView {
          id: watchListView
          anchors.fill: parent
          clip: true
          spacing: Style.space(6)
          model: root.watchingList

          delegate: Rectangle {
            id: watchCard
            width: watchListView.width
            height: Style.space(56)
            radius: Style.cornerRadius
            color: watchMouse.containsMouse ? colCardBg : Util.alpha(colCardBg, 0.4)
            border.color: watchMouse.containsMouse ? colAccent : colBorder
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              spacing: Style.space(8)

              // Cover
              Rectangle {
                width: Style.space(32)
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
                    text: "Progress: " + modelData.progress + (modelData.totalEpisodes ? (" / " + modelData.totalEpisodes) : " eps")
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
                color: watchMouse.containsMouse ? colAccent : colDim
              }
            }

            MouseArea {
              id: watchMouse
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
            visible: watchListView.count === 0 && !root.isFetching

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
                text: "No currently watching anime found"
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: colDim
              }
            }
          }
        }
      }

      // ===================================== TAB 3: Search
      Item {
        id: tabSearch

        ColumnLayout {
          anchors.fill: parent
          spacing: Style.space(6)

          // Search Input Bar
          Rectangle {
            Layout.fillWidth: true
            height: Style.space(32)
            radius: Style.cornerRadius
            color: colCardBg
            border.color: searchField.activeFocus ? colAccent : colBorder
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(6)

              Text {
                text: "󰍉"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: colDim
              }

              TextInput {
                id: searchField
                Layout.fillWidth: true
                text: root.searchInputText
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: colForeground
                selectByMouse: true

                Text {
                  anchors.fill: parent
                  text: "Search anime or manga (e.g. Frieren, Solo Leveling)..."
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  color: colMuted
                  visible: !searchField.text && !searchField.activeFocus
                }

                onAccepted: {
                  if (host && host.search) host.search(text)
                }

                onTextChanged: {
                  root.searchInputText = text
                  searchDebounce.restart()
                }
              }

              Text {
                visible: searchField.text.length > 0
                text: "✕"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: clearSearchHover.containsMouse ? colForeground : colDim

                MouseArea {
                  id: clearSearchHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    searchField.text = ""
                    if (host && host.clearSearch) host.clearSearch()
                  }
                }
              }
            }
          }

          Timer {
            id: searchDebounce
            interval: 500
            repeat: false
            onTriggered: {
              if (searchField.text.trim().length >= 2 && host && host.search) {
                host.search(searchField.text.trim())
              }
            }
          }

          // Search Results
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

                // Cover
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
                  text: searchField.text.length > 0 ? (root.isSearching ? "Searching..." : "No results found") : "Type a title to search on AniList"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  color: colDim
                }
              }
            }
          }
        }
      }

      // ===================================== TAB 4: Settings
      Item {
        id: tabSettings

        Flickable {
          anchors.fill: parent
          contentHeight: settingsCol.implicitHeight
          clip: true

          ColumnLayout {
            id: settingsCol
            width: parent.width
            spacing: Style.space(12)

            // Account Sync Section
            Text {
              text: "Account Sync"
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              color: colForeground
            }

            // AniList Username
            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(4)

              Text {
                text: "AniList Username"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: colDim
              }

              Rectangle {
                Layout.fillWidth: true
                height: Style.space(32)
                radius: Style.cornerRadius
                color: colCardBg
                border.color: aniInput.activeFocus ? colAccent : colBorder
                border.width: 1

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)

                  TextInput {
                    id: aniInput
                    Layout.fillWidth: true
                    text: root.aniListUser
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    color: colForeground
                    selectByMouse: true

                    onEditingFinished: {
                      if (host && host.updateSetting) host.updateSetting("aniListUser", text.trim())
                    }
                  }
                }
              }
            }

            // MyAnimeList Username
            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(4)

              Text {
                text: "MyAnimeList (MAL) Username (Optional)"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: colDim
              }

              Rectangle {
                Layout.fillWidth: true
                height: Style.space(32)
                radius: Style.cornerRadius
                color: colCardBg
                border.color: malInput.activeFocus ? colAccent : colBorder
                border.width: 1

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)

                  TextInput {
                    id: malInput
                    Layout.fillWidth: true
                    text: root.malUser
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    color: colForeground
                    selectByMouse: true

                    onEditingFinished: {
                      if (host && host.updateSetting) host.updateSetting("malUser", text.trim())
                    }
                  }
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
                text: "Notify on new Anime episodes"
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
                text: "Notify on Manga chapters"
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

            // Actions Section
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)

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

              Rectangle {
                Layout.fillWidth: true
                height: Style.space(32)
                radius: Style.cornerRadius
                color: saveBtnHover.containsMouse ? colAccent : Util.alpha(colAccent, 0.8)

                RowLayout {
                  anchors.centerIn: parent
                  spacing: Style.space(4)

                  Text {
                    text: "󰑐"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    color: "#12131a"
                  }

                  Text {
                    text: "Save & Sync Now"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    color: "#12131a"
                  }
                }

                MouseArea {
                  id: saveBtnHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (host) {
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
}
