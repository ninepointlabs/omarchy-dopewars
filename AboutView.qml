import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "About.js" as About

// The panel's About page: who made Dopewars, its version and license, the
// original game it comes from, where to get help, and what it does with your
// data. Panel.qml swaps it in for the game (info button or the `about` IPC
// call); Back or Escape returns, closing the panel resets it.
Column {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family
  property string version: ""
  property string licenseText: ""
  property bool showLicense: false
  property string notice: ""

  signal backRequested()

  readonly property string quickshellVersion: About.probedVersion(function(a, b) { return Quickshell.hasVersion(a, b) }, 0)
  readonly property string qtVersion: About.probedVersion(function(a, b) { return Quickshell.hasQtVersion(a, b) }, 6)
  readonly property string details: About.details(root.version, root.quickshellVersion, root.qtVersion,
    (Quickshell.env("XDG_CURRENT_DESKTOP") || "unknown desktop") + ", " + Qt.platform.pluginName)
  readonly property real labelWidth: Style.space(72)
  readonly property real valueWidth: width - labelWidth - Style.space(12)

  function copy(text, what) {
    Quickshell.clipboardText = text
    root.notice = what + " copied"
    noticeTimer.restart()
  }

  spacing: Style.space(10)
  onVisibleChanged: if (!visible) { root.showLicense = false; root.notice = "" }

  Timer { id: noticeTimer; interval: 2500; onTriggered: root.notice = "" }

  component Label: Text {
    width: root.labelWidth
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  component Value: Text {
    width: root.valueWidth
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(titleRow.implicitHeight, backButton.implicitHeight)

    Row {
      id: titleRow
      anchors.left: parent.left
      anchors.right: backButton.left
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(12)

      OpticalGlyph {
        id: appIcon
        width: Style.space(40)
        height: width
        anchors.verticalCenter: parent.verticalCenter
        text: "󰐂"
        fontFamily: root.fontFamily
        fontSize: Style.space(30)
        color: root.accent
      }

      Column {
        width: parent.width - appIcon.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          textFormat: Text.PlainText
          text: About.NAME
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          text: About.TAGLINE
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          objectName: "aboutVersion"
          textFormat: Text.PlainText
          text: "Version " + (root.version || "unknown")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Button {
      id: backButton
      objectName: "aboutBack"
      anchors.right: parent.right
      anchors.top: parent.top
      iconText: "󰁍"
      text: "Back"
      tooltipText: "Back to the game (Esc)"
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      iconSize: Style.font.body
      horizontalPadding: Style.space(8)
      verticalPadding: Style.space(3)
      onClicked: root.backRequested()
    }
  }

  PanelSeparator { foreground: root.foreground }

  Grid {
    width: parent.width
    columns: 2
    columnSpacing: Style.space(12)
    rowSpacing: Style.space(8)

    Label { text: "MADE BY" }
    Value { text: About.ORGANIZATION }

    Label { text: "CREATED" }
    Value { text: About.CREATED }

    Label { text: "LICENSE" }
    Column {
      width: root.valueWidth
      spacing: Style.space(4)
      Value { text: About.LICENSE }
      Button {
        objectName: "aboutLicense"
        text: root.showLicense ? "Hide license" : "Read license"
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(3)
        onClicked: root.showLicense = !root.showLicense
      }
    }

    Label { text: "CREDITS" }
    Value { objectName: "aboutCredits"; text: About.CREDITS }

    Label { text: "SUPPORT" }
    Column {
      width: root.valueWidth
      spacing: Style.space(4)
      Value { text: About.SUPPORT_EMAIL }
      Flow {
        width: parent.width
        spacing: Style.space(6)
        Button {
          objectName: "aboutEmail"
          text: "Email"
          tooltipText: "Opens your mail app with the version details filled in"
          bordered: true
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(8)
          verticalPadding: Style.space(3)
          onClicked: Qt.openUrlExternally(About.mailto(root.version, root.details))
        }
        Button {
          objectName: "aboutCopyEmail"
          text: "Copy"
          bordered: true
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(8)
          verticalPadding: Style.space(3)
          onClicked: root.copy(About.SUPPORT_EMAIL, "Address")
        }
        Button {
          objectName: "aboutCopyDetails"
          text: "Copy version details"
          bordered: true
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(8)
          verticalPadding: Style.space(3)
          onClicked: root.copy(root.details, "Version details")
        }
      }
      Text {
        visible: root.notice !== ""
        textFormat: Text.PlainText
        text: root.notice
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Label { text: "PRIVACY" }
    Value { objectName: "aboutPrivacy"; text: About.PRIVACY; font.pixelSize: Style.font.caption }

    Label { text: "BUILT WITH" }
    Value { objectName: "aboutBuiltWith"; text: About.builtWith(root.quickshellVersion, root.qtVersion); color: root.dim; font.pixelSize: Style.font.caption }
  }

  Rectangle {
    width: parent.width
    height: Style.space(220)
    visible: root.showLicense
    color: "transparent"
    radius: Style.cornerRadius
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)

    Flickable {
      id: licenseView
      anchors.fill: parent
      anchors.margins: Style.space(8)
      clip: true
      contentHeight: licenseBody.implicitHeight
      boundsBehavior: Flickable.StopAtBounds

      Text {
        id: licenseBody
        objectName: "aboutLicenseText"
        width: licenseView.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: About.licenseBody(root.licenseText) || "LICENSE could not be read from the plugin folder."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
