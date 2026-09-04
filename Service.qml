import Quickshell
import Quickshell.Io
import QtQuick

// Self-contained animated/parallax background system for stock Omarchy:
// a private bottom-layer renderer (image / video / animated / parallax
// scenes / audio passthrough) plus the background switcher panel, wired
// through ONE IpcHandler under this plugin's own target (no collision with
// Omarchy's first-party `background` IPC).
Item {
  id: root

  readonly property string ipcTarget: "io.github.avillagran.omarchy-animated-backgrounds"

  // Plugin dir resolution: in a `service` context neither manifest.__sourceDir
  // nor Quickshell.pluginDir exist for git-installed plugins; Qt.resolvedUrl
  // relative to this file is the reliable source. __sourceDir is kept as a
  // first choice because it is what symlinked local installs provide.
  readonly property string pluginDir: {
    if (typeof manifest !== 'undefined' && manifest.__sourceDir)
      return String(manifest.__sourceDir).replace(/\/$/, "")
    return Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  }

  BackgroundRenderer {
    id: renderer
    pluginDir: root.pluginDir
  }

  BackgroundSwitcher {
    id: switcher
    pluginDir: root.pluginDir
    ipcTarget: root.ipcTarget
  }

  IpcHandler {
    target: root.ipcTarget

    // switcher
    function toggle(): void { switcher.toggle() }

    // background renderer
    function refresh(): void { renderer.refreshBackground(); renderer.refreshSourceType() }
    function set(path: string): void { renderer.setSource(path, false) }
    function setInstant(path: string): void { renderer.setSource(path, true) }
    function setSourceType(type: string): void { renderer.setSourceType(type) }
    function toggleParallax(): void { renderer.toggleParallax() }
    function setParallaxResolution(n: int): void { renderer.setParallaxResolution(n) }
    function cycleParallaxResolution(delta: int): void { renderer.cycleParallaxResolution(delta) }
    function setSource(type: string, path: string): void {
      renderer.bgSourceType = type
      renderer.writeSourceType(type)
      renderer.transitionSource("", path, path, false, true)
    }
    function transition(fromPath: string, path: string): void {
      renderer.transitionSource(fromPath, path, path, false, false)
    }
  }
}
