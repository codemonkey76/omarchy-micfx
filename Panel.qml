import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: fx
  moduleName: "io.github.codemonkey76.micfx"
  ipcTarget: "io.github.codemonkey76.micfx"
  manageIpc: false

  // ---- Configuration ------------------------------------------------------
  // The helper is Python, bundled beside this file so the plugin is
  // self-contained, and run isolated (-I) so the environment can't change
  // what it imports.
  readonly property string cli: String(Qt.resolvedUrl("omarchy-mic-fx")).replace(/^file:\/\//, "")
  readonly property int refreshSeconds: Math.max(3, parseInt(setting("refreshSeconds", 10), 10) || 10)

  function helper(args) { return ["python3", "-I", cli].concat(args) }

  // ---- State --------------------------------------------------------------
  property var status: null
  property bool everLoaded: false
  // Values the user just set, shown until the helper reports them back, so a
  // slider doesn't snap back while its change is in flight.
  property var pending: ({})
  property var queue: []
  property string busyAction: ""
  property string message: ""
  property bool messageIsError: false

  // Not "settings": the Panel base already uses that name for this widget's
  // own shell.json options, which setting() reads.
  readonly property var fxSettings: status && status.settings ? status.settings : ({})
  readonly property bool running: status !== null && status.present === true
  readonly property bool isDefault: status !== null && status.isDefault === true
  readonly property bool depsOk: status !== null && status.deps !== undefined && status.deps.rnnoise === true && status.deps.lsp === true
  readonly property string deviceName: status && status.device ? (status.device.description || status.device.name || "") : ""
  readonly property var deviceOptions: status && status.devices
    ? status.devices.map(function(d) { return { value: d.name, label: d.description || d.name } }) : []

  // ---- Wizard state -------------------------------------------------------
  property bool wizard: false
  property int step: -1                 // -1 intro, 0..2 recording phases, 3 suggestions
  property bool recording: false
  property real levelRaw: -120
  property real levelFx: -120
  property real elapsed: 0
  property var results: ({})
  property var solution: null
  property string wizardError: ""
  // The before/after preview: "" (not built), "preparing", "ready" or "failed".
  property string previewState: ""
  property real previewProgress: 0
  property string playing: ""           // "before" or "after" while it plays
  property real playProgress: 0
  property var playQueue: []
  readonly property var phase: step >= 0 && step < Model.PHASES.length ? Model.PHASES[step] : null
  readonly property bool atSuggestions: step === Model.PHASES.length

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function value(key, fallback) {
    if (pending[key] !== undefined) return pending[key]
    var v = fxSettings[key]
    return v === undefined || v === null ? fallback : v
  }

  function withKey(obj, key, v) {
    var next = {}
    for (var k in obj) next[k] = obj[k]
    next[key] = v
    return next
  }

  function without(obj, key) {
    var next = {}
    for (var k in obj) if (k !== key) next[k] = obj[k]
    return next
  }

  function flash(text, isError) {
    message = text
    messageIsError = isError === true
    messageTimer.restart()
  }

  function parseLine(text) {
    try { return JSON.parse(String(text || "").trim()) } catch (e) { return null }
  }

  // ---- Reading ------------------------------------------------------------
  function refresh() {
    if (statusProc.running) return
    statusProc.command = helper(["status"])
    statusProc.running = true
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parse(text)
        if (!parsed) return
        fx.status = parsed
        fx.everLoaded = true
        if (!setProc.running && fx.queue.length === 0) fx.pending = ({})
      }
    }
  }

  // Polls harder while the panel is open, and not at all while the wizard
  // records (the helper is busy then, and the chain is bypassed on purpose).
  Timer {
    interval: (fx.opened ? 3 : fx.refreshSeconds) * 1000
    running: !fx.recording
    repeat: true
    triggeredOnStart: true
    onTriggered: fx.refresh()
  }

  // ---- Changing settings --------------------------------------------------
  // A slider emits a value per pixel of travel. Queue the key once and send
  // its latest value when the drag pauses, rather than one change per pixel.
  function setValue(key, v) {
    pending = withKey(pending, key, v)
    if (queue.indexOf(key) === -1) {
      var q = queue.slice()
      q.push(key)
      queue = q
    }
    sendTimer.restart()
  }

  Timer {
    id: sendTimer
    interval: 250
    onTriggered: fx.sendNext()
  }

  function sendNext() {
    if (setProc.running || queue.length === 0) return
    var key = queue[0]
    queue = queue.slice(1)
    var v = pending[key]
    setProc.key = key
    setProc.command = helper(["set", key, typeof v === "boolean" ? (v ? "on" : "off") : String(v)])
    setProc.running = true
  }

  Process {
    id: setProc
    property string key: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = fx.parseLine(text)
        if (r && r.ok === false) fx.flash(r.error || ("Couldn't change " + setProc.key), true)
      }
    }
    onExited: {
      if (fx.queue.length > 0) sendTimer.restart()
      else fx.refresh()
    }
  }

  function act(args, busyLabel, doneText) {
    if (actionProc.running) return
    busyAction = busyLabel
    message = ""
    messageIsError = false
    actionProc.doneText = doneText
    actionProc.command = helper(args)
    actionProc.running = true
  }

  Process {
    id: actionProc
    property string doneText: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = fx.parseLine(text)
        if (r && r.ok === false) fx.flash(r.error || "That didn't work", true)
        else if (r && r.ok === true) fx.flash(actionProc.doneText, false)
      }
    }
    onExited: {
      fx.busyAction = ""
      fx.refresh()
    }
  }

  function toggleOn() {
    if (!status || busyAction !== "" || recording) return
    if (running) act(["off"], "Turning off…", "Mic FX is off; apps use the raw mic again")
    else act(["on"], "Turning on…", "Mic FX is on and is your default input")
  }

  function makeDefault() { act(["default"], "Switching…", "Mic FX is your default input") }

  function chooseDevice(name) {
    if (!name || (status && status.device && status.device.name === name)) return
    var label = name
    for (var i = 0; i < deviceOptions.length; i++) if (deviceOptions[i].value === name) label = deviceOptions[i].label
    act(["device", name], "Switching microphone…", "Now processing " + label)
  }
  function resetAll() { act(["reset"], "Resetting…", "Back to the default settings") }

  Timer {
    id: messageTimer
    interval: fx.messageIsError ? 8000 : (fx.message.length > 40 ? 5000 : 2500)
    onTriggered: fx.message = ""
  }

  // ---- Wizard -------------------------------------------------------------
  function openWizard() {
    wizard = true
    step = -1
    results = ({})
    solution = null
    wizardError = ""
    clearClips()          // any left from an earlier run
  }

  function cancelWizard() {
    // Stopping the helper mid-recording is safe: it puts the user's settings
    // back however the recording ends.
    if (calibProc.running) {
      calibProc.running = false
      return
    }
    if (playing !== "" || previewState === "preparing") {
      stopPreview()
      return
    }
    closeWizard()
  }

  // However the wizard closes, its audio clips are deleted.
  function closeWizard() {
    stopPreview()
    wizard = false
    clearClips()
  }

  function startPhase() {
    if (!phase || calibProc.running) return
    wizardError = ""
    levelRaw = -120
    levelFx = -120
    elapsed = 0
    results = without(results, phase.id)
    previewState = ""     // a new recording makes any preview stale
    calibProc.phaseId = phase.id
    calibProc.command = helper(["calibrate", phase.id, String(phase.seconds)])
    recording = true
    calibProc.running = true
    if (phase.typing === true) {
      typingField.text = ""
      typingField.forceActiveFocus()
    }
  }

  Process {
    id: calibProc
    property string phaseId: ""
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line)
        if (s.indexOf("level ") === 0) {
          var parts = s.split(" ")
          fx.levelRaw = parseFloat(parts[1])
          fx.levelFx = parseFloat(parts[2])
          fx.elapsed = parseFloat(parts[3])
        } else if (s.indexOf("result ") === 0) {
          var r = fx.parseLine(s.slice(7))
          if (r) fx.results = fx.withKey(fx.results, calibProc.phaseId, r)
        } else {
          var e = fx.parseLine(s)
          if (e && e.ok === false) fx.wizardError = e.error || "Recording failed"
        }
      }
    }
    onExited: function(exitCode) {
      fx.recording = false
      if (exitCode !== 0 && fx.wizardError === "" && fx.results[calibProc.phaseId] === undefined)
        fx.wizardError = "Recording stopped before it finished."
      fx.runClear()
    }
  }

  function solve() {
    if (solveProc.running) return
    wizardError = ""
    solveProc.command = helper(["calibrate", "solve"])
    solveProc.running = true
  }

  Process {
    id: solveProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = fx.parseLine(text)
        if (r && r.ok === true) {
          fx.solution = r
          fx.step = Model.PHASES.length
        } else {
          fx.wizardError = r && r.error ? r.error : "Couldn't work out settings from those recordings."
        }
      }
    }
  }

  // ---- Before/after preview -----------------------------------------------
  // The typing mixed over the talking, as recorded and then through the
  // suggested settings. Built once by the helper (a throwaway copy of the
  // chain, so the real one is never touched), then played on request.
  function hearDifference(sequence) {
    playQueue = sequence
    if (previewState === "ready") {
      playNext()
      return
    }
    if (previewProc.running) return
    wizardError = ""
    previewState = "preparing"
    previewProgress = 0
    previewProc.command = helper(["calibrate", "preview"])
    previewProc.running = true
  }

  function playNext() {
    if (playProc.running || playQueue.length === 0) return
    var which = playQueue[0]
    playQueue = playQueue.slice(1)
    playing = which
    playProgress = 0
    playProc.command = helper(["calibrate", "play", which])
    playProc.running = true
  }

  function stopPreview() {
    playQueue = []
    if (playProc.running) playProc.running = false
    if (previewProc.running) previewProc.running = false
    if (previewState === "preparing") previewState = ""
  }

  // Waits for a stopped preview or playback to finish exiting, so a clip
  // can't be written back after it was cleared.
  property bool clearWanted: false

  function clearClips() {
    previewState = ""
    clearWanted = true
    runClear()
  }

  function runClear() {
    if (!clearWanted || clearProc.running || previewProc.running || playProc.running || calibProc.running) return
    clearWanted = false
    clearProc.command = helper(["calibrate", "clear"])
    clearProc.running = true
  }

  Process {
    id: previewProc
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line)
        if (s.indexOf("progress ") === 0) {
          fx.previewProgress = parseFloat(s.slice(9))
          return
        }
        var r = fx.parseLine(s)
        if (r && r.ok === true) fx.previewState = "ready"
        else if (r && r.ok === false) {
          fx.previewState = "failed"
          fx.wizardError = r.error || "Couldn't build the preview."
        }
      }
    }
    onExited: function(exitCode) {
      if (fx.previewState === "preparing") fx.previewState = exitCode === 0 ? "ready" : ""
      if (fx.previewState === "ready") fx.playNext()
      else fx.playQueue = []
      fx.runClear()
    }
  }

  Process {
    id: playProc
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line)
        if (s.indexOf("progress ") === 0) fx.playProgress = parseFloat(s.slice(9))
      }
    }
    onExited: {
      fx.playing = ""
      fx.playNext()
      fx.runClear()
    }
  }

  Process { id: clearProc }

  readonly property string primaryLabel: {
    if (step < 0) return running ? "Start" : "Turn on"
    if (phase) {
      if (recording) return "Recording…"
      if (results[phase.id] === undefined) return "Record"
      return step === Model.PHASES.length - 1 ? "Show suggestions" : "Next"
    }
    return "Apply"
  }

  readonly property bool primaryEnabled: busyAction === "" && !recording && !solveProc.running
    && (!atSuggestions || solution !== null)

  function primaryAction() {
    if (step < 0) {
      if (!running) {
        act(["on"], "Turning on…", "Mic FX is on")
        return
      }
      step = 0
      return
    }
    if (phase) {
      if (results[phase.id] === undefined) startPhase()
      else if (step < Model.PHASES.length - 1) step = step + 1
      else solve()
      return
    }
    act(["calibrate", "apply"], "Applying…", "Applied the suggested settings")
    closeWizard()
  }

  onOpenedChanged: if (opened) refresh()
  // Leaving the typing step hands the keyboard back to the panel, so Escape
  // and Tab work again.
  onStepChanged: if (!(phase && phase.typing === true) && typingField.activeFocus) keyCatcher.forceActiveFocus()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "io.github.codemonkey76.micfx"

    function open(): void { fx.open() }
    function close(): void { fx.close() }
    function toggle(): void { fx.toggle() }
    function enable(): void { if (!fx.running) fx.toggleOn() }
    function disable(): void { if (fx.running) fx.toggleOn() }
    function setup(): void { fx.open(); fx.openWizard() }
    function refresh(): void { fx.refresh() }
    function status(): string { return Model.tooltip(fx.status) }
  }

  // ---- Bar ----------------------------------------------------------------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: fx.bar
    text: fx.running ? Model.ICON_ON : Model.ICON_OFF
    dimmed: !fx.running
    active: fx.recording
    tooltipText: fx.opened ? "" : Model.tooltip(fx.status)
    onPressed: function(b) {
      if (b === Qt.RightButton) fx.toggleOn()
      else if (b === Qt.MiddleButton) fx.refresh()
      else fx.toggle()
    }
  }

  // ---- Panel --------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: fx
    bar: fx.bar
    open: fx.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    // Tall enough for every stage at once; only scrolls if the screen is shorter.
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (fx.wizard && !fx.recording) fx.closeWizard()
        else fx.close()
      }
      onTabRequested: function(direction) { fx.switchPanel(direction) }
      onTextKey: function(t) {
        if (fx.wizard) return
        if (t === "t" || t === "T") fx.toggleOn()
        else if (t === "w" || t === "W") fx.openWizard()
        else if (t === "r" || t === "R") fx.refresh()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Mic FX"
            meta: !fx.everLoaded ? "Loading…"
              : fx.busyAction !== "" ? fx.busyAction
              : fx.running ? (fx.isDefault ? "On  ·  default input" : "On  ·  not the default input")
              : "Off"
            detail: fx.recording ? "recording" : ""
            foreground: fx.fg
            fontFamily: fx.fontFamily
            iconOpacity: fx.running ? 1.0 : 0.5

            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: fx.running ? Model.ICON_ON : Model.ICON_OFF
                color: fx.running ? fx.fg : fx.dim
                font.family: fx.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                visible: fx.depsOk
                checked: fx.running
                busy: fx.busyAction !== ""
                interactive: fx.busyAction === "" && !fx.recording
                foreground: fx.fg
                onToggled: fx.toggleOn()

                PanelToolTip {
                  visible: powerSwitch.containsMouse
                  text: fx.running ? "Turn off  (t)" : "Turn on  (t)"
                  fontFamily: fx.fontFamily
                }
              }
            }
          }

          // The picker shows the device in the normal view; this line is for the wizard.
          Text {
            visible: fx.deviceName !== "" && (fx.wizard || fx.deviceOptions.length === 0)
            width: parent.width
            text: "Processing " + fx.deviceName
            textFormat: Text.PlainText
            color: fx.dim
            font.family: fx.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            visible: fx.message !== ""
            width: parent.width
            text: fx.message
            textFormat: Text.PlainText
            color: fx.messageIsError ? fx.urgent : fx.dim
            font.family: fx.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: fx.everLoaded && !fx.depsOk
            width: parent.width
            text: "Needs noise-suppression-for-voice and lsp-plugins-lv2: omarchy pkg add noise-suppression-for-voice lsp-plugins-lv2"
            textFormat: Text.PlainText
            color: fx.urgent
            font.family: fx.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Item {
            visible: fx.running && !fx.isDefault && !fx.wizard
            width: parent.width
            implicitHeight: Math.max(defaultNote.implicitHeight, defaultButton.implicitHeight)

            Text {
              id: defaultNote
              anchors.left: parent.left
              anchors.right: defaultButton.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: "Apps are still using the raw mic."
              textFormat: Text.PlainText
              color: fx.dim
              font.family: fx.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Button {
              id: defaultButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "Make default"
              bordered: true
              foreground: fx.fg
              fontFamily: fx.fontFamily
              onClicked: fx.makeDefault()
            }
          }

          // ---------- Normal view: microphone, wizard entry, then every stage ----------
          Column {
            visible: !fx.wizard
            width: parent.width
            spacing: Style.space(12)

            Item {
              visible: fx.deviceOptions.length > 0
              width: parent.width
              implicitHeight: micPicker.implicitHeight

              Text {
                id: micLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Microphone"
                textFormat: Text.PlainText
                color: fx.dim
                font.family: fx.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Dropdown {
                id: micPicker
                anchors.left: micLabel.right
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                showLabel: false
                label: "Microphone"
                fontFamily: fx.fontFamily
                options: fx.deviceOptions
                value: fx.status && fx.status.device ? fx.status.device.name : ""
                enabled: fx.busyAction === "" && !fx.recording
                onChanged: function(v) { fx.chooseDevice(v) }
              }
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(wizardNote.implicitHeight, wizardButton.implicitHeight)

              Text {
                id: wizardNote
                anchors.left: parent.left
                anchors.right: wizardButton.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: "Let the wizard listen to your room, your voice and your typing, and suggest settings."
                textFormat: Text.PlainText
                color: fx.dim
                font.family: fx.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Button {
                id: wizardButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: Model.ICON_WIZARD
                text: "Setup wizard"
                bordered: true
                enabled: fx.depsOk
                foreground: fx.fg
                fontFamily: fx.fontFamily
                onClicked: fx.openWizard()
              }
            }

            Repeater {
              model: Model.STAGES
              StageSection {
                required property var modelData
                width: column.width
                spec: modelData
              }
            }

            PanelSeparator { foreground: fx.fg }

            Item {
              width: parent.width
              implicitHeight: resetButton.implicitHeight

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "t on/off · w wizard · r refresh"
                textFormat: Text.PlainText
                color: fx.dim
                font.family: fx.fontFamily
                font.pixelSize: Style.font.caption
              }

              PanelActionButton {
                id: resetButton
                anchors.right: parent.right
                iconText: Model.ICON_RESTORE
                tooltipText: "Reset to defaults"
                foreground: fx.fg
                fontFamily: fx.fontFamily
                onClicked: fx.resetAll()
              }
            }
          }

          // ---------- Wizard view ----------
          Column {
            visible: fx.wizard
            width: parent.width
            spacing: Style.space(12)

            PanelSeparator { foreground: fx.fg }

            PanelSectionHeader {
              text: fx.step < 0 ? "SETUP WIZARD"
                : fx.phase ? ("STEP " + (fx.step + 1) + " OF " + Model.PHASES.length)
                : "SUGGESTED SETTINGS"
              foreground: fx.fg
              fontFamily: fx.fontFamily
            }

            Text {
              visible: fx.step < 0
              width: parent.width
              text: fx.running
                ? "Three short recordings, quiet, talking and typing, let the wizard measure your room, your voice and your keyboard, then suggest settings. At the end you can hear your typing over your talking, before and after. The clips stay in memory and are deleted when the wizard closes, and nothing changes until you apply the suggestions."
                : "Turn Mic FX on first: the wizard measures what comes out of the chain."
              textFormat: Text.PlainText
              color: fx.fg
              font.family: fx.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Row {
              visible: fx.phase !== null
              spacing: Style.space(10)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: fx.phase ? fx.phase.icon : ""
                textFormat: Text.PlainText
                color: fx.recording ? fx.accent : fx.fg
                font.family: fx.fontFamily
                font.pixelSize: Style.font.heading
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: fx.phase ? fx.phase.title : ""
                textFormat: Text.PlainText
                color: fx.fg
                font.family: fx.fontFamily
                font.pixelSize: Style.font.heading
              }
            }

            Text {
              visible: fx.phase !== null
              width: parent.width
              text: fx.phase ? fx.phase.text : ""
              textFormat: Text.PlainText
              color: fx.dim
              font.family: fx.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Rectangle {
              visible: fx.phase !== null && fx.phase.sample !== undefined
              width: parent.width
              implicitHeight: sampleText.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: "transparent"
              border.width: 1
              border.color: Util.alpha(fx.fg, 0.2)

              Text {
                id: sampleText
                anchors.fill: parent
                anchors.margins: Style.space(8)
                text: fx.phase && fx.phase.sample !== undefined ? fx.phase.sample : ""
                textFormat: Text.PlainText
                color: fx.fg
                font.family: fx.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }
            }

            // Somewhere real to type during the typing step, so the keys
            // don't land in another window or trigger shortcuts.
            TextField {
              id: typingField
              visible: fx.phase !== null && fx.phase.typing === true
              width: parent.width
              foreground: fx.fg
              font.family: fx.fontFamily
              placeholderText: "Type here…"
              Keys.onEscapePressed: keyCatcher.forceActiveFocus()
            }

            LevelBar {
              visible: fx.phase !== null
              width: parent.width
              label: "Microphone"
              db: fx.levelRaw
              tint: fx.dim
            }

            LevelBar {
              visible: fx.phase !== null
              width: parent.width
              label: "Suppressed"
              db: fx.levelFx
              tint: fx.accent
            }

            Rectangle {
              visible: fx.phase !== null
              width: parent.width
              height: Style.space(3)
              radius: height / 2
              color: Util.alpha(fx.fg, 0.12)

              Rectangle {
                width: parent.width * (fx.phase ? Math.min(1, fx.elapsed / fx.phase.seconds) : 0)
                height: parent.height
                radius: parent.radius
                color: fx.accent
              }
            }

            Text {
              visible: fx.phase !== null && fx.results[fx.phase.id] !== undefined
              width: parent.width
              text: fx.phase ? Model.phaseSummary(fx.phase.id, fx.results[fx.phase.id]) : ""
              textFormat: Text.PlainText
              color: fx.fg
              font.family: fx.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Column {
              visible: fx.atSuggestions && fx.solution !== null
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: fx.solution ? Model.MEASURED : []
                ValueRow {
                  required property var modelData
                  width: parent.width
                  label: modelData.label
                  value: fx.solution && fx.solution.measured ? Model.dbText(fx.solution.measured[modelData.key]) : ""
                }
              }

              PanelSectionHeader {
                text: "CHANGES"
                foreground: fx.fg
                fontFamily: fx.fontFamily
              }

              Repeater {
                model: fx.solution ? Model.changes(fx.solution.suggested, fx.fxSettings) : []
                ValueRow {
                  required property var modelData
                  width: parent.width
                  label: modelData.label
                  value: modelData.from + "  →  " + modelData.to
                }
              }

              Text {
                visible: fx.solution !== null && Model.changes(fx.solution.suggested, fx.fxSettings).length === 0
                width: parent.width
                text: "Your current settings already match the suggestions."
                textFormat: Text.PlainText
                color: fx.dim
                font.family: fx.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Repeater {
                model: fx.solution && fx.solution.notes ? fx.solution.notes : []
                Text {
                  required property var modelData
                  width: parent.width
                  text: "•  " + modelData
                  textFormat: Text.PlainText
                  color: fx.fg
                  font.family: fx.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
              }
            }

            Column {
              visible: fx.atSuggestions && fx.solution !== null
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                text: "HEAR THE DIFFERENCE"
                foreground: fx.fg
                fontFamily: fx.fontFamily
              }

              Text {
                width: parent.width
                text: "Your typing mixed over your talking: first as recorded, then through the suggested settings. It plays on your default output, so use headphones."
                textFormat: Text.PlainText
                color: fx.dim
                font.family: fx.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Row {
                id: previewButtons
                spacing: Style.space(6)
                readonly property bool idle: fx.playing === "" && fx.previewState !== "preparing"

                Button {
                  iconText: Model.ICON_PLAY
                  text: "Before → after"
                  bordered: true
                  enabled: previewButtons.idle
                  opacity: enabled ? 1.0 : 0.5
                  foreground: fx.fg
                  fontFamily: fx.fontFamily
                  onClicked: fx.hearDifference(["before", "after"])
                }

                Button {
                  text: "Before"
                  bordered: true
                  enabled: previewButtons.idle
                  opacity: enabled ? 1.0 : 0.5
                  foreground: fx.fg
                  fontFamily: fx.fontFamily
                  onClicked: fx.hearDifference(["before"])
                }

                Button {
                  text: "After"
                  bordered: true
                  enabled: previewButtons.idle
                  opacity: enabled ? 1.0 : 0.5
                  foreground: fx.fg
                  fontFamily: fx.fontFamily
                  onClicked: fx.hearDifference(["after"])
                }

                Button {
                  visible: !previewButtons.idle
                  iconText: Model.ICON_STOP
                  text: "Stop"
                  bordered: true
                  foreground: fx.fg
                  fontFamily: fx.fontFamily
                  onClicked: fx.stopPreview()
                }
              }

              Text {
                visible: fx.previewState === "preparing" || fx.playing !== ""
                width: parent.width
                text: fx.previewState === "preparing"
                  ? "Preparing the preview…  " + Math.round(fx.previewProgress * 100) + "%"
                  : (fx.playing === "before" ? Model.ICON_HEADPHONES + "  Playing: as recorded"
                                              : Model.ICON_HEADPHONES + "  Playing: with the suggested settings")
                textFormat: Text.PlainText
                color: fx.fg
                font.family: fx.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                visible: fx.previewState === "preparing" || fx.playing !== ""
                width: parent.width
                height: Style.space(3)
                radius: height / 2
                color: Util.alpha(fx.fg, 0.12)

                Rectangle {
                  width: parent.width * Math.min(1, fx.previewState === "preparing" ? fx.previewProgress : fx.playProgress)
                  height: parent.height
                  radius: parent.radius
                  color: fx.accent
                }
              }
            }

            Text {
              visible: fx.wizardError !== ""
              width: parent.width
              text: fx.wizardError
              textFormat: Text.PlainText
              color: fx.urgent
              font.family: fx.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Item {
              width: parent.width
              implicitHeight: primaryButton.implicitHeight

              Button {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: fx.recording ? "Stop" : "Cancel"
                bordered: true
                foreground: fx.fg
                fontFamily: fx.fontFamily
                onClicked: fx.cancelWizard()
              }

              Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Button {
                  visible: fx.phase !== null && !fx.recording && fx.results[fx.phase.id] !== undefined
                  text: "Redo"
                  bordered: true
                  foreground: fx.fg
                  fontFamily: fx.fontFamily
                  onClicked: fx.startPhase()
                }

                Button {
                  id: primaryButton
                  text: fx.primaryLabel
                  enabled: fx.primaryEnabled
                  opacity: enabled ? 1.0 : 0.5
                  bordered: true
                  selected: true
                  foreground: fx.fg
                  fontFamily: fx.fontFamily
                  onClicked: fx.primaryAction()
                }
              }
            }
          }
        }
      }
    }
  }

  // ---- Components ---------------------------------------------------------
  component StageSection: Column {
    id: stage
    property var spec: null
    readonly property string toggleKey: spec && spec.toggle ? spec.toggle : ""
    readonly property bool on: toggleKey === "" || fx.value(toggleKey, true) === true
    spacing: Style.space(8)

    PanelSeparator { foreground: fx.fg }

    Item {
      width: parent.width
      implicitHeight: Math.max(stageHeader.implicitHeight, stageSwitch.visible ? stageSwitch.implicitHeight : 0)

      PanelSectionHeader {
        id: stageHeader
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: stage.spec ? stage.spec.title : ""
        foreground: fx.fg
        fontFamily: fx.fontFamily
      }

      ToggleSwitch {
        id: stageSwitch
        visible: stage.toggleKey !== ""
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: stage.on
        foreground: fx.fg
        onToggled: fx.setValue(stage.toggleKey, !stage.on)
      }
    }

    Repeater {
      model: stage.spec ? stage.spec.controls : []
      SliderRow {
        required property var modelData
        width: stage.width
        spec: modelData
        opacity: stage.on ? 1.0 : 0.45
      }
    }
  }

  component SliderRow: Column {
    id: sliderRow
    property var spec: null
    readonly property real current: spec ? Number(fx.value(spec.key, spec.min)) : 0
    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: sliderLabel.implicitHeight

      Text {
        id: sliderLabel
        anchors.left: parent.left
        text: sliderRow.spec ? sliderRow.spec.label : ""
        textFormat: Text.PlainText
        color: fx.dim
        font.family: fx.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        anchors.right: parent.right
        text: sliderRow.spec ? Model.formatValue(sliderRow.current, sliderRow.spec.unit) : ""
        textFormat: Text.PlainText
        color: fx.fg
        font.family: fx.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    PanelSlider {
      width: parent.width
      bar: fx.bar
      minimum: sliderRow.spec ? sliderRow.spec.min : 0
      maximum: sliderRow.spec ? sliderRow.spec.max : 1
      step: sliderRow.spec ? sliderRow.spec.step : 1
      integer: sliderRow.spec ? sliderRow.spec.step >= 1 : false
      value: sliderRow.current
      onMoved: function(v) { if (sliderRow.spec) fx.setValue(sliderRow.spec.key, v) }
    }
  }

  component LevelBar: Item {
    id: levelBar
    property string label: ""
    property real db: -120
    property color tint: fx.fg
    implicitHeight: Style.space(18)

    Text {
      id: levelLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(80)
      text: levelBar.label
      textFormat: Text.PlainText
      color: fx.dim
      font.family: fx.fontFamily
      font.pixelSize: Style.font.caption
    }

    Rectangle {
      anchors.left: levelLabel.right
      anchors.right: levelValue.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      height: Style.space(6)
      radius: height / 2
      color: Util.alpha(fx.fg, 0.12)

      Rectangle {
        width: parent.width * Model.meter(levelBar.db)
        height: parent.height
        radius: parent.radius
        color: levelBar.tint
        Behavior on width { NumberAnimation { duration: 90 } }
      }
    }

    Text {
      id: levelValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(70)
      horizontalAlignment: Text.AlignRight
      text: Model.dbText(levelBar.db)
      textFormat: Text.PlainText
      color: fx.fg
      font.family: fx.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component ValueRow: Item {
    id: valueRow
    property string label: ""
    property string value: ""
    implicitHeight: Math.max(valueLabel.implicitHeight, valueText.implicitHeight)

    Text {
      id: valueLabel
      anchors.left: parent.left
      anchors.right: valueText.left
      anchors.rightMargin: Style.space(8)
      text: valueRow.label
      textFormat: Text.PlainText
      color: fx.dim
      font.family: fx.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Text {
      id: valueText
      anchors.right: parent.right
      text: valueRow.value
      textFormat: Text.PlainText
      color: fx.fg
      font.family: fx.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
