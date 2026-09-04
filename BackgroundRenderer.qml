import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtMultimedia
import qs.Commons
import qs.Ui

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"
  readonly property string bgSourceTypeFile: stateHome + "/omarchy/current/bg-source-type"
  readonly property string bgSourcePathFile: stateHome + "/omarchy/current/bg-source-path"
  property string bgSourcePath: ""

  // Plugin context: absolute path of the plugin dir (set by Service.qml) so
  // helper bins resolve without being on PATH.
  property string pluginDir: ""

  property string bgSourceType: "image"
  property string currentSource: ""
  property string displayedSource: ""
  property string incomingSource: ""
  property string oldSource: ""
  property bool finishingTransition: false
  property int backgroundVersion: 0
  property int revealStartedVersion: -1
  property real revealProgress: 1

  property bool ttfxRunning: false
  property bool rendererReady: true

  // Universal cover fade for video/animated transitions:
  // cover -> swap source under the cover -> reveal once ready.
  property bool coverOn: false
  property string swapTarget: ""

  // Mouse parallax (pixels of drift applied to the oversized renderer).
  // Optional, on by default; Space in the switcher toggles it and the
  // preference persists in ~/.local/state/omarchy/current/bg-parallax.
  property bool parallaxEnabled: true
  property real parallaxX: 0
  property real parallaxY: 0

  // Parallax strength: 1..8 (2 = the original feel). Amplitudes scale
  // linearly; the renderer headrooms scale with it so edges never show.
  readonly property string parallaxResolutionFile: stateHome + "/omarchy/current/bg-parallax-resolution"
  property int parallaxResolution: 2
  readonly property real pxAmpX: 21 * parallaxResolution
  readonly property real pxAmpY: 15 * parallaxResolution
  readonly property real prxHeadroomScale: Math.max(1, parallaxResolution / 2)

  function setParallaxResolution(n) {
    var v = parseInt(n)
    if (isNaN(v)) v = 2
    n = Math.max(1, Math.min(8, v))
    root.parallaxResolution = n
    Quickshell.execDetached(["sh", "-c", "mkdir -p " + stateHome + "/omarchy/current && echo '" + n + "' > " + root.parallaxResolutionFile])
  }

  function cycleParallaxResolution(delta) { root.setParallaxResolution(root.parallaxResolution + delta) }

  function isImagePath(path) {
    if (!path) return false
    var ext = String(path).split(".").pop().toLowerCase()
    return ["jpg", "jpeg", "png", "webp", "bmp", "svg"].indexOf(ext) !== -1
  }

  function isAnimatedPath(path) {
    if (!path) return false
    var ext = String(path).split(".").pop().toLowerCase()
    return ["gif", "webp", "apng"].indexOf(ext) !== -1
  }

  function isVideoPath(path) {
    if (!path) return false
    var ext = String(path).split(".").pop().toLowerCase()
    return ["mp4", "mkv", "mov", "webm", "avi"].indexOf(ext) !== -1
  }

  // Parallax backgrounds are directories: <dir>/layers/0-*.svg ... Any path
  // without a known file extension is treated as one (the layer helper
  // returns empty when the directory is not a parallax background).
  function isParallaxPath(path) {
    if (!path) return false
    var ext = String(path).split(".").pop().toLowerCase()
    return ["jpg", "jpeg", "png", "webp", "bmp", "svg", "gif", "apng",
            "mp4", "mkv", "mov", "webm", "avi"].indexOf(ext) === -1
  }

  function imageUrl(path) { return Util.fileUrl(path) }

  function fileUrl(path) {
    if (!path) return ""
    if (path.startsWith("file://") || path.startsWith("http://") || path.startsWith("https://")) return path
    return "file://" + path
  }

  // Re-apply the persisted source once we know both the type and the path.
  // Startup is racy: bgSourceType defaults to "image" until the state file is
  // read, and refreshBackground() then restores the theme wallpaper symlink
  // into displayedSource — leaving a stale image under an "animated"/"video"
  // type forever. When the type says non-image, the path file wins.
  function syncSourceFromState() {
    if (root.bgSourceType === "image" || !root.bgSourcePath) return
    if (root.bgSourcePath === root.displayedSource) return
    root.setSource(root.bgSourcePath, false)
  }

  function refreshBackground() {
    if (root.bgSourceType !== "image") {
      if (root.bgSourcePath) root.setSource(root.bgSourcePath, false)
      return
    }
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function refreshSourceType() { if (!readSourceTypeProc.running) readSourceTypeProc.running = true }
  function refreshSourcePath() { if (!readSourcePathProc.running) readSourcePathProc.running = true }

  function setSourceType(type) { bgSourceType = type; writeSourceType(type) }

  function setSource(path, instant) { transitionSource("", path, path, instant, false) }

  function setBackground(path, instant) {
    bgSourceType = "image"; writeSourceType("image")
    transitionSource("", path, path, instant, false)
  }

  function transitionSource(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    fromPath = String(fromPath || "").trim()
    if (!path || (!force && finalPath === currentSource && bgSourceType === "image")) return
    currentSource = finalPath
    backgroundVersion += 1
    revealStartedVersion = -1
    rendererReady = false
    revealAnimation.stop()
    finishingTransition = false

    // Only the audio type keeps ttfx alive; every other type must kill it
    // so its layer never overlaps our own renderer.
    if (bgSourceType !== "audio") stopTtfx()

    if (bgSourceType === "audio") {
      oldSource = ""; incomingSource = ""; displayedSource = path || "matrix"
      revealProgress = 1; rendererReady = true
      root.coverOn = false
      startTtfx(); return
    }

    if (instant || !displayedSource) {
      oldSource = ""; incomingSource = ""; displayedSource = path; revealProgress = 1
      root.coverOn = false
      return
    }

    // Video/animated swap under a black cover, revealed when the new
    // renderer is actually producing frames.
    if (bgSourceType === "video" || bgSourceType === "animated") {
      oldSource = ""; incomingSource = ""; revealProgress = 1
      root.swapTarget = path
      coverSafetyTimer.restart()
      if (root.coverOn) { root.displayedSource = path; return }
      root.coverOn = true
      coverTimer.restart()
      return
    }

    // Order matters: revealProgress must be 0 BEFORE incomingSource changes.
    // A cache-hot image emits Ready synchronously during the incomingSource
    // assignment, and the panel gate requires revealProgress === 0 already.
    oldSource = fromPath || displayedSource
    revealProgress = 0
    incomingSource = path
    root.coverOn = false
  }

  function tryReveal() {
    if (!root.coverOn || root.displayedSource !== root.swapTarget) return
    if ((bgSourceType === "video" || bgSourceType === "animated") && !rendererReady) return
    root.coverOn = false
  }

  function startReveal(panel) {
    if (!incomingSource && bgSourceType !== "audio") return
    panel.maskReady = true
    if (revealStartedVersion === backgroundVersion) return
    revealStartedVersion = backgroundVersion
    revealAnimation.restart()
  }

  function onRendererReady() {
    rendererReady = true
    root.rendererReadyTriggered()
    root.tryReveal()
    // Safety net: revealAnimation.onFinished normally clears these. If a stale
    // transition was interrupted after completing, clear it once a frame is ready.
    if (bgSourceType === "image" && root.incomingSource && root.revealProgress === 1) {
      incomingSource = ""; oldSource = ""
    }
  }


  signal rendererReadyTriggered()

  function openSelector() { if (!bgSwitchProc.running) bgSwitchProc.running = true }
  function openThemeSwitcher() { if (!themeSwitchProc.running) themeSwitchProc.running = true }

  function startTtfx() {
    if (ttfxRunning) return
    ttfxRunning = true
    // The live ASCII background is rendered by the companion
    // omarchy-audio-background plugin. It is OPTIONAL: when not installed we
    // simply render nothing (transparent) for the audio type.
    var launcher = home + "/.config/omarchy/plugins/io.github.avillagran.omarchy-audio-background/bin/ttfx-bg-launch.sh"
    Quickshell.execDetached(["sh", "-c", "[ -x " + Util.shellQuote(launcher) + " ] && exec " + Util.shellQuote(launcher)])
  }

  function stopTtfx() {
    if (!ttfxRunning) return
    ttfxRunning = false
    Quickshell.execDetached(["pkill", "-f", "[t]tfx-bg-rs-.* --render"])
    Quickshell.execDetached(["pkill", "-f", "[t]tfx-bg-rs-aarch64$"])
  }

  function writeSourceType(type) {
    Quickshell.execDetached(["sh", "-c", "mkdir -p " + stateHome + "/omarchy/current && echo '" + type + "' > " + bgSourceTypeFile])
  }

  readonly property string parallaxFile: stateHome + "/omarchy/current/bg-parallax"

  function toggleParallax() {
    root.parallaxEnabled = !root.parallaxEnabled
    if (!root.parallaxEnabled) { root.parallaxX = 0; root.parallaxY = 0 }
    Quickshell.execDetached(["sh", "-c", "mkdir -p " + stateHome + "/omarchy/current && echo '" + (root.parallaxEnabled ? "on" : "off") + "' > " + root.parallaxFile])
  }

  Process {
    id: bgSwitchProc
    command: ["bash", "-c", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
    onExited: root.refreshBackground()
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
    onExited: root.refreshBackground()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: {
        var p = String(text || "").trim()
        // Only the image type follows the theme wallpaper symlink; a non-image
        // type must not be clobbered by the async readlink result.
        if (p && root.bgSourceType === "image") { root.setBackground(p, false) }
      }
    }
  }

  Process {
    id: readSourceTypeProc
    command: ["cat", root.bgSourceTypeFile]
    stdout: StdioCollector {
      onStreamFinished: {
        var t = String(text || "image").trim()
        if (t !== root.bgSourceType) root.bgSourceType = t
        root.syncSourceFromState()
      }
    }
  }

  Process {
    id: readSourcePathProc
    command: ["cat", root.bgSourcePathFile]
    stdout: StdioCollector {
      onStreamFinished: {
        root.bgSourcePath = String(text || "").trim()
        root.syncSourceFromState()
      }
    }
  }

  Process {
    id: readParallaxProc
    command: ["cat", root.parallaxFile]
    stdout: StdioCollector {
      onStreamFinished: function() {
        root.parallaxEnabled = String(text || "on").trim() !== "off"
      }
    }
  }

  Process {
    id: readParallaxResolutionProc
    command: ["cat", root.parallaxResolutionFile]
    stdout: StdioCollector {
      onStreamFinished: function() {
        root.parallaxResolution = Math.max(1, Math.min(8, parseInt(String(text || "2").trim()) || 2))
      }
    }
  }

  // Cover-fade sequence: cover up -> swap source -> hold -> reveal.
  Timer {
    id: coverTimer
    interval: 200
    repeat: false
    onTriggered: {
      root.displayedSource = root.swapTarget
      revealHold.restart()
    }
  }

  Timer {
    id: revealHold
    interval: 380
    repeat: false
    onTriggered: root.tryReveal()
  }

  // Never leave the black cover up: if the renderer never reports ready
  // (cache hiccup, codec stall), reveal anyway after a bounded wait.
  Timer {
    id: coverSafetyTimer
    interval: 2500
    repeat: false
    onTriggered: { if (root.coverOn) root.coverOn = false }
  }

  NumberAnimation {
    id: revealAnimation
    target: root; property: "revealProgress"; from: 0; to: 1; duration: 420
    easing.type: Easing.InOutCubic
    onFinished: {
      if (root.incomingSource) root.displayedSource = root.currentSource || root.incomingSource
      root.revealProgress = 1
      // Clear immediately instead of waiting for the base Image's Ready: with a
      // cache-hot frame that signal can fire synchronously mid-assignment above,
      // while finishingTransition is still false, and the cleanup would be skipped.
      root.oldSource = ""; root.incomingSource = ""; root.finishingTransition = false
    }
  }

  Component.onCompleted: { refreshSourceType(); refreshSourcePath(); readParallaxProc.running = true; readParallaxResolutionProc.running = true; refreshBackground() }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: !remapGuard.remapping
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap { id: remapGuard; window: panel }
      color: "transparent"
      updatesEnabled: true
      property bool maskReady: false

      Connections {
        target: root
        function onRendererReadyTriggered() {
          if (root.incomingSource && root.revealProgress === 0 && root.rendererReady) {
            panel.maskReady = true; root.startReveal(panel)
          }
        }
      }

      WlrLayershell.namespace: "omarchy-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // --- Image renderer ---
      Component {
        id: imageRendererComponent
        Item {
          anchors.fill: parent

          Image {
            id: base
            anchors.fill: parent
            source: root.isImagePath(root.displayedSource) ? root.imageUrl(root.displayedSource) : ""
            fillMode: Image.PreserveAspectCrop; asynchronous: false; cache: true
            // Always notify: the cover-fade path (animated svg/png via the
            // image renderer) needs this to reveal once the frame is ready.
            onStatusChanged: { if (status === Image.Ready) root.onRendererReady() }
          }

          Image {
            id: oldFrame
            anchors.fill: parent
            source: root.isImagePath(root.oldSource) ? root.imageUrl(root.oldSource) : ""
            fillMode: Image.PreserveAspectCrop; asynchronous: false; cache: false; smooth: true; mipmap: true
            visible: root.oldSource !== "" && root.revealProgress < 1
          }

          Item {
            id: incomingLayer
            anchors.fill: parent
            visible: root.incomingSource !== "" && incomingFrame.status === Image.Ready && (root.revealProgress >= 1 || panel.maskReady)
            layer.enabled: root.incomingSource !== "" && root.revealProgress < 1
            layer.smooth: true
            layer.effect: MultiEffect {
              maskEnabled: true; maskSource: revealMask; maskThresholdMin: 0.5; maskSpreadAtMin: 0.02
            }
            Image {
              id: incomingFrame
              anchors.fill: parent
              source: root.isImagePath(root.incomingSource) ? root.imageUrl(root.incomingSource) : ""
              fillMode: Image.PreserveAspectCrop; asynchronous: false; cache: false; smooth: true; mipmap: true
              onStatusChanged: { if (status === Image.Ready) root.onRendererReady() }
            }
          }
        }
      }

      // --- Video renderer ---
      Component {
        id: videoRendererComponent
        Item {
          anchors.fill: parent
          MediaPlayer {
            id: videoPlayer
            source: root.isVideoPath(root.displayedSource) ? root.fileUrl(root.displayedSource) : ""
            loops: MediaPlayer.Infinite; autoPlay: true; videoOutput: videoOutput
            onPlaybackStateChanged: { if (playbackState === MediaPlayer.PlayingState) root.onRendererReady() }
          }
          VideoOutput { id: videoOutput; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectCrop }
        }
      }

      // --- Audio renderer (transparent) ---
      Component {
        id: audioRendererComponent
        Item {
          anchors.fill: parent
          Rectangle { anchors.fill: parent; color: "transparent" }
        }
      }

      // --- Animated renderer (static first frame) ---
      Component {
        id: animatedRendererComponent
        Item {
          anchors.fill: parent
          Image {
            id: animatedImg
            anchors.fill: parent
            source: root.isAnimatedPath(root.displayedSource) ? root.fileUrl(root.displayedSource) : ""
            fillMode: Image.PreserveAspectCrop; cache: true
            onStatusChanged: { if (status === Image.Ready) root.onRendererReady() }
          }
        }
      }

      // --- Parallax renderer (layered SVG artwork, depth drift) ---
      // The applied path is a directory: layers/0-*.svg ... N-*.svg stacked
      // back -> front. Each layer drifts by factor * (mouse parallax + slow
      // auto sway); factors default to linear depth (i/(N-1)) and can be
      // overridden per layer in <dir>/parallax.json.
      Component {
        id: parallaxRendererComponent
        Item {
          id: prx
          anchors.fill: parent

          property var layers: []
          property string poster: ""
          property int readyCount: 0
          property real driftT: 0

          // Oversize so the deepest drift never exposes an edge (scales
          // with the parallax strength set via the resolution option).
          readonly property real headroom: 0.06 * root.prxHeadroomScale
          readonly property real autoAmpX: 22
          readonly property real autoAmpY: 10
          readonly property real shiftX: root.parallaxX + (Math.sin(driftT * Math.PI * 2) * autoAmpX)
          readonly property real shiftY: root.parallaxY + (Math.cos(driftT * Math.PI * 2) * autoAmpY)

          Component.onCompleted: { prx.readyCount = 0; layersProc.running = true }

          // Switching from one parallax scene to another keeps the same
          // component alive, so the layer list must be re-queried whenever
          // the displayed source changes (the Process command binding
          // re-evaluates, but `running` does not re-fire by itself).
          Connections {
            target: root
            function onDisplayedSourceChanged() {
              prx.readyCount = 0
              layersProc.running = true
            }
          }

          // Slow endless sway so the scene feels alive without the mouse.
          SequentialAnimation on driftT {
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 26000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0; duration: 26000; easing.type: Easing.InOutSine }
          }

          Process {
            id: layersProc
            command: [root.pluginDir + "/bin/omarchy-bg-parallax-layers", String(root.displayedSource)]
            stdout: StdioCollector {
              onStreamFinished: {
                var j = null
                try { j = JSON.parse(String(text || "")) } catch (e) { j = null }
                var ls = (j && j.layers) ? j.layers : []
                prx.poster = (j && j.poster) ? j.poster : ""
                if (ls.length === 0 && prx.poster) {
                  // Not a parallax dir (or no layers yet): fall back to the
                  // static preview so the screen is never left black.
                  prx.layers = []
                  posterImg.visible = true
                  root.onRendererReady()
                } else {
                  prx.readyCount = 0
                  prx.layers = ls
                  if (ls.length === 0) root.onRendererReady()
                }
              }
            }
          }

          // Fallback poster when the directory has no extracted layers.
          Image {
            id: posterImg
            visible: false
            anchors.fill: parent
            source: visible && prx.poster ? root.fileUrl(prx.poster) : ""
            fillMode: Image.PreserveAspectCrop
          }

          Repeater {
            model: prx.layers
            Image {
              required property var modelData
              readonly property real depth: modelData.factor
              width: parent.width * (1 + prx.headroom * 2)
              height: parent.height * (1 + prx.headroom * 2)
              x: (parent.width - width) / 2 + prx.shiftX * depth
              y: (parent.height - height) / 2 + prx.shiftY * depth
              source: root.fileUrl(modelData.file)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              smooth: true
              onStatusChanged: {
                if (status === Image.Ready || status === Image.Error) {
                  prx.readyCount += 1
                  if (prx.readyCount >= prx.layers.length) root.onRendererReady()
                }
              }
            }
          }
        }
      }

      // --- Parallax layer (mouse-driven depth) ---
      Item {
        id: parallaxLayer
        anchors.fill: parent
        visible: false
      }

      Loader {
        id: rendererLoader
        // Slightly oversized and mouse-driven: every background type gets a
        // subtle parallax drift so static/responsive SVG artwork stays alive.
        // Headroom scales with the parallax strength (resolution) so the
        // drift never exposes an edge at high strengths.
        width: parent.width * (1 + 0.06 * root.prxHeadroomScale)
        height: parent.height * (1 + 0.06 * root.prxHeadroomScale)
        x: (parent.width - width) / 2 + root.parallaxX
        y: (parent.height - height) / 2 + root.parallaxY
        Behavior on x { NumberAnimation { duration: 1400; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 1400; easing.type: Easing.OutCubic } }
        sourceComponent: {
          switch (root.bgSourceType) {
            case "video": return videoRendererComponent
            case "audio": return audioRendererComponent
            // Animated sources are converted to a cached looping mp4 by
            // omarchy-bg-set-type; static SVGs (responsive artwork) stay
            // as images and get their motion from the parallax drift;
            // directories with layers/*.svg get the layered parallax renderer.
            case "animated":
              if (root.isParallaxPath(root.displayedSource)) return parallaxRendererComponent
              return root.isVideoPath(root.displayedSource) ? videoRendererComponent : imageRendererComponent
            default: return imageRendererComponent
          }
        }
      }

      // Black cover used by the video/animated fade transition.
      Rectangle {
        id: fadeCover
        anchors.fill: parent
        color: "black"
        z: 5
        opacity: root.coverOn ? 1 : 0
        visible: opacity > 0.001
        Behavior on opacity {
          NumberAnimation {
            duration: root.coverOn ? 170 : 360
            easing.type: Easing.InOutCubic
          }
        }
      }

      Item {
        id: revealMask
        anchors.fill: parent; visible: false; layer.enabled: true
        readonly property real slant: -0.18
        readonly property real centerTop: width / 2 - slant * height / 2
        readonly property real centerBottom: width / 2 + slant * height / 2
        readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
        readonly property real spread: reach * root.revealProgress
        Shape {
          anchors.fill: parent; antialiasing: true; preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: "white"; strokeColor: "transparent"
            startX: revealMask.centerTop - revealMask.spread; startY: 0
            PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
            PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
          }
        }
      }

      Connections {
        target: root
        function onIncomingSourceChanged() { panel.maskReady = false }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        onPositionChanged: function(mouse) {
          if (!root.parallaxEnabled) return
          root.parallaxX = ((mouse.x / width) * 2 - 1) * -root.pxAmpX
          root.parallaxY = ((mouse.y / height) * 2 - 1) * -root.pxAmpY
        }
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openThemeSwitcher()
          else root.openSelector()
          mouse.accepted = true
        }
      }
    }
  }
}
