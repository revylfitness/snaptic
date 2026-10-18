import Foundation

// The frozen 0.2 control list (lead; PLAN 0.3 §4.8.1, literal, frozen at 871c10b). Copied verbatim from the plan in
// step 0; it never changes afterwards. A name ending in `*` is one id for a parameterized family. The 0.3 homes are
// the owners' control tables (`replaces:`); ControlRemovals lists the ids removed with a reason.

package enum ControlLegacy {
    /// §4.8.1 expanded (588 ids), in table order.
    package static var ids: [LegacyControlID] { rawIDs.map { LegacyControlID(rawValue: $0) } }

    /// The 0.2 switcher `Config` key paths (Mirror walker form, R5-13: arrays are `*`) → their legacy ids, for
    /// `--selftest-controls` (A). `disabledFeatures` is one key for all 14 feature ids.
    package static var switcherKeyPaths: [String: [LegacyControlID]] {
        var map: [String: [LegacyControlID]] = [:]
        for name in ["modifier", "keyCode", "scope", "style", "includeMinimized", "includeWindowlessApps", "spaces",
                     "oneWindowPerApp"] {
            map["shortcuts.*." + name] = [LegacyControlID(rawValue: "l.sw.shortcut." + name)]
        }
        for name in ["releaseToSwitch", "previewSelected", "showOtherSpaces", "autoSize", "thumbnailSize", "showOnScreen",
                     "selectOnHover", "passthroughOnlyWhenFullscreen", "excludedBundleIDs", "passthroughBundleIDs",
                     "privateBundleIDs", "protectPrivateWindows", "gatherShortcut"] {
            map[name] = [LegacyControlID(rawValue: "l.sw." + name)]
        }
        map["disabledFeatures"] = rawIDs.filter { $0.hasPrefix("l.sw.feature.") }.map { LegacyControlID(rawValue: $0) }
        return map
    }

    /// Config key paths that are state, not controls (the key cross-check skips them and their children).
    package static var internalKeys: Set<String> {
        [
            // Switcher
            "shortcuts.*.id",
            // ModulesConfig: onboarding progress and one-time cards
            "onboarding", "onboardingPermissions", "showNewDisplaysCard", "newModuleCards",
            // DisplaysConfig: 0.2's per-display sleep prevention, ignored since 0.3 and kept only for 0.2 downgrades
            // until 0.4 (§2.13; its control moved to Awake through migration M1)
            "perDisplay.*.management.preventSleep",
        ]
    }

    private static let rawIDs: [String] = [
        // l.gen.modules.
        "l.gen.modules.switcher", "l.gen.modules.displays", "l.gen.modules.newDisplaysCard.turnOn",
        "l.gen.modules.newDisplaysCard.notNow",
        // l.gen.menu.
        "l.gen.menu.switcher.show", "l.gen.menu.switcher.icon", "l.gen.menu.displays.show",
        "l.gen.menu.displays.icon", "l.gen.menu.displays.hideWithoutExternal", "l.gen.menu.snaptic.icon",
        "l.gen.menu.scrollAdjustsSliders", "l.gen.menu.compact", "l.gen.menu.mainFirst", "l.gen.menu.showBadges",
        "l.gen.menu.headerForSingleDisplay", "l.gen.menu.sectionOrder", "l.gen.menu.displayOrder",
        "l.gen.menu.useDefaultOrder", "l.gen.menu.reset", "l.gen.menu.hiddenIconWarnings",
        // l.gen.cli.
        "l.gen.cli.enabled", "l.gen.cli.maySkipConfirmation", "l.gen.cli.copyInstall", "l.gen.cli.exitCodes",
        // l.gen.startup.
        "l.gen.startup.launchAtLogin",
        // l.gen.permissions.
        "l.gen.permissions.rows", "l.gen.permissions.openSettings", "l.gen.permissions.relaunch",
        // l.gen.backup.
        "l.gen.backup.export", "l.gen.backup.import", "l.gen.backup.resetAll",
        // l.gen.safeMode.
        "l.gen.safeMode.restart", "l.gen.safeMode.leave",
        // l.gen.otherApps.
        "l.gen.otherApps.policy",
        // l.gen.about.
        "l.gen.about.checkUpdates", "l.gen.about.licenses",
        // l.sw.shortcut.
        "l.sw.shortcut.modifier", "l.sw.shortcut.keyCode", "l.sw.shortcut.scope", "l.sw.shortcut.style",
        "l.sw.shortcut.includeMinimized", "l.sw.shortcut.includeWindowlessApps", "l.sw.shortcut.spaces",
        "l.sw.shortcut.oneWindowPerApp", "l.sw.shortcut.add", "l.sw.shortcut.delete",
        // l.sw.
        "l.sw.releaseToSwitch", "l.sw.previewSelected", "l.sw.showOtherSpaces", "l.sw.autoSize", "l.sw.thumbnailSize",
        "l.sw.showOnScreen", "l.sw.selectOnHover", "l.sw.passthroughOnlyWhenFullscreen", "l.sw.excludedBundleIDs",
        "l.sw.passthroughBundleIDs", "l.sw.privateBundleIDs", "l.sw.protectPrivateWindows", "l.sw.gatherShortcut",
        "l.sw.permissionRows",
        // l.sw.feature.
        "l.sw.feature.thumbnails", "l.sw.feature.preview", "l.sw.feature.otherSpaces", "l.sw.feature.windowlessApps",
        "l.sw.feature.search", "l.sw.feature.actionClose", "l.sw.feature.actionMinimize",
        "l.sw.feature.actionFullscreen", "l.sw.feature.actionHide", "l.sw.feature.actionQuit",
        "l.sw.feature.hoverButtons", "l.sw.feature.hoverSelect", "l.sw.feature.commandTabTakeover",
        "l.sw.feature.passthrough",
        // l.dfeat.
        "l.dfeat.overview", "l.dfeat.diagnostics", "l.dfeat.resolution", "l.dfeat.hiddenModes", "l.dfeat.scaleMatch",
        "l.dfeat.brightness", "l.dfeat.brightnessApple", "l.dfeat.brightnessDDC", "l.dfeat.brightnessGamma",
        "l.dfeat.brightnessOverlay", "l.dfeat.brightnessRestore", "l.dfeat.dimToBlack", "l.dfeat.dimOnLock",
        "l.dfeat.nits", "l.dfeat.xdr", "l.dfeat.sync", "l.dfeat.autoBrightness", "l.dfeat.color",
        "l.dfeat.colorProfiles", "l.dfeat.nightShift", "l.dfeat.applePresets", "l.dfeat.ddcControls",
        "l.dfeat.ddcInput", "l.dfeat.ddcPower", "l.dfeat.ddcCustom", "l.dfeat.brightnessKeys", "l.dfeat.volumeKeys",
        "l.dfeat.shortcuts", "l.dfeat.osd", "l.dfeat.osdBroadcast", "l.dfeat.mainDisplay", "l.dfeat.arrangement",
        "l.dfeat.mirroring", "l.dfeat.rotation", "l.dfeat.underscan", "l.dfeat.hdrToggle", "l.dfeat.disconnect",
        "l.dfeat.autoDisconnectBuiltin", "l.dfeat.protection", "l.dfeat.layouts", "l.dfeat.virtualScreens",
        "l.dfeat.smartHiDPI", "l.dfeat.hdrVirtual", "l.dfeat.pip", "l.dfeat.pipFilters", "l.dfeat.menuBarOverlays",
        "l.dfeat.sleepPrevention", "l.dfeat.hooks", "l.dfeat.customActions",
        // l.d.overview.
        "l.d.overview.ddcPower", "l.d.overview.brightness", "l.d.overview.volume", "l.d.overview.mute",
        "l.d.overview.resolutionSlider", "l.d.overview.resolutionPicker", "l.d.overview.input",
        "l.d.overview.identify", "l.d.overview.redetect", "l.d.overview.showPanel", "l.d.overview.showPanelShortcut",
        "l.d.overview.identifyShortcut", "l.d.overview.activeFeatures", "l.d.overview.banner.resume",
        "l.d.overview.banner.leaveSafeMode", "l.d.overview.banner.restartHelper",
        // l.d.features.
        "l.d.features.permissionRows", "l.d.features.featureOffRows",
        // l.d.resolution.
        "l.d.resolution.confirm", "l.d.resolution.allowBelow720p", "l.d.resolution.persistedChoice",
        "l.d.resolution.sliderLabel", "l.d.resolution.sliderSnapping", "l.d.resolution.sliderNativeAspectOnly",
        "l.d.resolution.mode", "l.d.resolution.refresh", "l.d.resolution.quick.hiDPI", "l.d.resolution.quick.native",
        "l.d.resolution.quick.default", "l.d.resolution.quick.nativeHalved", "l.d.resolution.quick.notch",
        "l.d.resolution.undo", "l.d.resolution.redo", "l.d.resolution.addFavorite", "l.d.resolution.favorite.apply",
        "l.d.resolution.favorite.remove", "l.d.resolution.dpiFilter", "l.d.resolution.widthMin",
        "l.d.resolution.widthMax", "l.d.resolution.widthClear", "l.d.resolution.refreshFilter",
        "l.d.resolution.matchUIScale", "l.d.resolution.forgetRemembered", "l.d.resolution.hiddenModes.display",
        "l.d.resolution.hiddenModes.try", "l.d.resolution.scaleMatch.reference",
        "l.d.resolution.scaleMatch.tolerance", "l.d.resolution.scaleMatch.preview", "l.d.resolution.scaleMatch.apply",
        // l.d.brightness.
        "l.d.brightness.display", "l.d.brightness.slider", "l.d.brightness.snapMarks", "l.d.brightness.method",
        "l.d.brightness.use", "l.d.brightness.switchover", "l.d.brightness.switchoverValue",
        "l.d.brightness.minHardware", "l.d.brightness.gammaStatus", "l.d.brightness.gammaAskAgain",
        "l.d.brightness.nits.now", "l.d.brightness.nits.custom", "l.d.brightness.nits.min", "l.d.brightness.nits.max",
        "l.d.brightness.nits.peak", "l.d.brightness.showNits", "l.d.brightness.xdr.enabled",
        "l.d.brightness.xdr.customMax", "l.d.brightness.xdr.max", "l.d.brightness.xdr.test",
        "l.d.brightness.xdr.globalMax", "l.d.brightness.xdr.method", "l.d.brightness.xdr.batteryFloor",
        "l.d.brightness.xdr.pauseOnLowPower", "l.d.brightness.xdr.detent", "l.d.brightness.sync.enabled",
        "l.d.brightness.sync.source", "l.d.brightness.sync.mode", "l.d.brightness.sync.follow",
        "l.d.brightness.sync.offset", "l.d.brightness.sync.externalChanges", "l.d.brightness.restoreMode",
        "l.d.brightness.smoothTransitions", "l.d.brightness.dimToBlack", "l.d.brightness.dimOnLockLevel",
        "l.d.brightness.featureOffRows",
        // l.d.color.
        "l.d.color.display", "l.d.color.suspend", "l.d.color.suspendAll", "l.d.color.contrast", "l.d.color.gamma",
        "l.d.color.gain", "l.d.color.temperature", "l.d.color.blackLevel", "l.d.color.whiteLevel", "l.d.color.invert",
        "l.d.color.rgbGain.red", "l.d.color.rgbGain.green", "l.d.color.rgbGain.blue", "l.d.color.rgbGamma.red",
        "l.d.color.rgbGamma.green", "l.d.color.rgbGamma.blue", "l.d.color.resetDisplay", "l.d.color.profile",
        "l.d.color.profile.showInFinder", "l.d.color.profile.openColorSync", "l.d.color.profile.restorePrevious",
        "l.d.color.applePreset", "l.d.color.autoBrightness", "l.d.color.menuBarStrip", "l.d.color.cornerRadiusTop",
        "l.d.color.cornerRadiusBottom", "l.d.color.allowGammaWithCustomProfile", "l.d.color.nightShift",
        "l.d.color.nightShiftWarmth",
        // l.d.ddc.
        "l.d.ddc.readback", "l.d.ddc.readbackInterval", "l.d.ddc.restoreOnWake", "l.d.ddc.display", "l.d.ddc.enabled",
        "l.d.ddc.info", "l.d.ddc.readCapabilities", "l.d.ddc.checkConnection", "l.d.ddc.volume", "l.d.ddc.contrast",
        "l.d.ddc.vcp.use", "l.d.ddc.vcp.min", "l.d.ddc.vcp.max", "l.d.ddc.vcp.invert", "l.d.ddc.vcp.showInMenu",
        "l.d.ddc.vcp.readbackInterval", "l.d.ddc.input.name", "l.d.ddc.input.hide", "l.d.ddc.input.order",
        "l.d.ddc.input.switch", "l.d.ddc.input.add", "l.d.ddc.input.resetList", "l.d.ddc.power.state",
        "l.d.ddc.power.on", "l.d.ddc.power.standby", "l.d.ddc.power.standbyValue", "l.d.ddc.custom.list",
        "l.d.ddc.custom.add", "l.d.ddc.raw.code", "l.d.ddc.raw.value", "l.d.ddc.raw.read", "l.d.ddc.raw.send",
        "l.d.ddc.raw.unlockCode", "l.d.ddc.raw.unlock", "l.d.ddc.raw.lockAll", "l.d.ddc.timing.replyDelay",
        "l.d.ddc.timing.retries", "l.d.ddc.timing.writeTwice", "l.d.ddc.timing.ignoreChecksum",
        "l.d.ddc.timing.forgetFraming", "l.d.ddc.allowedWithoutAsking", "l.d.ddc.featureOffRows",
        // l.d.keys.
        "l.d.keys.permission.pane", "l.d.keys.permission.status", "l.d.keys.permission.grant",
        "l.d.keys.permission.retry", "l.d.keys.brightnessPolicy", "l.d.keys.brightnessAlsoSystem", "l.d.keys.target",
        "l.d.keys.steps", "l.d.keys.fineSteps", "l.d.keys.alternateKeys", "l.d.keys.volumePolicy",
        "l.d.keys.volumeAlsoSystem", "l.d.keys.muteAlsoSystem", "l.d.keys.perDisplay.keysEnabled",
        "l.d.keys.perDisplay.showVolumeOSD", "l.d.keys.perDisplay.audioDeviceName", "l.d.keys.modifiers",
        "l.d.keys.shortcutFilter", "l.d.keys.inputSlots",
        // l.d.osd.
        "l.d.osd.style", "l.d.osd.position", "l.d.osd.target", "l.d.osd.showValue", "l.d.osd.showNits",
        "l.d.osd.native", "l.d.osd.preview", "l.d.osd.broadcastName",
        // l.d.arrangement.
        "l.d.arrangement.canvas", "l.d.arrangement.snap", "l.d.arrangement.positionForm",
        "l.d.arrangement.mainDisplay", "l.d.arrangement.mirroring", "l.d.arrangement.rotation", "l.d.arrangement.hdr",
        "l.d.arrangement.underscan", "l.d.arrangement.underscanApply", "l.d.arrangement.powerSwitch",
        "l.d.arrangement.connect", "l.d.arrangement.connectAll", "l.d.arrangement.autoDisconnectWithoutDDC",
        "l.d.arrangement.ignoreForAutoDisconnect", "l.d.arrangement.preventSleep", "l.d.arrangement.featureOffRows",
        // l.d.protection.
        "l.d.protection.protect", "l.d.protection.saveProtected", "l.d.protection.fields", "l.d.protection.forgetAll",
        "l.d.protection.undoToast", "l.d.protection.layout.name", "l.d.protection.layout.save",
        "l.d.protection.layout.status", "l.d.protection.layout.applyAutomatically", "l.d.protection.layout.priority",
        "l.d.protection.layout.apply", "l.d.protection.layout.stopTrusting", "l.d.protection.layout.update",
        "l.d.protection.layout.move", "l.d.protection.layout.delete",
        // l.d.virtual.
        "l.d.virtual.connected", "l.d.virtual.edit", "l.d.virtual.delete", "l.d.virtual.new.shape",
        "l.d.virtual.new.create", "l.d.virtual.recipes", "l.d.virtual.bulk",
        "l.d.virtual.behavior.restoreLayoutAfterConnect", "l.d.virtual.behavior.reconnectAfterWake",
        "l.d.virtual.behavior.disconnectOnLock", "l.d.virtual.editor.name", "l.d.virtual.editor.aspect",
        "l.d.virtual.editor.fillSizes", "l.d.virtual.editor.diagonal", "l.d.virtual.editor.hiDPI",
        "l.d.virtual.editor.portrait", "l.d.virtual.editor.reconnect", "l.d.virtual.editor.hdr",
        "l.d.virtual.editor.refresh", "l.d.virtual.editor.sizes", "l.d.virtual.editor.associations",
        "l.d.virtual.smartHiDPI.enabled", "l.d.virtual.smartHiDPI.size", "l.d.virtual.smartHiDPI.hdr",
        // l.d.pip.
        "l.d.pip.intro", "l.d.pip.screenRecording", "l.d.pip.running.pause", "l.d.pip.running.show",
        "l.d.pip.running.crop", "l.d.pip.running.stop", "l.d.pip.running.bulk", "l.d.pip.config.start",
        "l.d.pip.config.edit", "l.d.pip.new", "l.d.pip.newStream", "l.d.pip.windows", "l.d.pip.editor.name",
        "l.d.pip.editor.showAs", "l.d.pip.editor.target", "l.d.pip.editor.autoStart", "l.d.pip.editor.delete",
        "l.d.pip.editor.level", "l.d.pip.editor.opacity", "l.d.pip.editor.clickThrough",
        "l.d.pip.editor.lockPosition", "l.d.pip.editor.lockAspect", "l.d.pip.editor.integerScaling",
        "l.d.pip.editor.showTitleBar", "l.d.pip.editor.snapToQuarters", "l.d.pip.editor.shadow",
        "l.d.pip.editor.resetPosition", "l.d.pip.editor.matchRefresh", "l.d.pip.editor.fps",
        "l.d.pip.editor.showCursor", "l.d.pip.editor.warpOnCommandClick", "l.d.pip.editor.crop",
        "l.d.pip.editor.rotation", "l.d.pip.editor.flip", "l.d.pip.editor.scaling", "l.d.pip.editor.size",
        "l.d.pip.editor.nativeMode", "l.d.pip.editor.lut", "l.d.pip.editor.filters", "l.d.pip.importLUT",
        "l.d.pip.privacy.prefixes", "l.d.pip.privacy.restoreDefaults", "l.d.pip.pauseWhenOccluded",
        "l.d.pip.stopHotkeyEnabled",
        // l.d.automation.
        "l.d.automation.hook.name", "l.d.automation.hook.enabled", "l.d.automation.hook.event",
        "l.d.automation.hook.display", "l.d.automation.hook.delay", "l.d.automation.hook.program",
        "l.d.automation.hook.choose", "l.d.automation.hook.arguments", "l.d.automation.action.name",
        "l.d.automation.action.showInMenu", "l.d.automation.action.cliAllowed", "l.d.automation.action.shortcut",
        "l.d.automation.action.program", "l.d.automation.action.arguments", "l.d.automation.action.runNow",
        "l.d.automation.action.delete",
        // l.d.names.
        "l.d.names.name", "l.d.names.useSystemName", "l.d.names.icon", "l.d.names.showInMenu", "l.d.names.menuOrder",
        "l.d.names.details", "l.d.names.edid.copyHex", "l.d.names.edid.copyBase64", "l.d.names.edid.export",
        "l.d.names.copySettingsFrom", "l.d.names.forget", "l.d.names.forgetAll",
        // l.d.safety.
        "l.d.safety.confirm", "l.d.safety.confirmSeconds", "l.d.safety.announceRecovery", "l.d.safety.panicHotkey",
        "l.d.safety.restoreAllNow", "l.d.safety.resume", "l.d.safety.helper.status", "l.d.safety.helper.canRevert",
        "l.d.safety.pendingConfirmation", "l.d.safety.undoJournal", "l.d.safety.allowedWithoutAsking",
        "l.d.safety.keptModes.forget", "l.d.safety.unavailable",
        // l.d.diagnostics.
        "l.d.diagnostics.copyReport", "l.d.diagnostics.export", "l.d.diagnostics.refresh", "l.d.diagnostics.report",
        // l.onboarding.
        "l.onboarding.modules", "l.onboarding.displayChips", "l.onboarding.hideMenuIcon", "l.onboarding.smartHiDPI",
        "l.onboarding.useTheseFeatures",
        // l.action.
        "l.action.c.brightnessUp", "l.action.c.brightnessDown", "l.action.c.brightnessUpFine",
        "l.action.c.brightnessDownFine", "l.action.c.volumeUp", "l.action.c.volumeDown", "l.action.c.volumeUpFine",
        "l.action.c.volumeDownFine", "l.action.c.mute", "l.action.c.contrastUp", "l.action.c.contrastDown",
        "l.action.c.contrastUpFine", "l.action.c.contrastDownFine", "l.action.c.gammaUp", "l.action.c.gammaDown",
        "l.action.c.gammaUpFine", "l.action.c.gammaDownFine", "l.action.c.temperatureUp",
        "l.action.c.temperatureDown", "l.action.c.temperatureUpFine", "l.action.c.temperatureDownFine",
        "l.action.c.invert", "l.action.c.colorReset", "l.action.c.colorSuspend", "l.action.c.menuBarStrip",
        "l.action.c.nightShiftToggle", "l.action.c.nightShiftUp", "l.action.c.nightShiftDown",
        "l.action.c.syncToggle", "l.action.c.xdrToggle", "l.action.c.xdrUp", "l.action.c.xdrDown",
        "l.action.c.ddcPowerOn", "l.action.c.ddcStandby", "l.action.c.inputSlot*", "l.action.d.resolutionUp",
        "l.action.d.resolutionDown", "l.action.d.hiDPIToggle", "l.action.d.nativeMode", "l.action.d.defaultMode",
        "l.action.d.nativeHalved", "l.action.d.resolutionUndo", "l.action.d.resolutionRedo", "l.action.d.notchToggle",
        "l.action.d.matchUI", "l.action.d.rotate", "l.action.d.hdrToggle", "l.action.d.setMain",
        "l.action.d.mirrorToggle", "l.action.d.toggleBuiltin", "l.action.d.connectAll", "l.action.d.disconnect",
        "l.action.d.disconnectAllButMain", "l.action.d.sleepPreventionToggle", "l.action.d.protectionToggle",
        "l.action.d.smartHiDPIToggle", "l.action.d.favorite*", "l.action.d.layout*", "l.action.d.virtualToggle*",
        "l.action.e.pipToggle.*", "l.action.e.pipToggleDisplay", "l.action.e.pipPickWindow", "l.action.e.pipPauseAll",
        "l.action.e.pipHideAll", "l.action.e.pipStopAll", "l.action.f.showPanel", "l.action.f.identify",
        "l.action.f.redetect", "l.action.f.copyDiagnostics", "l.action.b.restoreAll", "l.action.b.resumeAutomation",
        "l.action.a.custom.*",
        // l.menu.
        "l.menu.c.brightness.slider", "l.menu.c.brightness.method", "l.menu.c.ddc.volume", "l.menu.c.ddc.mute",
        "l.menu.c.ddc.contrast", "l.menu.c.ddc.input", "l.menu.c.ddc.power", "l.menu.c.ddc.custom",
        "l.menu.c.color.submenu", "l.menu.c.color.profiles", "l.menu.c.color.applePresets",
        "l.menu.c.color.autoBrightness", "l.menu.c.menuBarStrip.toggle", "l.menu.c.xdr.toggle",
        "l.menu.c.sync.toggle", "l.menu.c.tools.nightShift", "l.menu.d.resolutionSlider", "l.menu.d.resolutionMenu",
        "l.menu.d.matchUI", "l.menu.d.setMain", "l.menu.d.mirrorMenu", "l.menu.d.rotationMenu", "l.menu.d.hdrToggle",
        "l.menu.d.powerSwitch", "l.menu.d.disconnectItem", "l.menu.d.connectAll", "l.menu.d.connectAll.quick",
        "l.menu.d.disconnectAllButMain", "l.menu.d.arrange", "l.menu.d.underscanMenu", "l.menu.d.sleepPrevention",
        "l.menu.d.protection", "l.menu.d.layoutsMenu", "l.menu.d.layoutMatch", "l.menu.d.virtualMenu",
        "l.menu.d.smartHiDPI", "l.menu.b.restoreAll", "l.menu.b.restoreAll.quick", "l.menu.b.resumeAutomation",
        "l.menu.f.tools.identify", "l.menu.f.tools.redetect", "l.menu.f.tools.panel", "l.menu.f.quick.redetect",
        "l.menu.e.pip.display", "l.menu.e.pip.tools", "l.menu.a.custom.*",
        // l.menu.fixed.
        "l.menu.fixed.switcher.enableThumbnails", "l.menu.fixed.switcher.pressHint", "l.menu.fixed.switcher.gather",
        "l.menu.fixed.displays.header", "l.menu.fixed.displays.more", "l.menu.fixed.displays.moreResolution",
        "l.menu.fixed.displays.moreMute", "l.menu.fixed.tools.header", "l.menu.fixed.tools.moreFeatures",
        "l.menu.fixed.recentNotices", "l.menu.fixed.quickMenu", "l.menu.fixed.settings", "l.menu.fixed.quit",
        "l.menu.fixed.safeModeRow", "l.menu.fixed.upgradeCard",
    ]
}
