// X(name, selector_cstring, label, arity, pref_key)
// Entries sharing a pref_key toggle together; only the first one carries the picker label.

#define RYG_DATE_FORMAT_ENTRIES(X) \
    X(mixed,      "formattedDateInMixedFormat",                                       "Feed posts",               0, "date_fmt_mixed") \
    X(rel,        "formattedDateRelativeToNow",                                       "Notes, comments, stories", 0, "date_fmt_notes_comments_stories") \
    X(shortRel,   "shortenedFormattedDateRelativeToNow",                              "",                         0, "date_fmt_notes_comments_stories") \
    X(shortMixed, "formattedDateInShortenedMixedFormat",                              "",                         0, "date_fmt_notes_comments_stories") \
    X(partRel,    "partiallyShortenedFormattedDateRelativeToNow",                     "",                         0, "date_fmt_notes_comments_stories") \
    X(partRelHs,  "partiallyShortenedFormattedDateRelativeToNowHideSeconds:options:", "",                         2, "date_fmt_notes_comments_stories") \
    X(shortRelHs, "shortenedFormattedDateRelativeToNowHideSeconds:",                  "DMs",                      1, "date_fmt_dms")

// Other NSDate formatters IG ships. Add one here if a surface still shows its own format.
//
// X(shortRelYears,            "shortenedFormattedDateRelativeToNowIncludeYears",                                          "Shortened relative (incl. years)",         0, "date_fmt_shortRelYears")
// X(shortRelOpts,             "shortenedFormattedDateRelativeToNowWithOptions:",                                          "Shortened relative (options)",             1, "date_fmt_shortRelOpts")
// X(shortRelFloor,            "shortenedFormattedDateRelativeToNowWithFloorDaysWeeks:",                                   "Shortened rel. (floor days/weeks)",        1, "date_fmt_shortRelFloor")
// X(mixedShortRelMDY,         "formattedDateInMixedShortenedRelativeAndMonthDayYearFormatWithThreshold:",                 "Mixed shortened + M/D/Y",                  1, "date_fmt_mixedShortRelMDY")
// X(relHs,                    "formattedDateRelativeToNowHideSeconds:",                                                   "Relative (hide seconds)",                  1, "date_fmt_relHs")
// X(relYearsHs,               "formattedDateRelativeToNowIncludingYearsHideSeconds:",                                     "Rel. incl. years (hide seconds)",          1, "date_fmt_relYearsHs")
// X(relHsFloor,               "formattedDateRelativeToNowHideSeconds:shouldFloorDaysWeeks:",                              "Relative (hide secs, floor)",              2, "date_fmt_relHsFloor")
// X(shortRelHsFloor,          "shortenedFormattedDateRelativeToNowHideSeconds:shouldFloorDaysWeeks:",                     "Shortened rel. (hide secs, floor)",        2, "date_fmt_shortRelHsFloor")
// X(shortRelHsFloorOpts,      "shortenedFormattedDateRelativeToNowHideSeconds:shouldFloorDaysWeeks:options:",             "Shortened rel. (hide secs, floor, opts)",  3, "date_fmt_shortRelHsFloorOpts")
// X(shortRelHsFloorYearsOpts, "shortenedFormattedDateRelativeToNowHideSeconds:shouldFloorDaysWeeks:includeYears:options:","Shortened rel. (full signature)",          4, "date_fmt_shortRelHsFloorYearsOpts")
