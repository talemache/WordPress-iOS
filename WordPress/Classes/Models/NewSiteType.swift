
/// A site type. There is already a SiteType enum in the codebase. To be renamed after we get rid of the old code
struct NewSiteType {
    let id: Identifier
    let title: String
    let subtitle: String
    let icon: URL
}
