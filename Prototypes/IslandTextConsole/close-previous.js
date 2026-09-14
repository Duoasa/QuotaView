// Run with osascript -l JavaScript. Uses AppKit application identity, never a broad process match.
ObjC.import('AppKit');

function run(argv) {
    if (argv.length !== 1) throw new Error('Expected the newly launched console app path.');
    const bundleID = 'com.quotaview.island-text-console';
    const canonical = path => ObjC.unwrap($(path).stringByResolvingSymlinksInPath);
    const keepPath = canonical(argv[0]);
    function running() {
        const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(bundleID);
        const result = [];
        for (let i = 0; i < apps.count; i++) result.push(apps.objectAtIndex(i));
        return result;
    }
    let current;
    for (let attempt = 0; attempt < 50; attempt++) {
        current = running().find(app => canonical(ObjC.unwrap(app.bundleURL.path)) === keepPath
            && Boolean(app.finishedLaunching));
        if (current) break;
        delay(0.1);
    }
    if (!current) throw new Error('New console did not finish launching; old consoles were kept.');

    const keepPID = Number(current.processIdentifier);
    const previous = running().filter(app => Number(app.processIdentifier) !== keepPID);
    const previousPIDs = previous.map(app => Number(app.processIdentifier));
    previous.forEach(app => { app.terminate; });
    let remaining = previousPIDs;
    for (let attempt = 0; attempt < 30 && remaining.length; attempt++) {
        remaining = running().map(app => Number(app.processIdentifier)).filter(pid => previousPIDs.includes(pid));
        if (remaining.length) delay(0.1);
    }
    if (remaining.length) throw new Error('Old consoles did not exit: ' + remaining.join(', '));
    return JSON.stringify({keptPID: keepPID, closedPIDs: previousPIDs});
}
