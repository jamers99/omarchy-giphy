import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// GIF picker in the shape of the built-in emoji picker. Searches Giphy and
// hands the chosen GIF to ./insert, which pastes it into the focused window.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginId: (manifest && manifest.id) || "james.giphy"
  readonly property string sourceDir: (manifest && manifest.__sourceDir) || (home + "/.config/omarchy/plugins/james.giphy")
  readonly property string keyPath: home + "/.config/omarchy/giphy-key"

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property string apiKey: ""
  property string status: ""
  property int requestId: 0

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(720), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)
  readonly property int columns: 4

  onApiKeyChanged: if (root.opened) root.search()

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.search()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Empty search shows trending GIFs.
  function search() {
    var id = ++root.requestId
    searchTimer.stop()
    displayModel.clear()
    root.selectedIndex = 0

    if (!root.apiKey) {
      root.status = ""
      return
    }

    var query = root.filterText.trim()
    root.status = "Searching…"

    var url = "https://api.giphy.com/v1/gifs/" + (query ? "search" : "trending")
      + "?limit=40&rating=pg&api_key=" + encodeURIComponent(root.apiKey)
      + (query ? "&q=" + encodeURIComponent(query) : "")

    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE || id !== root.requestId) return

      if (xhr.status === 401 || xhr.status === 403) {
        root.status = "Giphy rejected the API key in ~/.config/omarchy/giphy-key"
        return
      }
      if (xhr.status !== 200) {
        root.status = "Couldn't reach Giphy"
        return
      }

      var gifs = []
      try { gifs = JSON.parse(xhr.responseText).data || [] } catch (e) {}

      for (var i = 0; i < gifs.length; i++) {
        var images = gifs[i].images || {}
        var full = images.downsized || images.original
        if (!images.fixed_width || !full) continue
        displayModel.append({ gifId: gifs[i].id, preview: images.fixed_width.url, full: full.url })
      }

      root.status = displayModel.count ? "" : "No GIFs for “" + query + "”"
    }
    xhr.open("GET", url)
    xhr.send()
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    searchTimer.restart()
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.selectedIndex = Math.max(0, Math.min(displayModel.count - 1, root.selectedIndex + delta))
    resultGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.dismiss()
    Quickshell.execDetached([root.sourceDir + "/insert", row.full, row.gifId])
  }

  ListModel { id: displayModel }

  Timer {
    id: searchTimer
    interval: 300
    onTriggered: root.search()
  }

  FileView {
    path: root.keyPath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.apiKey = text().trim()
    onLoadFailed: root.apiKey = ""
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-gifs"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-root.columns)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(root.columns)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (searchTimer.running) root.search()
            else root.activateIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Search GIFs…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing

          GridView {
            id: resultGrid
            anchors.fill: parent
            model: displayModel
            clip: true
            cellWidth: Math.floor(width / root.columns)
            cellHeight: Math.floor(cellWidth * 0.75)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
              id: cell
              required property int index
              required property string preview

              readonly property bool hasCursor: index === root.selectedIndex

              width: resultGrid.cellWidth
              height: resultGrid.cellHeight

              Rectangle {
                anchors.fill: parent
                anchors.margins: Style.space(3)
                radius: root.cornerRadius
                color: root.selectedBackground
                opacity: 0.35
              }

              AnimatedImage {
                anchors.fill: parent
                anchors.margins: Style.space(3)
                source: cell.preview
                fillMode: Image.PreserveAspectCrop
              }

              Rectangle {
                anchors.fill: parent
                anchors.margins: Style.space(1)
                visible: cell.hasCursor
                radius: root.cornerRadius
                color: "transparent"
                border.width: Math.max(2, Style.space(3))
                border.color: root.selectedText
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) root.selectedIndex = cell.index
                onClicked: root.activateIndex(cell.index)
              }
            }
          }

          Text {
            anchors.centerIn: parent
            width: parent.width
            visible: displayModel.count === 0
            textFormat: Text.PlainText
            text: root.status
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // Setup steps, shown until a key is saved.
          Text {
            anchors.centerIn: parent
            width: Math.min(parent.width, Style.space(520))
            visible: !root.apiKey
            textFormat: Text.StyledText
            text: "<b>Giphy API key needed</b><br><br>"
              + "1. Open <a href=\"https://developers.giphy.com/dashboard\">developers.giphy.com/dashboard</a> and sign in<br>"
              + "2. Click <b>Create an API Key</b> and choose <b>API</b><br>"
              + "3. Enter any name and description, accept the terms<br>"
              + "4. Copy the key and run:<br><br>"
              + "&nbsp;&nbsp;echo 'YOUR_KEY' &gt; ~/.config/omarchy/giphy-key<br><br>"
              + "GIFs appear here as soon as the key is saved."
            color: root.foreground
            linkColor: root.selectedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            lineHeight: 1.2
            wrapMode: Text.WordWrap
            onLinkActivated: function(link) {
              root.dismiss()
              Qt.openUrlExternally(link)
            }

            HoverHandler {
              cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
          }
        }
      }
    }
  }
}
