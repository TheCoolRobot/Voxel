const { app, BrowserWindow, Menu, shell, dialog } = require('electron')
const path = require('path')

// ── Single-instance lock ────────────────────────────────────────────────────
const gotLock = app.requestSingleInstanceLock()
if (!gotLock) { app.quit(); process.exit(0) }

let win = null

function createWindow() {
  win = new BrowserWindow({
    width:     1600,
    height:    960,
    minWidth:  900,
    minHeight: 540,
    title:     'FRC Dashboard',

    // Match the dashboard's void background so there's no white flash on load
    backgroundColor: '#04040d',

    // Hide the window until the page is ready to avoid a blank frame
    show: false,

    // macOS: merge title bar into the content area
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
    trafficLightPosition: { x: 14, y: 14 },

    webPreferences: {
      nodeIntegration:    false,
      contextIsolation:   true,
      // Allow XHR to local files (layouts/default.json, field image, etc.)
      webSecurity:        false,
    },
  })

  // Load the dashboard — file:// so no local server is needed
  win.loadFile(path.join(__dirname, '..', 'index.html'))

  // Show once the page has painted its first frame
  win.once('ready-to-show', () => {
    win.show()
    if (process.platform === 'darwin') app.dock.show()
  })

  // ── Keyboard shortcuts ─────────────────────────────────────────────────
  win.webContents.on('before-input-event', (_event, input) => {
    // F11 / Ctrl+Shift+F — fullscreen toggle
    if (input.key === 'F11' || (input.control && input.shift && input.key === 'F')) {
      win.setFullScreen(!win.isFullScreen())
    }
    // F5 / Ctrl+R — rebuild + reload (dev convenience)
    if (input.key === 'F5' || (input.control && input.key === 'r')) {
      win.webContents.reload()
    }
    // F12 / Ctrl+Shift+I — DevTools
    if (input.key === 'F12' || (input.control && input.shift && input.key === 'I')) {
      win.webContents.toggleDevTools()
    }
  })

  win.on('closed', () => { win = null })
}

// ── App menu ────────────────────────────────────────────────────────────────
function buildMenu() {
  const isMac = process.platform === 'darwin'

  const template = [
    // macOS app menu
    ...(isMac ? [{
      label: app.name,
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        { role: 'hide' }, { role: 'hideOthers' }, { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' }
      ]
    }] : []),

    {
      label: 'Dashboard',
      submenu: [
        {
          label: 'Reload',
          accelerator: 'CmdOrCtrl+R',
          click: () => win?.webContents.reload()
        },
        {
          label: 'Toggle Fullscreen',
          accelerator: isMac ? 'Ctrl+Cmd+F' : 'F11',
          click: () => win && win.setFullScreen(!win.isFullScreen())
        },
        { type: 'separator' },
        {
          label: 'Toggle DevTools',
          accelerator: isMac ? 'Alt+Cmd+I' : 'F12',
          click: () => win?.webContents.toggleDevTools()
        }
      ]
    },

    {
      label: 'Edit',
      submenu: [
        { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }
      ]
    },

    {
      label: 'Window',
      submenu: [
        { role: 'minimize' },
        { role: 'zoom' },
        ...(isMac ? [{ type: 'separator' }, { role: 'front' }] : [])
      ]
    }
  ]

  Menu.setApplicationMenu(Menu.buildFromTemplate(template))
}

// ── Lifecycle ───────────────────────────────────────────────────────────────
app.whenReady().then(() => {
  buildMenu()
  createWindow()

  // macOS: re-open window when dock icon is clicked after all windows are closed
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

// Quit when all windows are closed (except on macOS)
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})

// Focus existing window if a second instance is launched
app.on('second-instance', () => {
  if (win) {
    if (win.isMinimized()) win.restore()
    win.focus()
  }
})
