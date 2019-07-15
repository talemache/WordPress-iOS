import Foundation

/// Takes care of storing and accessing Gutenberg settings.
///
class GutenbergSettings {

    // MARK: - Enabled Editors Keys
    enum Key {
        static let enabled = "kUserDefaultsGutenbergEditorEnabled"
        // This key is already used to auto-enable gutenberg upon showing the informative dialog,
        // so we need to keep it as it is to get the value from previous users and avoid showing the dialog again.
        static let enabledOnce = "Gutenberg.InformativeDialog"
    }

    // MARK: - Internal variables
    fileprivate let database: KeyValueDatabase
    private let queue = DispatchQueue(label: "org.wordpress.post_editor_settings", qos: .background)

    // MARK: - Initialization
    init(database: KeyValueDatabase) {
        self.database = database
    }

    convenience init() {
        self.init(database: UserDefaults() as KeyValueDatabase)
    }

    // MARK: Public accessors

    /// True if gutenberg editor is currently enabled
    private(set) var isGutenbergEnabled: Bool {
        get {
            return database.bool(forKey: Key.enabled)
        }
        set(enabled) {
            if enabled {
                wasGutenbergEnabledOnce = true
            }
            database.set(enabled, forKey: Key.enabled)
        }
    }

    /// True if gutenberg editor has been enabled at least once
    var wasGutenbergEnabledOnce: Bool {
        get {
            return isGutenbergEnabled || database.bool(forKey: Key.enabledOnce)
        }
        set {
            database.set(newValue, forKey: Key.enabledOnce)
        }
    }

    func shouldAutoenableGutenberg(for post: AbstractPost) -> Bool {
        return  post.containsGutenbergBlocks() && !wasGutenbergEnabledOnce
    }

    func setGutenbergEnabledIfNeeded() {
        if isGutenbergEnabled == false {
            toggleGutenberg()
        }
    }

    func toggleGutenberg() {
        if isGutenbergEnabled {
            WPAppAnalytics.track(.appSettingsGutenbergDisabled)
            isGutenbergEnabled = false
        } else {
            WPAppAnalytics.track(.appSettingsGutenbergEnabled)
            isGutenbergEnabled = true
        }
        WPAnalytics.refreshMetadata()
    }

    // MARK: - Gutenberg Choice Logic

    /// Call this method to know if Gutenberg must be used for the specified post.
    ///
    /// - Parameters:
    ///     - post: the post that will be edited.
    ///
    /// - Returns: true if the post must be edited with Gutenberg.
    ///
    func mustUseGutenberg(for post: AbstractPost) -> Bool {
        if post.isContentEmpty() {
            // It's a new post
            return isGutenbergEnabled
        } else {
            // It's an existing post
            return post.containsGutenbergBlocks()
        }
    }

    // MARK: - Editor settings sync with remote

    /// Posts the current local editor setting to remote. This local setting will be set to all the user's blogs.
    ///
    func setToRemote() {
        let currentSettings: EditorSettings = isGutenbergEnabled ? .gutenberg : .aztec
        let allBlogs = getAllBlogs()
        let delay: TimeInterval = allBlogs.count > 5 ? 0.3 : 0;

        queue.async {
            allBlogs.forEach({ (blog) in
                self.postEditorSettings(currentSettings, to: blog)
                Thread.sleep(forTimeInterval: delay)
            })
        }
    }

    private func getAllBlogs() -> [Blog] {
        let blogService = BlogService(managedObjectContext: ContextManager.sharedInstance().mainContext)
        return blogService.blogsForAllAccounts() as? [Blog] ?? []
    }

    private func postEditorSettings(_ settings: EditorSettings, to blog: Blog) {
        guard
            let blogDotComId = blog.dotComID as? Int,
            let remoteAPI = blog.wordPressComRestApi()
        else {
            return
        }

        let service = EditorServiceRemote(wordPressComRestApi: remoteAPI)
        service.postDesignateMobileEditor(blogDotComId, editor: settings, success: { _ in }) { (error) in
            DDLogError("Failed to syncronize editor settings with error: \(error)")
        }
    }
}

@objc(GutenbergSettings)
class GutenbergSettingsBridge: NSObject {
    @objc
    static func isGutenbergEnabled() -> Bool {
        return GutenbergSettings().isGutenbergEnabled
    }
}
