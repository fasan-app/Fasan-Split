## 0.1.87
- Better: In the browser the performance test measures scrolling against 60 frames per second, because Android and the browser set the rate of web pages. The report names the target rate.
- New: Menu rebuilt. Bottom: Group | Settlement | Friends. In “Group” pick “All”, “No group” or a group at the top; below it “Bills | Items”. “Settlement” shows the people and balances of the picked group, or all groups with balances if none is picked.
- New: Press and hold a bill and drag it onto a group name to move it there.

## 0.1.86
- New: The group has a header with the number of bills, total and people. The frame shows how many items are done, in progress or open. Tap the total for the breakdown, the people icon for balances.
- New: Switch “Bills | Items”. The items view lists every item of the group, grouped by bill, and only loads what you see.
- New: One line names open items and bills without a payer.

## 0.1.85
- New: In the browser, settings show the version, date and build of your page. The new entry "What's new" lists the latest changes.
- New: The performance report holds much more about device and browser (battery, memory, network, system settings, display Hz, build type).
## 0.1.84
- Fixed: The performance test no longer shows names from real bills, only invented ones.
- New: The report states the app's effect level. The test reminds you to use battery above 50 % with battery saver off.
## 0.1.83
- Better: The performance test keeps its preparation apart from the measurement and judges scrolling against your screen's frame rate (120 Hz).
- New: Three counter-samples show whether shadows, thumbnails or the row itself slow scrolling. The test takes about three minutes.
## 0.1.82
- Better: In the browser, group messages are checked and signed about 100 times faster. This was the likely cause of the stutter.
- Better: Each message is checked once, not again on every reconnect.
- New: The performance test takes about two minutes, uses thumbnails, group checks and finger-speed swipes, shows the time since start and gives a verdict.
## 0.1.81
- Fixed: In the browser “Check for updates now” really looks for a new build and reloads the page. Your login stays.
- Better: In the browser it shows the real build (“Build abc1234”) instead of “Version 0.1.0”.
- New: The performance test also measures a list of 500 items.
## 0.1.80
- New: “Performance test” in the settings under Diagnostics measures stutter with made-up data and makes a report to share.
- New: A counter on the thumbnail shows how much others changed. The bill lists “New since your last visit” with name and change.
- Better: Bills show only icon, date and people in the second line. The name has more room.
- Better: Items show people and icons in their own line.
- Better: Frames of bill, items and payer are the same.
## 0.1.79
- New: In a bill's history, “Bring back an earlier state” restores a member's last state.
## 0.1.78
- Fixed: The shared bill wins over the local copy at start. Old states no longer overwrite it.
- Better: The bill list only builds visible tiles and stutters less.
- New: The history shows the time and app version of the writer.
- New: Without WebGL in the browser the app shows a hint.
## 0.1.77
- New: "About" lists the licences of all bundled parts.
- Better: The web page reloads itself when a new version is out.
- Better: The app is smoother, costly effects are now off.
- New: A bill is no longer green without a payer.
- New: Too many pieces handed out show the item in yellow.
## 0.1.76
- New: The filter reads "All items" while it is switched on.
## 0.1.73
- New: A coloured frame shows whether an item is still open.
- New: "Only open items" hides what is already done.
- New: Lock items and bills with the padlock.
- New: Enter payments and loans in the group.
- New: Find the guide and tips in Settings.
