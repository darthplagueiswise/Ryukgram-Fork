# FBSharedFramework reverse scan: QuickSnap + Dogfood persisted queries

Input framework used for this pass: `FBSharedFramework(26)` / Instagram 426-era FBSharedFramework.

## Target persisted operations

Dogfood/internal targets:

- `DogfoodingEligibilityQuery`
- `ExposeExperimentFromClientQuery`

QuickSnap / Instants targets:

- `IGQuickSnapGetQuickSnapsQuery`
- `IGQuickSnapGetHistoryQuery`
- `IGQuickSnapGetHistoryPaginatedQuery`
- `IGQuickSnapGetPromptsQuery`
- `IGQuickSnapBadgingInfoQuery`
- `IGQuickSnapUpdateBadgingStateMutation`
- `IGQuickSnapUpdateSeenStateMutation`
- `IGQuickSnapSendEmojiReactionMutation`
- `MSHGetQuickSnapsQuery`
- `MSHQuickSnapGetHistoryQuery`

## Reverse scan result

`ExposeExperimentFromClientQuery` is present as a framework literal and ObjC/GraphQL class surface:

- `ExposeExperimentFromClientQueryBuilder`
- `ExposeExperimentFromClientQueryResponse`
- `ExposeExperimentFromClientQueryResponseImpl`
- `xdtExposeExperimentFromClient`
- literal hits at file offsets observed in this framework: `0x1a283b8`, `0x1a7d5d7`, `0x1c3e92b`, `0x1cc3d6a`, `0x1f990ee`
- one data reference observed around `__DATA.__objc_const` at `0x28f7fd8`

`DogfoodingEligibilityQuery` was not found as a direct literal in this FBSharedFramework binary. It is present in the persisted query JSON catalog, so it must be resolved through the imported catalog rather than by string-xrefing FBSharedFramework.

The exact `IGQuickSnap*Query`, `IGQuickSnap*Mutation`, `MSHGetQuickSnapsQuery`, and `MSHQuickSnapGetHistoryQuery` operation names were not found as direct literals in this FBSharedFramework binary. They are present in `igios-instagram-schema_client-persist.json`, which means the persisted-query catalog is the correct source for `operation_name`, hashes and `client_doc_id`.

The framework does contain the real QuickSnap runtime/model/MC surfaces, including:

- `IGAPIQuickSnapData`
- `IGAPIQuickSnapEmojiReaction`
- `IGAPIQuickSnapEmojiReactionCount`
- `IGAPIQuickSnapPromptInfo`
- `IGAPIQuicksnapRecapMediaInfo`
- `XDTQuickSnapData`
- `XDTQuickSnapEmojiReaction`
- `XDTQuickSnapEmojiReactionCount`
- `XDTQuickSnapPromptInfo`
- `XDTQuicksnapRecapMediaInfo`
- `quick_snap_info`
- `quick_snap_emoji_reactions`
- `QUICK_SNAP`
- `QUICKSNAP_REPLY`
- `quick_snaps_from_author`
- `quick_snap_details`
- `_ig_ios_quick_snap`
- `_ig_ios_quick_snap_nux_v2`
- `_ig_ios_quicksnap_navigation_v3`
- `_ig_ios_quicksnap_consumption_v2`
- `_ig_ios_quicksnap_consumption_stack_improvements`
- `_ig_ios_instants_widget`
- `_ig_instants_hide`

## Implementation decision

Do not scan FBSharedFramework at runtime to discover these operation names. The correct model is:

1. Import `igios-instagram-schema_client-persist.json` once at build/runtime catalog load.
2. Index the complete JSON by `operation_name`, `client_doc_id`, `operation_name_hash`, `operation_text_hash`, `schema`, and category.
3. Use the catalog for GraphQL/persisted-query diagnostics and doc-id lookup.
4. Use MobileConfig/internal-use specifier hooks and Swift/ObjC eligibility hooks for actual QuickSnap UI/runtime gates.
5. Keep Dogfood/Internal toggles mapped to employee/test-user/internal-use MC gates and expose `ExposeExperimentFromClientQuery` through the catalog/browser for validation.

This matches the Instamoon/InstaEclipse-style division: persisted JSON is a mapping layer, not a replacement for every runtime eligibility gate.
