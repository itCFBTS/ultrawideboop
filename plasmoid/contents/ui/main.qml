// Sensei Battery — tray widget polling `ultrawideboop` (read-only queries, same as GG/Solaar do).
// Tray number: cheap single-query poll every 5 min. Popup: full query on open/refresh.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    property int mouseBat: -1
    property int baseBat: -1
    property string firmware: ""
    property string sleepTimer: ""
    property var dpiStages: []    // [{val, active}]
    property var pollLevels: []   // [{label, active}]
    property string maxPerf: ""   // "on" / "off" / "" (unknown)
    property string lastUpdate: ""
    property string err: "querying…"

    // Runs through /bin/sh; Plasma's PATH often lacks the per-user bin dirs.
    readonly property string binPath: 'PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH" ultrawideboop'
    readonly property string cmdBattery: binPath + " --battery"
    readonly property string cmdFull: binPath + " -v"
    readonly property bool low: mouseBat >= 0 && mouseBat <= 15

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            disconnectSource(source)
            const out = data["stdout"] || ""
            if (data["exit code"] === 127) {
                root.err = "ultrawideboop not installed"
                return
            }
            if (data["exit code"] !== 0) {
                root.err = "mouse not reachable"
                return
            }
            if (source === root.cmdBattery) {
                const m = out.trim().match(/^(\d+)\s+(\d+)$/)
                if (m) {
                    root.mouseBat = parseInt(m[1])
                    root.baseBat = parseInt(m[2])
                    root.err = ""
                    root.lastUpdate = new Date().toLocaleTimeString(Qt.locale(), "hh:mm")
                } else {
                    root.err = "no battery data"
                }
            } else {
                root.parseFull(out)
            }
        }
    }

    function parseFull(out) {
        const mb = out.match(/mouse battery\s*:\s*(\d+)%/)
        const bb = out.match(/base battery\s*:\s*(\d+)%/)
        if (mb) root.mouseBat = parseInt(mb[1])
        if (bb) root.baseBat = parseInt(bb[1])
        const fw = out.match(/firmware\s*:\s*(\S+)/)
        root.firmware = fw ? fw[1] : ""
        const st = out.match(/sleep timer\s*:\s*(\d+)\s*s/)
        root.sleepTimer = st ? st[1] : ""
        const dm = out.match(/dpi stages\s*:\s*(.+?)\s{2,}\(/)
        root.dpiStages = dm
            ? dm[1].trim().split(/\s+/).map(t => ({ active: t.startsWith("["), val: t.replace(/[\[\]]/g, "") }))
            : []
        const pm = out.match(/poll profiles\s*:\s*(.+?)\s{2,}\(/)
        root.pollLevels = pm
            ? pm[1].trim().split(/\s+/).map(t => ({ active: t.startsWith("["), label: t.replace(/[\[\]]/g, "") }))
            : []
        const mp = out.match(/max perf(?:ormance)?\s*:\s*(on|off)/)
        root.maxPerf = mp ? mp[1] : ""
        root.err = mb ? "" : "no data"
        root.lastUpdate = new Date().toLocaleTimeString(Qt.locale(), "hh:mm")
    }

    function refreshBattery() { exec.connectSource(cmdBattery) }
    function refreshFull() { exec.connectSource(cmdFull) }

    Timer { interval: 5 * 60 * 1000; running: true; repeat: true; onTriggered: root.refreshBattery() }
    Component.onCompleted: refreshBattery()
    onExpandedChanged: { if (root.expanded) refreshFull() }

    Plasmoid.status: root.low ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus
    toolTipMainText: mouseBat >= 0 ? ("Mouse " + mouseBat + "% · Base " + baseBat + "%") : ("Sensei Pro: " + err)
    toolTipSubText: lastUpdate !== "" ? ("updated " + lastUpdate) : ""

    compactRepresentation: MouseArea {
        id: compactRoot
        implicitWidth: fullRow.implicitWidth + Kirigami.Units.smallSpacing * 2
        readonly property bool tight: width > 0 && width < fullRow.implicitWidth
        property bool wasExpanded: false
        onPressed: wasExpanded = root.expanded
        onClicked: root.expanded = !wasExpanded

        Item {
            anchors.fill: parent
            visible: compactRoot.tight
            Kirigami.Icon {
                anchors.fill: parent
                source: "input-mouse-symbolic"
                opacity: 0.45
            }
            PC3.Label {
                anchors.centerIn: parent
                text: root.mouseBat >= 0 ? root.mouseBat : "–"
                color: root.low ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                font.bold: true
                fontSizeMode: Text.Fit
                minimumPointSize: 6
                style: Text.Outline
                styleColor: Kirigami.Theme.backgroundColor
            }
        }

        RowLayout {
            id: fullRow
            anchors.centerIn: parent
            visible: !compactRoot.tight
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                source: "input-mouse-symbolic"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            PC3.Label {
                text: root.mouseBat >= 0 ? root.mouseBat + "%" : "–"
                color: root.low ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                font.bold: root.low
            }
            Kirigami.Icon {
                source: "battery-symbolic"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            PC3.Label {
                text: root.baseBat >= 0 ? root.baseBat + "%" : "–"
            }
        }
    }

    fullRepresentation: ColumnLayout {
        spacing: Kirigami.Units.largeSpacing
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 14

        component BatteryRow: ColumnLayout {
            property string label
            property string iconName
            property int value: -1
            property bool warn: false
            spacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: iconName
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }
                PC3.Label { text: label }
                Item { Layout.fillWidth: true }
                PC3.Label {
                    text: value >= 0 ? value + "%" : "—"
                    font.bold: true
                    color: warn ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                }
            }
            PC3.ProgressBar {
                from: 0; to: 100
                value: Math.max(0, parent.value)
                Layout.fillWidth: true
            }
        }

        component Pill: Rectangle {
            property string text
            property bool active: false
            property bool small: false
            radius: height / 2
            color: active ? Kirigami.Theme.highlightColor : "transparent"
            implicitWidth: pillLabel.implicitWidth + Kirigami.Units.largeSpacing * (small ? 1.2 : 1.6)
            implicitHeight: pillLabel.implicitHeight + Kirigami.Units.smallSpacing * (small ? 1.2 : 1.6)
            PC3.Label {
                id: pillLabel
                anchors.centerIn: parent
                text: parent.text
                font.bold: parent.active
                font.pointSize: parent.small ? Kirigami.Theme.smallFont.pointSize : Kirigami.Theme.defaultFont.pointSize
                color: parent.active ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                opacity: parent.active ? 1.0 : 0.65
            }
        }

        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.leftMargin: Kirigami.Units.largeSpacing * 2
            Layout.rightMargin: Kirigami.Units.largeSpacing * 2

            BatteryRow { label: "Mouse"; iconName: "input-mouse-symbolic"; value: root.mouseBat; warn: root.low }
            BatteryRow { label: "Base station"; iconName: "battery-symbolic"; value: root.baseBat }
        }

        Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }

        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.alignment: Qt.AlignHCenter
            visible: root.dpiStages.length > 0

            Kirigami.Heading { level: 5; text: "DPI stages"; opacity: 0.8; Layout.alignment: Qt.AlignHCenter }
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Layout.alignment: Qt.AlignHCenter
                Repeater {
                    model: root.dpiStages
                    delegate: Pill {
                        required property var modelData
                        text: modelData.val
                        active: modelData.active
                    }
                }
            }
        }

        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.alignment: Qt.AlignHCenter
            visible: root.pollLevels.length > 0

            Kirigami.Heading { level: 5; text: "Polling · sensor/UWB Hz"; opacity: 0.8; Layout.alignment: Qt.AlignHCenter }
            ColumnLayout {
                spacing: Kirigami.Units.smallSpacing / 2
                Layout.alignment: Qt.AlignHCenter
                Repeater {
                    model: root.pollLevels
                    delegate: Pill {
                        required property var modelData
                        text: modelData.label.replace(":", "  ·  ").replace("/", " / ")
                        active: modelData.active
                        small: true
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.alignment: Qt.AlignHCenter
            visible: root.maxPerf !== ""

            Kirigami.Heading { level: 5; text: "Max Performance"; opacity: 0.8 }
            Pill {
                text: root.maxPerf === "on" ? "On" : "Off"
                active: root.maxPerf === "on"
                small: true
            }
        }

        PC3.Label {
            visible: root.err !== ""
            text: root.err
            opacity: 0.7
            Layout.alignment: Qt.AlignHCenter
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            PC3.Label {
                text: {
                    let parts = []
                    if (root.firmware !== "") parts.push("FW " + root.firmware)
                    if (root.sleepTimer !== "") parts.push("sleep " + root.sleepTimer + " s")
                    if (root.lastUpdate !== "") parts.push("updated " + root.lastUpdate)
                    return parts.join(" · ")
                }
                opacity: 0.6
            }
            PC3.ToolButton {
                icon.name: "view-refresh"
                text: "Refresh"
                onClicked: root.refreshFull()
            }
        }
    }
}
