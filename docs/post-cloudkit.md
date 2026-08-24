# My app hadn't synced for months and nothing told me

*Draft. Publish on a blog, then submit to r/iOSProgramming and Hacker News as Show HN.*

---

I ship a small iOS app that keeps GitHub projects on a Kanban board. It uses SwiftData with
CloudKit, which is the part everyone recommends because it is nearly free: add the capability, mark
the container, and your users get sync across their devices without you running a server.

It had not synced for months. Not once. And at no point did anything — not the app, not Xcode, not
App Store Connect — say so.

Here is the whole failure, because every step of it is something you can hit.

## `save()` succeeds whether or not anything leaves the device

This is the root of it. `NSPersistentCloudKitContainer` mirrors your store in the background. A
local save is a local save: it returns successfully, the UI updates, the row is on disk. Whether
that row ever reached iCloud is a separate question nobody asks.

So a broken sync and a working sync look **identical from inside the app**. There is no error to
catch, because your code never made the failing call.

The fix is to listen:

```swift
NotificationCenter.default.addObserver(
    forName: NSPersistentCloudKitContainer.eventChangedNotification,
    object: nil, queue: .main
) { note in
    guard let event = note.userInfo?[
        NSPersistentCloudKitContainer.eventNotificationUserInfoKey
    ] as? NSPersistentCloudKitContainer.Event, event.endDate != nil else { return }
    if let error = event.error { /* now you know */ }
}
```

If you take one thing from this: **add that observer today**, and put whatever it reports somewhere
a human will see it. Not a `print`. Mine printed, in `DEBUG` only, to a console nobody was watching.

## "The operation couldn't be completed"

Once I was listening, the error arrived immediately — and said nothing:

```
The operation couldn't be completed. (CKErrorDomain error 2.)
```

Code 2 is `.partialFailure`: *some of your records failed*. Its `localizedDescription` is useless
by design, because the real information sits one level down, in `partialErrorsByItemID` — one error
per record. You have to unwrap it yourself:

```swift
let underlying = ckError.partialErrorsByItemID?.values.compactMap { $0 as? CKError } ?? []
```

Group those by code before showing them. The same cause repeated across forty records is one
problem, not forty.

## Production rejects unknown record types. It does not create them.

The actual cause: I had added a model. In the **Development** environment CloudKit generates schema
for you — write a record of a new type and the type appears. This is why it feels like magic during
development.

**Production does not.** An unknown record type is rejected. Your users' devices try to upload it,
fail, and carry on quietly.

The schema has to be promoted explicitly: CloudKit Console → Development → *Deploy Schema Changes*.
Two things about that button. It is **disabled in Production**, because Production is read-only —
if you are looking there, you are looking in the wrong place. And it can only deploy what exists in
Development, which brings us to the part that actually cost me the afternoon.

## Your debug builds may be writing to Production

Both of my build configurations shared one entitlements file:

```xml
<key>com.apple.developer.icloud-container-environment</key>
<string>Production</string>
```

Every build I had ever run on a device wrote to the production container. That has two
consequences, and the second is the nasty one:

1. Development work was writing into real user data.
2. **The Development schema never updated**, because nothing was ever written there. So when I
   finally went to deploy, there was nothing to deploy. The console showed six record types and my
   new one was in neither environment.

Debug needs its own entitlements file pointing at `Development`. While you are in there, check
`aps-environment` too — CloudKit signals changes over silent push, and a development-signed build
declaring `production` never receives them. That one explains a different symptom I had been
blaming on something else: remote changes only appeared when something forced a fetch.

## Relationships arrive separately from records

One more, because it produced the strangest bug of the lot: eight tasks that existed in the
database and were drawn on no screen at all.

CloudKit stores a to-one relationship as a reference synced independently of the records
themselves. A partial failure can land the record without landing its link. My board renders
columns and asks each one for its tasks, so a task whose `column` is nil is not misplaced — it is
invisible.

This is not preventable. It is why SwiftData insists every relationship be optional. What you can
do is repair it, so write down enough to make repair possible. I got lucky: a legacy `status`
field, which I had marked as deprecated because it duplicated the relationship, still held the
column's name from creation time. The redundant field I was planning to delete was the only
surviving evidence of intent.

## The checklist I wish I'd had

- Observe `eventChangedNotification` and surface failures **to the user**, not to a log.
- Unwrap `partialFailure`. Never show its `localizedDescription`.
- Separate entitlements per configuration: Debug → Development, Release → Production. Check
  `aps-environment` as well.
- After adding a `@Model` field: run a Debug build so Development generates the schema, verify the
  type appears there, deploy, then verify in Production.
- Adding fields is safe. **Removing one is not** — once deployed to Production, a field is
  permanent.
- Treat a nil relationship as expected, and keep enough redundant information to rebuild it.

None of this is exotic. It is all in the documentation somewhere. What made it cost months is that
every single failure mode was silent — and the default reading of silence is that everything works.
