# Pre-release checklist

`tools/scripts/release_checks.sh` runs the scripted items. The rest are manual.

- [ ] (script) irdb notice present in the built app, if irdb data is bundled;
      irdb issue link recorded in THIRD_PARTY.md
- [ ] (script) `dart run check_licenses` passes; THIRD_PARTY.md matches the
      in-app Licenses screen
- [ ] (script) bundle ID is not a `com.example` placeholder
- [ ] (script) no brand logo assets in the app bundle
- [ ] (script) only `{{PUBLISHER}}` appears as an organization name
- [ ] (manual) "Not affiliated" line in About and in the listings
- [ ] (manual) firmware source and LGPL notice published with the bridge release
- [ ] (manual) App Review video recorded (app_review_video.md)
- [ ] (manual) privacy manifest and required-reason APIs reviewed (M8)
- [ ] (manual) performance budgets measured on a mid-range phone (M8)
