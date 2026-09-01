import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.estebanhiram.hypr-autoscroll"
  ipcTarget: "hypr-autoscroll-widget"

  readonly property string icon: "󰍽"
  readonly property string sensitivityScript: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/" + moduleName + "/scripts/set-sensitivity.sh"

  property bool pluginAvailable: false
  property bool pluginEnabled: false
  property bool middleModeEnabled: false
  property bool autoscrollActive: false
  property real sensitivity: 4
  property real pendingSensitivity: 4
  property bool sensitivityQueued: false
  property real wheelAccumulator: 0
  property string focusSection: "toggle"
  property bool cursorActive: false

  readonly property string toggleHint: middleModeEnabled
    ? "Restore normal middle click"
    : "Enable middle-button autoscroll"

  function applyStatus(raw) {
    var status = Model.parseStatus(raw)
    if (!status) {
      pluginAvailable = false
      return
    }

    pluginAvailable = status.available
    pluginEnabled = status.enabled
    middleModeEnabled = status.middleModeEnabled
    autoscrollActive = status.active
    if (!sensitivitySlider.dragging && !sensitivityProc.running)
      sensitivity = status.sensitivity
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggleMiddleMode() {
    if (!pluginAvailable || actionProc.running) return
    actionProc.command = ["hyprctl", "-j", "hypr-autoscroll", "toggle"]
    actionProc.running = true
  }

  function previewSensitivity(value) {
    sensitivity = Model.clampSensitivity(value)
  }

  function setSensitivity(value) {
    pendingSensitivity = Model.clampSensitivity(value)
    sensitivity = pendingSensitivity

    if (sensitivityProc.running) {
      sensitivityQueued = true
      return
    }

    sensitivityQueued = false
    sensitivityProc.command = ["bash", sensitivityScript, pendingSensitivity.toFixed(2)]
    sensitivityProc.running = true
  }

  function moveCursor(direction) {
    cursorActive = true
    if (direction !== 0)
      focusSection = focusSection === "toggle" ? "sensitivity" : "toggle"
  }

  function activateCursor() {
    if (focusSection === "toggle") toggleMiddleMode()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      focusSection = "toggle"
      cursorActive = false
      refresh()
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    command: ["hyprctl", "-j", "hypr-autoscroll"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    onRunningChanged: if (!running) root.refresh()
  }

  Process {
    id: sensitivityProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    onRunningChanged: {
      if (running) return
      if (root.sensitivityQueued) root.setSensitivity(root.pendingSensitivity)
      else root.refresh()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: root.middleModeEnabled
    dimmed: !root.pluginAvailable || !root.pluginEnabled || !root.middleModeEnabled
    tooltipText: root.pluginAvailable
      ? (root.middleModeEnabled ? "Autoscroll on" : "Autoscroll off")
      : "Autoscroll plugin unavailable"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton || mouseButton === Qt.MiddleButton)
        root.toggleMiddleMode()
      else
        root.toggle()
    }
    onWheelMoved: function(delta) {
      if (!root.pluginAvailable) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps !== 0)
        root.setSensitivity(root.sensitivity + wheel.steps * 0.25)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(310))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(300))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0 && root.focusSection === "sensitivity")
          root.setSensitivity(root.sensitivity + dx * 0.25)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(14)

        Item {
          id: hero
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, modeSwitch.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.icon
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            opacity: root.middleModeEnabled ? 1 : 0.5
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: modeSwitch.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "Autoscroll"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: !root.pluginAvailable
                ? "PLUGIN UNAVAILABLE"
                : (root.middleModeEnabled ? "MIDDLE BUTTON READY" : "NORMAL MIDDLE CLICK")
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }

          ToggleSwitch {
            id: modeSwitch
            checked: root.middleModeEnabled
            busy: actionProc.running
            enabled: root.pluginAvailable && root.pluginEnabled
            hasCursor: root.cursorActive && root.focusSection === "toggle"
            foreground: root.bar.foreground
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onHovered: function(hovered) {
              if (!hovered) return
              root.cursorActive = true
              root.focusSection = "toggle"
            }
            onToggled: root.toggleMiddleMode()

            PanelToolTip {
              visible: modeSwitch.containsMouse
              text: root.toggleHint
              fontFamily: root.bar.fontFamily
            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: Math.max(sensitivityHeader.implicitHeight, sensitivityValue.implicitHeight)

            PanelSectionHeader {
              id: sensitivityHeader
              text: "SENSITIVITY"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: sensitivityValue
              textFormat: Text.PlainText
              text: (sensitivitySlider.dragging ? sensitivitySlider.liveValue : root.sensitivity).toFixed(2) + "×"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          CursorSurface {
            width: parent.width
            height: sensitivitySlider.implicitHeight + Style.spacing.controlGap
            hasCursor: root.cursorActive && root.focusSection === "sensitivity"
            foreground: root.bar.foreground
            outline: true

            PanelSlider {
              id: sensitivitySlider
              bar: root.bar
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              minimum: 0.5
              maximum: 10
              step: 0.25
              tickCount: 8
              value: root.sensitivity
              onMoved: function(value) { root.previewSensitivity(value) }
              onReleased: function(value) { root.setSensitivity(value) }
            }

            HoverHandler {
              onHoveredChanged: if (hovered) {
                root.cursorActive = true
                root.focusSection = "sensitivity"
              }
            }
          }

          Text {
            width: parent.width
            text: Model.sensitivityName(root.sensitivity).toUpperCase()
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
